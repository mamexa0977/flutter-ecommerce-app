import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.id,
    required this.title,
    this.season = 1,
    this.episode = 1,
    this.resourceId,
  });
  final String id, title;
  final int season, episode;
  final String? resourceId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);

  PlayInfo? _info;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Sets raw libmpv options. Safe no-op on platforms without them.
  Future<void> _mpv(String key, String value) async {
    if (kIsWeb) return;
    try {
      await (_player.platform as dynamic).setProperty(key, value);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await ref.read(apiClientProvider).play(
            widget.id,
            season: widget.season,
            episode: widget.episode,
            resourceId: widget.resourceId,
          );

      // Same CDN requirements the backend's mpv launcher uses.
      await _mpv('ytdl', 'no');
      final ua = info.headers['User-Agent'];
      final ref_ = info.headers['Referer'];
      if (ua != null) await _mpv('user-agent', ua);
      if (ref_ != null) await _mpv('referrer', ref_);
      final cookie = info.headers['Cookie'];
      // DASH sub-requests do not inherit http-header-fields; pass to the demuxer too.
      if (cookie != null && info.url.contains('.mpd')) {
        await _mpv('demuxer-lavf-o', 'headers=Cookie: $cookie');
      }

      await _player.open(Media(info.url, httpHeaders: info.headers), play: true);

      if (info.subtitleUrl != null) {
        try {
          await _player.setSubtitleTrack(SubtitleTrack.uri(info.subtitleUrl!));
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = _info?.subtitles ?? const <SubtitleItem>[];
    final subtitle = widget.season > 1 || widget.episode > 1
        ? 'S${widget.season} · E${widget.episode}'
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (subs.isNotEmpty)
            PopupMenuButton<SubtitleItem>(
              icon: const Icon(Icons.subtitles_outlined),
              tooltip: 'Subtitles',
              onSelected: (s) => _player.setSubtitleTrack(s.url.isEmpty
                  ? SubtitleTrack.no()
                  : SubtitleTrack.uri(s.url, title: s.label)),
              itemBuilder: (_) => [
                const PopupMenuItem(value: SubtitleItem('', 'Off'), child: Text('Off')),
                for (final s in subs) PopupMenuItem(value: s, child: Text(s.label)),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _loading
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Finding the best stream…', style: TextStyle(color: Colors.white70)),
                  ]))
                : _error != null
                    ? ErrorView(_error!, onRetry: _load)
                    : Video(controller: _video),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(subtitle, style: const TextStyle(color: Colors.white70)),
            ),
        ]),
      ),
    );
  }
}
