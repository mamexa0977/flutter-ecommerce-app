import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../core/watch_history.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class _SectionRow extends StatelessWidget {
  const _SectionRow(this.section);
  final Section section;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(section.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: 235,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: section.items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 125, child: MovieCard(section.items[i])),
        ),
      ),
    ]);
  }
}

/// "Continue watching" row (local history, newest first).
class _ContinueRow extends ConsumerWidget {
  const _ContinueRow(this.items);
  final List<HistoryEntry> items;

  String _sub(HistoryEntry e) {
    final ep = e.series ? 'S${e.season} \u00B7 E${e.episode}' : '';
    final String left;
    if (e.positionMs > 15000 && e.durationMs > 0) {
      final mins = ((e.durationMs - e.positionMs) / 60000).ceil();
      left = '$mins min left';
    } else {
      left = 'Up next';
    }
    return [if (ep.isNotEmpty) ep, left].join(' \u00B7 ');
  }

  void _options(BuildContext context, WidgetRef ref, HistoryEntry e) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Details'),
            onTap: () {
              Navigator.pop(sheet);
              context.push('/detail/${e.id}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Start over'),
            onTap: () {
              Navigator.pop(sheet);
              context.push(playLocation(e.id,
                  title: e.title,
                  season: e.season,
                  episode: e.episode,
                  resourceId: e.resourceId,
                  fresh: true));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remove from history'),
            onTap: () {
              Navigator.pop(sheet);
              ref.read(watchHistoryProvider.notifier).remove(e.id);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Row(children: [
          const Expanded(
            child: Text('Continue watching',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Clear watch history?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(d);
                      ref.read(watchHistoryProvider.notifier).clear();
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            child: const Text('Clear'),
          ),
        ]),
      ),
      SizedBox(
        height: 235,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final e = items[i];
            return SizedBox(
              width: 125,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => context.push(playLocation(e.id,
                    title: e.title,
                    season: e.season,
                    episode: e.episode,
                    resourceId: e.resourceId)),
                onLongPress: () => _options(context, ref, e),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Stack(fit: StackFit.expand, children: [
                      Poster(e.cover),
                      const Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            size: 40, color: Colors.white70),
                      ),
                      if (e.progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(10)),
                            child: LinearProgressIndicator(
                                value: e.progress, minHeight: 4),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text(e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text(_sub(e),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white54)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _tab = feedTabs.keys.first;

  @override
  Widget build(BuildContext context) {
    final endpoint = feedTabs[_tab]!;
    final feed = ref.watch(feedProvider(endpoint));
    final history = ref.watch(watchHistoryProvider);
    final showContinue = _tab == feedTabs.keys.first && history.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MovieBox', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in feedTabs.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: t == _tab,
                      onSelected: (_) => setState(() => _tab = t),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView('$e', onRetry: () => ref.invalidate(feedProvider(endpoint))),
        data: (sections) => sections.isEmpty
            ? ErrorView('Nothing to show here yet.', onRetry: () => ref.invalidate(feedProvider(endpoint)))
            : RefreshIndicator(
                onRefresh: () => ref.refresh(feedProvider(endpoint).future),
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  itemCount: sections.length + (showContinue ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (showContinue && i == 0) return _ContinueRow(history);
                    return _SectionRow(sections[i - (showContinue ? 1 : 0)]);
                  },
                ),
              ),
      ),
    );
  }
}