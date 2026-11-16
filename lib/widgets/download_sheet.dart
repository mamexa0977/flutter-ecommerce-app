import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/download_manager.dart';
import '../core/providers.dart';
import '../features/shell/main_shell.dart';
import '../models/downlaod_task.dart';

import '../models/models.dart';

/// Opens the download picker for a movie or a series.
Future<void> showDownloadSheet(
  BuildContext context, {
  required Movie movie,
  String? resourceId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF1A1A1D),
    builder: (_) => _DownloadSheet(movie: movie, resourceId: resourceId, rootContext: context),
  );
}

class _DownloadSheet extends ConsumerStatefulWidget {
  const _DownloadSheet({
    required this.movie,
    required this.resourceId,
    required this.rootContext,
  });
  final Movie movie;
  final String? resourceId;
  final BuildContext rootContext;

  @override
  ConsumerState<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<_DownloadSheet> {
  static const _defaults = ['1080p', '720p', '480p', '360p'];

  List<String> _qualities = _defaults;
  String _quality = '720p';
  bool _probing = true;
  int? _season;
  final Set<String> _selected = {}; // "season-episode"

  bool get _series => !widget.movie.isMovie;

  @override
  void initState() {
    super.initState();
    if (_series) {
      ref.read(episodesProvider(widget.movie.id).future).then((seasons) {
        if (!mounted) return;
        if (seasons.isEmpty) {
          setState(() => _probing = false);
          return;
        }
        setState(() => _season ??= seasons.first.number);
        _probe(seasons.first.number, seasons.first.episodes.first.number);
      }).catchError((_) {
        if (mounted) setState(() => _probing = false);
      });
    } else {
      _probe(1, 1);
    }
  }

  int _height(String q) => int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// Ask the backend which qualities really exist. The default list is shown
  /// meanwhile, so the user never has to wait for this.
  Future<void> _probe(int season, int episode) async {
    try {
      final info = await ref.read(apiClientProvider).play(widget.movie.id,
          season: season, episode: episode, resourceId: widget.resourceId);
      if (!mounted) return;
      final list = {...info.qualities}.toList()
        ..sort((a, b) => _height(b).compareTo(_height(a)));
      if (list.isNotEmpty) {
        final keep = list.indexWhere((q) => q.toLowerCase() == _quality.toLowerCase());
        final p720 = list.indexWhere((q) => _height(q) == 720);
        setState(() {
          _qualities = list;
          _quality = keep >= 0 ? list[keep] : (p720 >= 0 ? list[p720] : list.first);
        });
      }
    } catch (_) {
      // Keep the default list; the download itself will still try the choice.
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  String _k(int s, int e) => '$s-$e';

  Future<void> _start(List<Season> seasons) async {
    final items = <DownloadEpisode>[];
    if (_series) {
      for (final s in seasons) {
        for (final e in s.episodes) {
          if (_selected.contains(_k(s.number, e.number))) {
            items.add(DownloadEpisode(s.number, e.number, e.title));
          }
        }
      }
    } else {
      items.add(const DownloadEpisode(1, 1));
    }
    if (items.isEmpty) return;

    // Grab everything we need before the sheet closes.
    final messenger = ScaffoldMessenger.of(widget.rootContext);
    final router = GoRouter.of(widget.rootContext);
    final tab = ref.read(mainTabProvider.notifier);

    final added = await ref.read(downloadManagerProvider.notifier).enqueue(
          movie: widget.movie,
          items: items,
          quality: _quality,
          resourceId: widget.resourceId,
        );
    if (!mounted) return;
    Navigator.pop(context);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(added == 0
          ? 'Already in your downloads.'
          : added == 1
              ? 'Download started.'
              : '$added downloads started.'),
      action: SnackBarAction(
        label: 'VIEW',
        onPressed: () {
          tab.state = 2;
          router.go('/');
        },
      ),
    ));
  }

  String? _statusText(DownloadTask? t) {
    if (t == null) return null;
    switch (t.status) {
      case DownloadStatus.completed:
        return 'Downloaded';
      case DownloadStatus.downloading:
      case DownloadStatus.preparing:
        return 'Downloading\u2026';
      case DownloadStatus.queued:
        return 'In queue';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.failed:
        return 'Failed \u2013 tap to retry';
    }
  }

  DownloadTask? _taskOf(List<DownloadTask> tasks, int s, int e) {
    for (final t in tasks) {
      if (t.key == '${widget.movie.id}|$s|$e') return t;
    }
    return null;
  }

  List<Widget> _seasonSection(Season c, List<Season> seasons, List<DownloadTask> tasks) {
    final selectable = <Episode>[
      for (final e in c.episodes)
        if (_taskOf(tasks, c.number, e.number) == null ||
            _taskOf(tasks, c.number, e.number)!.status == DownloadStatus.paused ||
            _taskOf(tasks, c.number, e.number)!.status == DownloadStatus.failed)
          e,
    ];
    final allSelected = selectable.isNotEmpty &&
        selectable.every((e) => _selected.contains(_k(c.number, e.number)));

    return [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final s in seasons)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('Season ${s.number}'),
                  selected: s.number == c.number,
                  onSelected: (_) => setState(() => _season = s.number),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
        child: Row(children: [
          Text('${c.episodes.length} episodes',
              style: const TextStyle(color: Colors.white60)),
          const Spacer(),
          TextButton(
            onPressed: selectable.isEmpty
                ? null
                : () => setState(() {
                      for (final e in selectable) {
                        final k = _k(c.number, e.number);
                        if (allSelected) {
                          _selected.remove(k);
                        } else {
                          _selected.add(k);
                        }
                      }
                    }),
            child: Text(allSelected ? 'Clear' : 'Select all'),
          ),
        ]),
      ),
      Flexible(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: c.episodes.length,
          itemBuilder: (_, i) {
            final e = c.episodes[i];
            final t = _taskOf(tasks, c.number, e.number);
            final blocked = t != null && (t.isCompleted || t.isActive);
            final key = _k(c.number, e.number);
            final status = _statusText(t);
            return CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.trailing,
              value: blocked ? true : _selected.contains(key),
              onChanged: blocked
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          _selected.add(key);
                        } else {
                          _selected.remove(key);
                        }
                      }),
              title: Text(
                e.title.isEmpty ? 'Episode ${e.number}' : 'E${e.number}  ${e.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: status == null
                  ? null
                  : Text(status,
                      style: TextStyle(
                          fontSize: 11,
                          color: (t != null && t.isCompleted)
                              ? Colors.greenAccent
                              : Colors.white54)),
            );
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(downloadManagerProvider);
    final seasonsAsync = _series ? ref.watch(episodesProvider(widget.movie.id)) : null;
    final seasons = seasonsAsync?.asData?.value ?? const <Season>[];

    Season? cur;
    for (final s in seasons) {
      if (s.number == _season) cur = s;
    }
    cur ??= seasons.isNotEmpty ? seasons.first : null;

    final canDownload = _series ? _selected.isNotEmpty : true;
    final movieTask = _series ? null : _taskOf(tasks, 1, 1);
    final movieBlocked =
        movieTask != null && (movieTask.isCompleted || movieTask.isActive);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ---- header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Download',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(widget.movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),

        // ---- quality
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(children: [
            const Text('Quality', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            if (_probing)
              const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            if (_probing)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('checking\u2026',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final q in _qualities)
                ChoiceChip(
                  label: Text(q),
                  selected: q == _quality,
                  onSelected: (_) => setState(() => _quality = q),
                ),
            ]),
          ),
        ),

        // ---- series: seasons + episodes
        if (_series) ...[
          const Divider(height: 20),
          if (seasonsAsync == null || seasonsAsync.isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (seasons.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Text('No episodes found.', style: TextStyle(color: Colors.white70)),
                TextButton(
                  onPressed: () => ref.invalidate(episodesProvider(widget.movie.id)),
                  child: const Text('Retry'),
                ),
              ]),
            )
          else
            ..._seasonSection(cur!, seasons, tasks),
        ] else
          const SizedBox(height: 12),

        // ---- action button
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: Text(_series
                    ? (_selected.isEmpty
                        ? 'Select episodes'
                        : 'Download ${_selected.length} episode${_selected.length == 1 ? '' : 's'} \u00B7 $_quality')
                    : movieBlocked
                        ? (movieTask!.isCompleted ? 'Already downloaded' : 'Already downloading')
                        : 'Download \u00B7 $_quality'),
                onPressed: (canDownload && !movieBlocked) && (!_series || seasons.isNotEmpty)
                    ? () => _start(seasons)
                    : null,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}