import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../core/watch_history.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/download_sheet.dart';

class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  int? _season;
  String? _resourceId; // chosen audio/resource track

  void _play(Movie m, {int season = 1, int episode = 1, bool fresh = false}) {
    context.push(playLocation(widget.id,
        title: m.title,
        season: season,
        episode: episode,
        resourceId: _resourceId,
        fresh: fresh));
  }
  void _promptDownload(Movie m) =>
      showDownloadSheet(context, movie: m, resourceId: _resourceId);

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(detailProvider(widget.id));

    return Scaffold(
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SafeArea(
          child: Stack(children: [
            ErrorView('$e', onRetry: () => ref.invalidate(detailProvider(widget.id))),
            const BackButton(),
          ]),
        ),
        data: (d) => _body(d),
      ),
    );
  }

  Widget _body(MovieDetail d) {
    final m = d.movie;
    // Anything that is not a plain movie may have seasons/episodes.
    final episodes = m.isMovie ? null : ref.watch(episodesProvider(widget.id));
    // Where the user stopped last time (null = never watched).
    final HistoryEntry? h = ref
        .watch(watchHistoryProvider)
        .cast<HistoryEntry?>()
        .firstWhere((e) => e!.id == widget.id, orElse: () => null);
    final resuming = h != null && h.positionMs > 15000;
    final String playLabel;
    if (h == null) {
      playLabel = m.isMovie ? 'Play' : 'Play S${_season ?? 1} \u00B7 E1';
    } else if (m.isMovie) {
      playLabel = resuming ? 'Resume \u00B7 ${formatMs(h.positionMs)}' : 'Play';
    } else {
      playLabel = resuming
          ? 'Resume S${h.season} \u00B7 E${h.episode} \u00B7 ${formatMs(h.positionMs)}'
          : 'Play S${h.season} \u00B7 E${h.episode}';
    }
    final meta = [
      if (m.year != 'N/A') m.year,
      if (m.runtime != null && m.runtime!.isNotEmpty) m.runtime!,
    ].join('  \u2022  ');

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        expandedHeight: 360,
        flexibleSpace: FlexibleSpaceBar(
          title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          background: Stack(fit: StackFit.expand, children: [
            Poster(m.cover, radius: 0),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF0E0E10)],
                ),
              ),
            ),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList.list(children: [
          Row(children: [
            if (m.score != 'N/A') ...[
              const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
              const SizedBox(width: 4),
              Text(m.score, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
            ],
            Text(meta, style: const TextStyle(color: Colors.white60)),
          ]),
          const SizedBox(height: 16),
          // Replace your current single play button block with this Row
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(playLabel),
                  onPressed: () => h == null
                      ? _play(m, season: _season ?? 1, episode: 1)
                      : _play(m, season: h.season, episode: h.episode),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download'),
                onPressed: () => _promptDownload(m),
              ),
            ],
          ),
          // SizedBox(
          //   width: double.infinity,
          //   child: FilledButton.icon(
          //     icon: const Icon(Icons.play_arrow_rounded),
          //     label: Text(playLabel),
          //     onPressed: () => h == null
          //         ? _play(m, season: _season ?? 1, episode: 1)
          //         : _play(m, season: h.season, episode: h.episode),
          //   ),
          // ),
          if (h != null && resuming)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _play(m, season: h.season, episode: h.episode, fresh: true),
                child: const Text('Start over'),
              ),
            ),
          if (m.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(m.description, style: const TextStyle(height: 1.4, color: Colors.white70)),
          ],
          if (d.languages.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Audio / versions', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final l in d.languages)
                if (l.type == 'dub' && l.subjectId != null)
                  ActionChip(
                    avatar: const Icon(Icons.open_in_new, size: 16),
                    label: Text(l.name),
                    onPressed: () => context.push('/detail/${l.subjectId}'),
                  )
                else if (l.resourceId != null)
                  ChoiceChip(
                    label: Text(l.name),
                    selected: _resourceId == l.resourceId,
                    onSelected: (sel) =>
                        setState(() => _resourceId = sel ? l.resourceId : null),
                  ),
            ]),
          ],
        ]),
      ),
      if (episodes != null) ..._episodeSlivers(m, episodes),
      if (d.cast.isNotEmpty) SliverToBoxAdapter(child: _Cast(d.cast)),
      if (d.collection.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('In this collection', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SizedBox(
                height: 235,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: d.collection.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(width: 125, child: MovieCard(d.collection[i])),
                ),
              ),
            ]),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);
  }

  List<Widget> _episodeSlivers(Movie m, AsyncValue<List<Season>> episodes) {
    return episodes.when<List<Widget>>(
      loading: () => [
        const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
      ],
      error: (e, _) => [SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Text('Episodes: $e')))],
      data: (seasons) {
        if (seasons.isEmpty) return const <Widget>[];
        final current = seasons.firstWhere(
          (s) => s.number == (_season ?? seasons.first.number),
          orElse: () => seasons.first,
        );
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Text('Episodes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                DropdownButton<int>(
                  value: current.number,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final s in seasons)
                      DropdownMenuItem(value: s.number, child: Text('Season ${s.number}')),
                  ],
                  onChanged: (v) => setState(() => _season = v),
                ),
              ]),
            ),
          ),
          SliverList.builder(
            itemCount: current.episodes.length,
            itemBuilder: (_, i) {
              final e = current.episodes[i];
              HistoryEntry? hist;
              for (final x in ref.watch(watchHistoryProvider)) {
                if (x.matches(widget.id, current.number, e.number)) hist = x;
              }
              final prog = (hist != null && hist.positionMs > 15000) ? hist.progress : 0.0;
              return ListTile(
                leading: CircleAvatar(
                    backgroundColor: Colors.white10, child: Text('${e.number}')),
                title: Text(e.title.isEmpty ? 'Episode ${e.number}' : e.title),
                subtitle: prog > 0
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(value: prog, minHeight: 3),
                      )
                    : null,
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () => _play(m, season: current.number, episode: e.number),
              );
            },
          ),
        ];
      },
    );
  }
}

class _Cast extends StatelessWidget {
  const _Cast(this.cast);
  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Cast', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final c = cast[i];
              return SizedBox(
                width: 76,
                child: Column(children: [
                  ClipOval(
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: Poster(c.avatar.isEmpty ? null : c.avatar, radius: 30),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(c.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}