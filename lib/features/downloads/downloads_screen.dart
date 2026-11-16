import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/download_manager.dart';
import '../../core/routes.dart';
import '../../models/downlaod_task.dart';
import '../../widgets/common.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    // Group by title (a series = one card with its episodes).
    final groups = <String, List<DownloadTask>>{};
    for (final t in tasks) {
      groups.putIfAbsent(t.id, () => []).add(t);
    }
    final ordered = groups.values.toList()
      ..sort((a, b) {
        // Newest activity first.
        final an = a.map((t) => t.createdAt).reduce((x, y) => x > y ? x : y);
        final bn = b.map((t) => t.createdAt).reduce((x, y) => x > y ? x : y);
        return bn.compareTo(an);
      });

    final used = tasks.fold<int>(0, (sum, t) => sum + t.received);
    final hasActive = tasks.any((t) => t.isActive);
    final hasStopped = tasks.any(
        (t) => t.status == DownloadStatus.paused || t.status == DownloadStatus.failed);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (hasActive)
            IconButton(
              tooltip: 'Pause all',
              icon: const Icon(Icons.pause_circle_outline),
              onPressed: manager.pauseAll,
            ),
          if (!hasActive && hasStopped)
            IconButton(
              tooltip: 'Resume all',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: manager.resumeAll,
            ),
        ],
      ),
      body: tasks.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${tasks.length} item${tasks.length == 1 ? '' : 's'} \u00B7 ${DownloadTask.formatBytes(used)} on this phone',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                for (final g in ordered) _Group(g),
              ],
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.white24),
          SizedBox(height: 12),
          Text('Nothing downloaded yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text(
            'Open any movie or series and tap Download.\nDownloaded titles play without internet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.4),
          ),
        ]),
      ),
    );
  }
}

class _Group extends ConsumerWidget {
  const _Group(this.items);
  final List<DownloadTask> items;

  Future<void> _confirmDeleteTitle(BuildContext context, WidgetRef ref) async {
    final first = items.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete ${first.title}?'),
        content: Text(items.length == 1
            ? 'The downloaded file will be removed from this phone.'
            : 'All ${items.length} downloaded episodes will be removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(downloadManagerProvider.notifier).removeTitle(first.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = items.first;
    final series = first.isSeries;
    final sorted = [...items]..sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.episode.compareTo(b.episode);
      });
    final done = items.where((t) => t.isCompleted).length;
    final size = items.fold<int>(0, (sum, t) => sum + t.received);

    return Card(
      color: const Color(0xFF1A1A1D),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // ---- title header
        InkWell(
          onTap: series ? null : () => _play(context, first),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 64, height: 92, child: Poster(first.cover)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(first.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    series
                        ? '$done of ${items.length} episodes \u00B7 ${DownloadTask.formatBytes(size)}'
                        : '${first.quality} \u00B7 ${DownloadTask.formatBytes(size)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  if (!series) ...[
                    const SizedBox(height: 10),
                    _Status(first),
                  ],
                ]),
              ),
              if (!series) _TaskButton(first),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                onSelected: (v) {
                  if (v == 'delete') _confirmDeleteTitle(context, ref);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
          ),
        ),

        // ---- episodes (series only)
        if (series)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: items.any((t) => !t.isCompleted),
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              title: const Text('Episodes', style: TextStyle(fontSize: 13)),
              children: [for (final t in sorted) _EpisodeRow(t)],
            ),
          ),
      ]),
    );
  }
}

void _play(BuildContext context, DownloadTask t) {
  final path = t.filePath;
  if (!t.isCompleted || path == null) return;
  context.push(playLocation(t.id,
      title: t.title,
      season: t.season,
      episode: t.episode,
      resourceId: t.resourceId,
      localPath: path));
}

class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow(this.t);
  final DownloadTask t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      onTap: t.isCompleted ? () => _play(context, t) : null,
      title: Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _Status(t),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _TaskButton(t),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white54),
          onPressed: () => ref.read(downloadManagerProvider.notifier).remove(t.key),
        ),
      ]),
    );
  }
}

/// Progress bar + one line of text for any state.
class _Status extends StatelessWidget {
  const _Status(this.t);
  final DownloadTask t;

  @override
  Widget build(BuildContext context) {
    switch (t.status) {
      case DownloadStatus.completed:
        return Text('Downloaded \u00B7 ${t.quality} \u00B7 ${DownloadTask.formatBytes(t.received)}',
            style: const TextStyle(color: Colors.greenAccent, fontSize: 12));
      case DownloadStatus.failed:
        return Text(t.error ?? 'Download failed',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12));
      case DownloadStatus.queued:
        return const Text('Waiting in queue\u2026',
            style: TextStyle(color: Colors.white54, fontSize: 12));
      case DownloadStatus.preparing:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('Preparing\u2026 (finding the stream)',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          SizedBox(height: 6),
          LinearProgressIndicator(minHeight: 3),
        ]);
      case DownloadStatus.paused:
      case DownloadStatus.downloading:
        final paused = t.status == DownloadStatus.paused;
        final p = t.progress;
        final sizeText = t.total > 0
            ? '${DownloadTask.formatBytes(t.received)} / ${DownloadTask.formatBytes(t.total)}'
            : DownloadTask.formatBytes(t.received);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                paused ? 'Paused \u00B7 $sizeText' : '${t.speedText} \u00B7 $sizeText',
                style: TextStyle(
                    color: paused ? Colors.white54 : Colors.lightBlueAccent, fontSize: 12),
              ),
            ),
            if (p != null)
              Text('${(p * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: p,
            minHeight: 3,
            backgroundColor: Colors.white10,
          ),
        ]);
    }
  }
}

/// Play / pause / resume / retry depending on the state.
class _TaskButton extends ConsumerWidget {
  const _TaskButton(this.t);
  final DownloadTask t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.read(downloadManagerProvider.notifier);
    switch (t.status) {
      case DownloadStatus.completed:
        return IconButton(
          tooltip: 'Play',
          icon: const Icon(Icons.play_circle_fill_rounded, size: 30),
          onPressed: () => _play(context, t),
        );
      case DownloadStatus.downloading:
      case DownloadStatus.preparing:
      case DownloadStatus.queued:
        return IconButton(
          tooltip: 'Pause',
          icon: const Icon(Icons.pause_circle_outline, size: 28),
          onPressed: () => m.pause(t.key),
        );
      case DownloadStatus.paused:
        return IconButton(
          tooltip: 'Resume',
          icon: const Icon(Icons.play_circle_outline, size: 28),
          onPressed: () => m.resume(t.key),
        );
      case DownloadStatus.failed:
        return IconButton(
          tooltip: 'Retry',
          icon: const Icon(Icons.refresh_rounded, size: 28),
          onPressed: () => m.resume(t.key),
        );
    }
  }
}