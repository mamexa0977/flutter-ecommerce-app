
// import 'dart:async';

// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:media_kit/media_kit.dart';
// import 'package:media_kit_video/media_kit_video.dart';

// import '../../core/providers.dart';
// import '../../core/routes.dart';
// import '../../core/subtitle_service.dart';
// import '../../core/watch_history.dart';
// import '../../models/models.dart';
// import '../../widgets/common.dart';
// import 'subtitle_sheet.dart';

// /// One entry in the quality menu.
// class _QOpt {
//   const _QOpt(this.label, {this.serverQuality, this.track, this.trackMode = false});
//   final String label;
//   final String? serverQuality; // reload the stream from the backend with this quality
//   final VideoTrack? track; // switch the video track inside the current stream
//   final bool trackMode; // true for the "Auto" entry of the track list
// }

// class _Ep {
//   const _Ep(this.season, this.episode);
//   final int season, episode;
// }

// class PlayerScreen extends ConsumerStatefulWidget {
//   const PlayerScreen({
//     super.key,
//     required this.id,
//     required this.title,
//     this.season = 1,
//     this.episode = 1,
//     this.resourceId,
//     this.fresh = false,
//   });
//   final String id, title;
//   final int season, episode;
//   final String? resourceId;

//   /// true = ignore the saved position and start from the beginning.
//   final bool fresh;

//   @override
//   ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
// }

// class _PlayerScreenState extends ConsumerState<PlayerScreen>
//     with WidgetsBindingObserver {
//   /// How many player screens are alive (a "next episode" replace briefly has 2).
//   static int _live = 0;

//   late final Player _player = Player();
//   late final VideoController _video = VideoController(_player);
//   final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
//   late final WatchHistory _history;

//   PlayInfo? _info;
//   String? _error;
//   bool _loading = true;

//   String? _quality; // quality requested from the backend (null = its default)
//   String? _trackId; // chosen in-stream track (null = auto)
//   List<VideoTrack> _tracks = const [];

//   // --- subscriptions / timers
//   StreamSubscription<Tracks>? _tracksSub;
//   StreamSubscription<bool>? _playingSub;
//   StreamSubscription<bool>? _completedSub;
//   Timer? _saveTimer;
//   Timer? _hideTimer;
//   Timer? _flashTimer;
//   Timer? _seekTargetTimer;

//   // --- UI state
//   final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
//   final ValueNotifier<Duration?> _scrub = ValueNotifier(null);
//   final ValueNotifier<int?> _flash = ValueNotifier(null); // +/- seconds
//   double _speed = 1.0;
//   late double _subScale;
//   final List<SubtitleChoice> _downloaded = [];
//   String? _activeSub;
//   BoxFit _fit = BoxFit.contain;
//   double _tapX = 0;
//   Duration? _seekTarget;
//   bool? _lastLandscape;

//   // --- history / series info
//   Duration? _resumeFrom;
//   String? _cover;
//   bool _isSeries = false;
//   _Ep? _next;

//   bool get _mobile =>
//       !kIsWeb &&
//       (defaultTargetPlatform == TargetPlatform.android ||
//           defaultTargetPlatform == TargetPlatform.iOS);

//   // ------------------------------------------------------------------ life cycle

//   @override
//   void initState() {
//     super.initState();
//     _live++;
//     WidgetsBinding.instance.addObserver(this);
//     _history = ref.read(watchHistoryProvider.notifier);
//     _subScale = ref.read(subtitleServiceProvider).scale;

//     final saved = _history.latestFor(widget.id);
//     _cover = saved?.cover;
//     _isSeries = saved?.series ?? (widget.season > 1 || widget.episode > 1);
//     if (!widget.fresh &&
//         saved != null &&
//         saved.matches(widget.id, widget.season, widget.episode) &&
//         saved.positionMs > 15000) {
//       _resumeFrom = Duration(milliseconds: saved.positionMs);
//     }

//     // Adaptive streams (DASH/HLS) expose several resolutions as video tracks.
//     _tracksSub = _player.stream.tracks.listen((t) {
//       final byHeight = <int, VideoTrack>{};
//       for (final v in t.video) {
//         final h = v.h ?? 0;
//         if (v.id == 'auto' || v.id == 'no' || h <= 0) continue;
//         byHeight.putIfAbsent(h, () => v);
//       }
//       final list = byHeight.values.toList()
//         ..sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));
//       if (mounted) setState(() => _tracks = list);
//     });

//     _playingSub = _player.stream.playing.listen((p) {
//       if (p) {
//         _scheduleHide();
//       } else {
//         _saveNow();
//         _controlsVisible.value = true;
//       }
//     });
//     _completedSub = _player.stream.completed.listen((c) {
//       if (c) _onCompleted();
//     });
//     _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
//       if (_player.state.playing) _saveNow();
//     });

//     _prepareSeriesInfo();
//     _load(resume: _resumeFrom);
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _saveTimer?.cancel();
//     _hideTimer?.cancel();
//     _flashTimer?.cancel();
//     _seekTargetTimer?.cancel();
//     _tracksSub?.cancel();
//     _playingSub?.cancel();
//     _completedSub?.cancel();

//     // Save where we stopped. Deferred so we never change provider state while
//     // the widget tree is being torn down.
//     final pos = _player.state.position;
//     final dur = _player.state.duration;
//     scheduleMicrotask(() => _commitProgress(pos, dur));

//     _player.dispose();
//     _controlsVisible.dispose();
//     _scrub.dispose();
//     _flash.dispose();

//     _live--;
//     if (_live <= 0) {
//       _live = 0;
//       // Always give the phone back to the app in portrait / normal bars.
//       if (_mobile) {
//         SystemChrome.setPreferredOrientations(const []);
//         SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
//             overlays: SystemUiOverlay.values);
//       }
//     }
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state != AppLifecycleState.resumed) _saveNow();
//   }

//   // ------------------------------------------------------------------ history

//   void _saveNow() {
//     if (_loading || _info == null) return;
//     _commitProgress(_player.state.position, _player.state.duration);
//   }

//   void _commitProgress(Duration pos, Duration dur) {
//     if (_info == null || dur.inSeconds <= 0 || pos.inSeconds < 15) return;
//     final now = DateTime.now().millisecondsSinceEpoch;

//     // Watched (almost) to the end: forget it, or point to the next episode.
//     if (pos.inMilliseconds / dur.inMilliseconds > 0.95) {
//       final nx = _next;
//       if (nx != null) {
//         _history.record(HistoryEntry(
//           id: widget.id,
//           title: widget.title,
//           cover: _cover,
//           resourceId: widget.resourceId,
//           season: nx.season,
//           episode: nx.episode,
//           positionMs: 0,
//           durationMs: 0,
//           updatedAt: now,
//           series: true,
//         ));
//       } else {
//         _history.remove(widget.id);
//       }
//       return;
//     }

//     _history.record(HistoryEntry(
//       id: widget.id,
//       title: widget.title,
//       cover: _cover,
//       resourceId: widget.resourceId,
//       season: widget.season,
//       episode: widget.episode,
//       positionMs: pos.inMilliseconds,
//       durationMs: dur.inMilliseconds,
//       updatedAt: now,
//       series: _isSeries,
//     ));
//   }

//   /// Works out the cover / "is this a series" / "what is the next episode".
//   Future<void> _prepareSeriesInfo() async {
//     try {
//       if (_cover == null) {
//         final d = ref.read(detailProvider(widget.id)).asData?.value;
//         if (d != null) {
//           _cover = d.movie.cover;
//           _isSeries = _isSeries || !d.movie.isMovie;
//         }
//       }
//       if (!_isSeries) return;
//       final seasons = await ref.read(episodesProvider(widget.id).future);
//       if (!mounted) return;
//       final cur = seasons.indexWhere((s) => s.number == widget.season);
//       if (cur < 0) return;
//       final eps = seasons[cur].episodes;
//       final i = eps.indexWhere((e) => e.number == widget.episode);
//       _Ep? nx;
//       if (i >= 0 && i + 1 < eps.length) {
//         nx = _Ep(seasons[cur].number, eps[i + 1].number);
//       } else if (cur + 1 < seasons.length && seasons[cur + 1].episodes.isNotEmpty) {
//         nx = _Ep(seasons[cur + 1].number, seasons[cur + 1].episodes.first.number);
//       }
//       if (mounted) setState(() => _next = nx);
//     } catch (_) {
//       // Next-episode is a bonus feature; never break playback because of it.
//     }
//   }

//   void _goNext() {
//     final nx = _next;
//     if (nx == null || !mounted) return;
//     context.pushReplacement(playLocation(widget.id,
//         title: widget.title,
//         season: nx.season,
//         episode: nx.episode,
//         resourceId: widget.resourceId));
//   }

//   void _onCompleted() {
//     if (!mounted || _loading || _info == null) return;
//     if (_player.state.duration.inSeconds <= 0) return;
//     if (_next != null) {
//       _commitProgress(_player.state.duration, _player.state.duration);
//       _goNext();
//     } else {
//       _history.remove(widget.id);
//       _controlsVisible.value = true;
//     }
//   }

//   // ------------------------------------------------------------------ loading

//   /// Sets raw libmpv options. Safe no-op on platforms without them.
//   Future<void> _mpv(String key, String value) async {
//     if (kIsWeb) return;
//     try {
//       await (_player.platform as dynamic).setProperty(key, value);
//     } catch (_) {}
//   }

//   Future<void> _load({Duration? resume}) async {
//     setState(() {
//       _loading = true;
//       _error = null;
//       _trackId = null;
//       _tracks = const [];
//     });
//     try {
//       final info = await ref.read(apiClientProvider).play(
//             widget.id,
//             season: widget.season,
//             episode: widget.episode,
//             resourceId: widget.resourceId,
//             quality: _quality,
//           );

//       // Same CDN requirements the backend's mpv launcher uses.
//       await _mpv('ytdl', 'no');
//       final ua = info.headers['User-Agent'];
//       final referer = info.headers['Referer'];
//       if (ua != null) await _mpv('user-agent', ua);
//       if (referer != null) await _mpv('referrer', referer);
//       final cookie = info.headers['Cookie'];
//       // DASH sub-requests do not inherit http-header-fields; pass to the demuxer too.
//       if (cookie != null && info.url.contains('.mpd')) {
//         await _mpv('demuxer-lavf-o', 'headers=Cookie: $cookie');
//       }

//       await _player.open(
//         Media(
//           info.url,
//           httpHeaders: info.headers,
//           start: (resume != null && resume > Duration.zero) ? resume : null,
//         ),
//         play: true,
//       );
//       if (_speed != 1.0) await _player.setRate(_speed);

//       if (info.subtitleUrl != null) {
//         try {
//           await _player.setSubtitleTrack(SubtitleTrack.uri(info.subtitleUrl!));
//         } catch (_) {}
//       }
//       if (!mounted) return;
//       setState(() {
//         _info = info;
//         _loading = false;
//       });
//       _showControls();
//     } catch (e) {
//       if (!mounted) return;
//       setState(() {
//         _error = '$e';
//         _loading = false;
//       });
//     }
//   }

//   List<_QOpt> _qualityOptions() {
//     if (_tracks.length > 1) {
//       return [
//         const _QOpt('Auto', trackMode: true),
//         for (final t in _tracks) _QOpt('${t.h}p', track: t, trackMode: true),
//       ];
//     }
//     final q = _info?.qualities ?? const <String>[];
//     if (q.length > 1) {
//       return [const _QOpt('Default'), for (final x in q) _QOpt(x, serverQuality: x)];
//     }
//     return const [];
//   }

//   bool _isSelected(_QOpt o) {
//     if (o.trackMode) return _trackId == o.track?.id;
//     final current = _quality ?? _info?.quality;
//     if (o.serverQuality == null) return _quality == null;
//     return current?.toLowerCase() == o.serverQuality!.toLowerCase();
//   }

//   void _pick(_QOpt o) {
//     if (o.trackMode) {
//       setState(() => _trackId = o.track?.id);
//       _player.setVideoTrack(o.track ?? VideoTrack.auto());
//     } else {
//       _quality = o.serverQuality;
//       _load(resume: _player.state.position); // keep the current position
//     }
//     _showControls();
//   }

//   // ------------------------------------------------------------------ orientation / fullscreen

//   /// Keeps the system bars in sync with the real orientation, so the UI can
//   /// never end up "landscape without controls" like before.
//   void _syncChrome(bool landscape) {
//     if (!_mobile || _lastLandscape == landscape) return;
//     _lastLandscape = landscape;
//     if (landscape) {
//       SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
//     } else {
//       SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
//           overlays: SystemUiOverlay.values);
//     }
//   }

//   bool get _isLandscape =>
//       MediaQuery.of(context).orientation == Orientation.landscape;

//   Future<void> _toggleFullscreen() async {
//     if (!_mobile) return;
//     if (_isLandscape) {
//       await _exitFullscreen();
//     } else {
//       await SystemChrome.setPreferredOrientations(const [
//         DeviceOrientation.landscapeLeft,
//         DeviceOrientation.landscapeRight,
//       ]);
//     }
//     if (mounted) _showControls();
//   }

//   Future<void> _exitFullscreen() async {
//     // Force portrait first, then hand control back to the sensor/OS.
//     await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
//     await Future.delayed(const Duration(milliseconds: 700));
//     if (mounted) await SystemChrome.setPreferredOrientations(const []);
//   }

//   // ------------------------------------------------------------------ subtitles

//   Future<void> _openSubtitles() async {
//     _hideTimer?.cancel();
//     final choice = await showSubtitleSheet(
//       context,
//       title: widget.title,
//       series: _isSeries,
//       season: widget.season,
//       episode: widget.episode,
//       builtIn: _info?.subtitles ?? const <SubtitleItem>[],
//       downloaded: List.of(_downloaded),
//       activeLabel: _activeSub,
//       scale: _subScale,
//       onScale: (v) {
//         if (mounted) setState(() => _subScale = v);
//       },
//     );
//     if (!mounted) return;
//     if (choice != null) await _applySubtitle(choice);
//     if (mounted) _showControls();
//   }

//   Future<void> _applySubtitle(SubtitleChoice c) async {
//     try {
//       if (c.isOff) {
//         await _player.setSubtitleTrack(SubtitleTrack.no());
//       } else if (c.data != null) {
//         await _player.setSubtitleTrack(SubtitleTrack.data(c.data!,
//             title: c.label, language: c.language));
//         if (!_downloaded.any((d) => d.label == c.label)) _downloaded.add(c);
//       } else {
//         await _player.setSubtitleTrack(SubtitleTrack.uri(c.url!, title: c.label));
//       }
//       if (mounted) setState(() => _activeSub = c.isOff ? null : c.label);
//     } catch (_) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('Could not load this subtitle.')));
//       }
//     }
//   }

//   // ------------------------------------------------------------------ controls logic

//   void _showControls() {
//     _hideTimer?.cancel();
//     _controlsVisible.value = true;
//     _scheduleHide();
//   }

//   void _scheduleHide() {
//     _hideTimer?.cancel();
//     _hideTimer = Timer(const Duration(seconds: 3), () {
//       if (_player.state.playing && _scrub.value == null) {
//         _controlsVisible.value = false;
//       }
//     });
//   }

//   void _toggleControls() {
//     if (_controlsVisible.value) {
//       _hideTimer?.cancel();
//       _controlsVisible.value = false;
//     } else {
//       _showControls();
//     }
//   }

//   void _seekBy(int seconds) {
//     final dur = _player.state.duration;
//     var t = (_seekTarget ?? _player.state.position) + Duration(seconds: seconds);
//     if (t < Duration.zero) t = Duration.zero;
//     if (dur > Duration.zero && t > dur) t = dur;
//     _seekTarget = t;
//     _seekTargetTimer?.cancel();
//     _seekTargetTimer = Timer(const Duration(milliseconds: 900), () => _seekTarget = null);
//     _player.seek(t);

//     // Little "+10 s" bubble, accumulating while you keep tapping.
//     final current = _flash.value;
//     final same = current != null && (current < 0) == (seconds < 0);
//     _flash.value = (same ? current! : 0) + seconds;
//     _flashTimer?.cancel();
//     _flashTimer = Timer(const Duration(milliseconds: 800), () => _flash.value = null);
//   }

//   void _playPause() {
//     _player.playOrPause();
//     _showControls();
//   }

//   String _fmt(Duration d) => formatMs(d.inMilliseconds);

//   // ------------------------------------------------------------------ build

//   @override
//   Widget build(BuildContext context) {
//     final landscape = _mobile && _isLandscape;
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (mounted) _syncChrome(landscape);
//     });

//     final stage = _stage(landscape);

//     return PopScope(
//       // In landscape the back button first returns to portrait, then leaves.
//       canPop: !landscape,
//       onPopInvokedWithResult: (didPop, _) {
//         if (!didPop) _exitFullscreen();
//       },
//       child: Scaffold(
//         backgroundColor: Colors.black,
//         body: landscape
//             ? SizedBox.expand(child: stage)
//             : SafeArea(
//                 child: Column(children: [
//                   AspectRatio(aspectRatio: 16 / 9, child: stage),
//                   Expanded(child: _infoPanel()),
//                 ]),
//               ),
//       ),
//     );
//   }

//   /// Video + gestures + controls. Same widget in portrait and landscape.
//   Widget _stage(bool landscape) {
//     return Stack(fit: StackFit.expand, children: [
//       const ColoredBox(color: Colors.black),
//       if (_loading)
//         const Center(
//           child: Column(mainAxisSize: MainAxisSize.min, children: [
//             CircularProgressIndicator(),
//             SizedBox(height: 12),
//             Text('Finding the best stream\u2026',
//                 style: TextStyle(color: Colors.white70)),
//           ]),
//         )
//       else if (_error != null)
//         ErrorView(_error!, onRetry: () => _load(resume: _resumeFrom))
//       else ...[
//         Video(
//           key: _videoKey,
//           controller: _video,
//           controls: NoVideoControls,
//           fit: _fit,
//           fill: Colors.black,
//           subtitleViewConfiguration: SubtitleViewConfiguration(
//             style: TextStyle(
//               height: 1.35,
//               fontSize: (landscape ? 32.0 : 20.0) * _subScale,
//               color: Colors.white,
//               backgroundColor: const Color(0x99000000),
//             ),
//             textAlign: TextAlign.center,
//             padding: EdgeInsets.fromLTRB(16, 0, 16, landscape ? 64 : 32),
//           ),
//         ),
//         _gestureLayer(),
//         _bufferingSpinner(),
//         _flashBubble(),
//         _controlsOverlay(landscape),
//       ],
//       if (_loading || _error != null) _simpleBackBar(landscape),
//     ]);
//   }

//   Widget _simpleBackBar(bool landscape) => Align(
//         alignment: Alignment.topLeft,
//         child: SafeArea(
//           bottom: false,
//           child: IconButton(
//             color: Colors.white,
//             icon: const Icon(Icons.arrow_back),
//             onPressed: () => Navigator.of(context).maybePop(),
//           ),
//         ),
//       );

//   Widget _gestureLayer() => LayoutBuilder(builder: (_, c) {
//         return GestureDetector(
//           behavior: HitTestBehavior.opaque,
//           onTap: _toggleControls,
//           onDoubleTapDown: (d) => _tapX = d.localPosition.dx,
//           onDoubleTap: () => _seekBy(_tapX < c.maxWidth / 2 ? -10 : 10),
//         );
//       });

//   Widget _bufferingSpinner() => IgnorePointer(
//         child: StreamBuilder<bool>(
//           stream: _player.stream.buffering,
//           initialData: _player.state.buffering,
//           builder: (_, s) => s.data == true
//               ? const Center(child: CircularProgressIndicator())
//               : const SizedBox.shrink(),
//         ),
//       );

//   Widget _flashBubble() => IgnorePointer(
//         child: ValueListenableBuilder<int?>(
//           valueListenable: _flash,
//           builder: (_, v, __) {
//             if (v == null) return const SizedBox.shrink();
//             final left = v < 0;
//             return Align(
//               alignment: Alignment(left ? -0.6 : 0.6, 0),
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
//                 decoration: BoxDecoration(
//                   color: Colors.black54,
//                   borderRadius: BorderRadius.circular(40),
//                 ),
//                 child: Row(mainAxisSize: MainAxisSize.min, children: [
//                   Icon(left ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
//                       color: Colors.white),
//                   const SizedBox(width: 6),
//                   Text('${v.abs()} s',
//                       style: const TextStyle(
//                           color: Colors.white, fontWeight: FontWeight.w600)),
//                 ]),
//               ),
//             );
//           },
//         ),
//       );

//   // ------------------------------------------------------------------ controls overlay

//   Widget _controlsOverlay(bool landscape) {
//     return ValueListenableBuilder<bool>(
//       valueListenable: _controlsVisible,
//       builder: (_, visible, child) => IgnorePointer(
//         ignoring: !visible,
//         child: AnimatedOpacity(
//           opacity: visible ? 1 : 0,
//           duration: const Duration(milliseconds: 200),
//           child: child,
//         ),
//       ),
//       child: Stack(fit: StackFit.expand, children: [
//         // Dark gradients for readability. Ignores touches so taps reach the video.
//         const IgnorePointer(
//           child: DecoratedBox(
//             decoration: BoxDecoration(
//               gradient: LinearGradient(
//                 begin: Alignment.topCenter,
//                 end: Alignment.bottomCenter,
//                 colors: [
//                   Color(0xCC000000),
//                   Color(0x00000000),
//                   Color(0x00000000),
//                   Color(0xCC000000),
//                 ],
//                 stops: [0, 0.3, 0.65, 1],
//               ),
//             ),
//           ),
//         ),
//         // In landscape we are full screen, so respect notches / gesture bars.
//         SafeArea(
//           top: landscape,
//           bottom: landscape,
//           left: landscape,
//           right: landscape,
//           child: Column(children: [
//             _topBar(),
//             Expanded(child: Center(child: _centerButtons())),
//             _bottomBar(landscape),
//           ]),
//         ),
//       ]),
//     );
//   }

//   Widget _topBar() {
//     final qualityOpts = _qualityOptions();
//     final shown = _info?.quality;
//     final sub = [
//       if (widget.season > 1 || widget.episode > 1 || _isSeries)
//         'S${widget.season} \u00B7 E${widget.episode}',
//       if (shown != null && shown.isNotEmpty) shown,
//     ].join('  \u2022  ');

//     return Row(children: [
//       IconButton(
//         color: Colors.white,
//         icon: const Icon(Icons.arrow_back),
//         onPressed: () => Navigator.of(context).maybePop(),
//       ),
//       Expanded(
//         child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//           Text(widget.title,
//               maxLines: 1,
//               overflow: TextOverflow.ellipsis,
//               style: const TextStyle(
//                   color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
//           if (sub.isNotEmpty)
//             Text(sub,
//                 maxLines: 1,
//                 overflow: TextOverflow.ellipsis,
//                 style: const TextStyle(color: Colors.white70, fontSize: 12)),
//         ]),
//       ),
//       if (qualityOpts.isNotEmpty)
//         PopupMenuButton<_QOpt>(
//           icon: const Icon(Icons.high_quality_outlined, color: Colors.white),
//           tooltip: 'Quality',
//           onOpened: () => _hideTimer?.cancel(),
//           onCanceled: _showControls,
//           onSelected: _pick,
//           itemBuilder: (_) => [
//             for (final o in qualityOpts)
//               PopupMenuItem(
//                 value: o,
//                 child: Row(children: [
//                   Text(o.label),
//                   const Spacer(),
//                   if (_isSelected(o)) const Icon(Icons.check, size: 18),
//                 ]),
//               ),
//           ],
//         ),
//       IconButton(
//         icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
//         tooltip: 'Subtitles',
//         onPressed: _openSubtitles,
//       ),
//     ]);
//   }

//   Widget _centerButtons() {
//     return Row(mainAxisSize: MainAxisSize.min, children: [
//       IconButton(
//         iconSize: 40,
//         color: Colors.white,
//         tooltip: 'Back 10 seconds',
//         icon: const Icon(Icons.replay_10_rounded),
//         onPressed: () {
//           _seekBy(-10);
//           _showControls();
//         },
//       ),
//       const SizedBox(width: 24),
//       StreamBuilder<bool>(
//         stream: _player.stream.buffering,
//         initialData: _player.state.buffering,
//         builder: (_, b) => StreamBuilder<bool>(
//           stream: _player.stream.playing,
//           initialData: _player.state.playing,
//           builder: (_, p) {
//             if (b.data == true) return const SizedBox(width: 72, height: 72);
//             return IconButton(
//               iconSize: 64,
//               color: Colors.white,
//               icon: Icon(p.data == true
//                   ? Icons.pause_circle_filled_rounded
//                   : Icons.play_circle_filled_rounded),
//               onPressed: _playPause,
//             );
//           },
//         ),
//       ),
//       const SizedBox(width: 24),
//       IconButton(
//         iconSize: 40,
//         color: Colors.white,
//         tooltip: 'Forward 10 seconds',
//         icon: const Icon(Icons.forward_10_rounded),
//         onPressed: () {
//           _seekBy(10);
//           _showControls();
//         },
//       ),
//     ]);
//   }

//   Widget _bottomBar(bool landscape) {
//     return Column(mainAxisSize: MainAxisSize.min, children: [
//       Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 12),
//         child: _seekBar(),
//       ),
//       Row(children: [
//         const SizedBox(width: 4),
//         PopupMenuButton<double>(
//           tooltip: 'Speed',
//           onOpened: () => _hideTimer?.cancel(),
//           onCanceled: _showControls,
//           onSelected: (v) {
//             setState(() => _speed = v);
//             _player.setRate(v);
//             _showControls();
//           },
//           itemBuilder: (_) => [
//             for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
//               PopupMenuItem(
//                 value: v,
//                 child: Row(children: [
//                   Text(v == 1.0 ? 'Normal' : '${v}x'),
//                   const Spacer(),
//                   if (_speed == v) const Icon(Icons.check, size: 18),
//                 ]),
//               ),
//           ],
//           child: Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//             child: Row(mainAxisSize: MainAxisSize.min, children: [
//               const Icon(Icons.speed_rounded, color: Colors.white, size: 20),
//               const SizedBox(width: 4),
//               Text(_speed == 1.0 ? '1x' : '${_speed}x',
//                   style: const TextStyle(color: Colors.white, fontSize: 13)),
//             ]),
//           ),
//         ),
//         IconButton(
//           color: Colors.white,
//           tooltip: 'Fit / fill screen',
//           icon: Icon(_fit == BoxFit.contain
//               ? Icons.zoom_out_map_rounded
//               : Icons.zoom_in_map_rounded),
//           onPressed: () {
//             setState(() => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);
//             _showControls();
//           },
//         ),
//         if (_next != null)
//           TextButton.icon(
//             style: TextButton.styleFrom(foregroundColor: Colors.white),
//             icon: const Icon(Icons.skip_next_rounded),
//             label: const Text('Next'),
//             onPressed: _goNext,
//           ),
//         const Spacer(),
//         if (_mobile)
//           IconButton(
//             color: Colors.white,
//             tooltip: landscape ? 'Exit full screen' : 'Full screen',
//             icon: Icon(landscape
//                 ? Icons.fullscreen_exit_rounded
//                 : Icons.fullscreen_rounded),
//             onPressed: _toggleFullscreen,
//           ),
//         const SizedBox(width: 4),
//       ]),
//     ]);
//   }

//   Widget _seekBar() {
//     return StreamBuilder<Duration>(
//       stream: _player.stream.duration,
//       initialData: _player.state.duration,
//       builder: (_, ds) {
//         final dur = ds.data ?? Duration.zero;
//         final maxMs = dur.inMilliseconds.toDouble();
//         return StreamBuilder<Duration>(
//           stream: _player.stream.buffer,
//           initialData: _player.state.buffer,
//           builder: (_, bs) => StreamBuilder<Duration>(
//             stream: _player.stream.position,
//             initialData: _player.state.position,
//             builder: (_, ps) => ValueListenableBuilder<Duration?>(
//               valueListenable: _scrub,
//               builder: (_, scrub, __) {
//                 final pos = scrub ?? ps.data ?? Duration.zero;
//                 final hasDur = maxMs > 0;
//                 final value = hasDur
//                     ? pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble()
//                     : 0.0;
//                 final buf = hasDur
//                     ? (bs.data ?? Duration.zero)
//                         .inMilliseconds
//                         .clamp(0, dur.inMilliseconds)
//                         .toDouble()
//                     : 0.0;
//                 return Row(children: [
//                   Text(_fmt(pos),
//                       style: const TextStyle(color: Colors.white, fontSize: 12)),
//                   Expanded(
//                     child: SliderTheme(
//                       data: SliderTheme.of(context).copyWith(
//                         trackHeight: 3,
//                         thumbShape:
//                             const RoundSliderThumbShape(enabledThumbRadius: 7),
//                         overlayShape:
//                             const RoundSliderOverlayShape(overlayRadius: 16),
//                         inactiveTrackColor: Colors.white24,
//                         secondaryActiveTrackColor: Colors.white38,
//                       ),
//                       child: Slider(
//                         min: 0,
//                         max: hasDur ? maxMs : 1,
//                         value: value,
//                         secondaryTrackValue: hasDur ? buf : null,
//                         onChangeStart: (_) => _hideTimer?.cancel(),
//                         onChanged: hasDur
//                             ? (x) => _scrub.value = Duration(milliseconds: x.round())
//                             : null,
//                         onChangeEnd: (x) {
//                           _player.seek(Duration(milliseconds: x.round()));
//                           _scrub.value = null;
//                           _showControls();
//                         },
//                       ),
//                     ),
//                   ),
//                   Text(_fmt(dur),
//                       style: const TextStyle(color: Colors.white, fontSize: 12)),
//                 ]);
//               },
//             ),
//           ),
//         );
//       },
//     );
//   }

//   // ------------------------------------------------------------------ portrait info panel

//   /// Everything under the video in portrait. Scrollable, so it can never overflow.
//   Widget _infoPanel() {
//     final shown = _info?.quality;
//     final sub = [
//       if (_isSeries || widget.season > 1 || widget.episode > 1)
//         'Season ${widget.season} \u00B7 Episode ${widget.episode}',
//       if (shown != null && shown.isNotEmpty) shown,
//     ].join('  \u2022  ');
//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(16),
//       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//         Text(widget.title,
//             style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
//         if (sub.isNotEmpty) ...[
//           const SizedBox(height: 4),
//           Text(sub, style: const TextStyle(color: Colors.white70)),
//         ],
//         if (_next != null) ...[
//           const SizedBox(height: 16),
//           FilledButton.tonalIcon(
//             onPressed: _goNext,
//             icon: const Icon(Icons.skip_next_rounded),
//             label: Text('Next: S${_next!.season} \u00B7 E${_next!.episode}'),
//           ),
//         ],
//       ]),
//     );
//   }
// }
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/download_manager.dart';
import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../core/subtitle_service.dart';
import '../../core/watch_history.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'subtitle_sheet.dart';

/// One entry in the quality menu.
class _QOpt {
  const _QOpt(this.label, {this.serverQuality, this.track, this.trackMode = false});
  final String label;
  final String? serverQuality; // reload the stream from the backend with this quality
  final VideoTrack? track; // switch the video track inside the current stream
  final bool trackMode; // true for the "Auto" entry of the track list
}

class _Ep {
  const _Ep(this.season, this.episode, [this.path]);
  final int season, episode;
  final String? path; // set when the next episode is a downloaded file
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.id,
    required this.title,
    this.season = 1,
    this.episode = 1,
    this.resourceId,
    this.fresh = false,
    this.localPath,
  });
  final String id, title;
  final int season, episode;
  final String? resourceId;

  /// true = ignore the saved position and start from the beginning.
  final bool fresh;

  /// Downloaded file to play (offline). null = stream from the backend.
  final String? localPath;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  /// How many player screens are alive (a "next episode" replace briefly has 2).
  static int _live = 0;

  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final WatchHistory _history;

  PlayInfo? _info;
  String? _error;
  bool _loading = true;

  String? _quality; // quality requested from the backend (null = its default)
  String? _trackId; // chosen in-stream track (null = auto)
  List<VideoTrack> _tracks = const [];

  // --- subscriptions / timers
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  Timer? _saveTimer;
  Timer? _hideTimer;
  Timer? _flashTimer;
  Timer? _seekTargetTimer;

  // --- UI state
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
  final ValueNotifier<Duration?> _scrub = ValueNotifier(null);
  final ValueNotifier<int?> _flash = ValueNotifier(null); // +/- seconds
  double _speed = 1.0;
  late double _subScale;
  final List<SubtitleChoice> _downloaded = [];
  String? _activeSub;
  BoxFit _fit = BoxFit.contain;
  double _tapX = 0;
  Duration? _seekTarget;
  bool? _lastLandscape;

  // --- history / series info
  Duration? _resumeFrom;
  String? _cover;
  bool _isSeries = false;
  _Ep? _next;

  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ------------------------------------------------------------------ life cycle

  @override
  void initState() {
    super.initState();
    _live++;
    WidgetsBinding.instance.addObserver(this);
    _history = ref.read(watchHistoryProvider.notifier);
    _subScale = ref.read(subtitleServiceProvider).scale;

    final saved = _history.latestFor(widget.id);
    final dl = widget.localPath == null
        ? null
        : ref
            .read(downloadManagerProvider.notifier)
            .taskFor('${widget.id}|${widget.season}|${widget.episode}');
    _cover = saved?.cover ?? dl?.cover;
    _isSeries = saved?.series ?? dl?.isSeries ?? (widget.season > 1 || widget.episode > 1);
    if (!widget.fresh &&
        saved != null &&
        saved.matches(widget.id, widget.season, widget.episode) &&
        saved.positionMs > 15000) {
      _resumeFrom = Duration(milliseconds: saved.positionMs);
    }

    // Adaptive streams (DASH/HLS) expose several resolutions as video tracks.
    _tracksSub = _player.stream.tracks.listen((t) {
      final byHeight = <int, VideoTrack>{};
      for (final v in t.video) {
        final h = v.h ?? 0;
        if (v.id == 'auto' || v.id == 'no' || h <= 0) continue;
        byHeight.putIfAbsent(h, () => v);
      }
      final list = byHeight.values.toList()
        ..sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));
      if (mounted) setState(() => _tracks = list);
    });

    _playingSub = _player.stream.playing.listen((p) {
      if (p) {
        _scheduleHide();
      } else {
        _saveNow();
        _controlsVisible.value = true;
      }
    });
    _completedSub = _player.stream.completed.listen((c) {
      if (c) _onCompleted();
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.state.playing) _saveNow();
    });

    _prepareSeriesInfo();
    _load(resume: _resumeFrom);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _seekTargetTimer?.cancel();
    _tracksSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();

    // Save where we stopped. Deferred so we never change provider state while
    // the widget tree is being torn down.
    final pos = _player.state.position;
    final dur = _player.state.duration;
    scheduleMicrotask(() => _commitProgress(pos, dur));

    _player.dispose();
    _controlsVisible.dispose();
    _scrub.dispose();
    _flash.dispose();

    _live--;
    if (_live <= 0) {
      _live = 0;
      // Always give the phone back to the app in portrait / normal bars.
      if (_mobile) {
        SystemChrome.setPreferredOrientations(const []);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _saveNow();
  }

  // ------------------------------------------------------------------ history

  void _saveNow() {
    if (_loading || _info == null) return;
    _commitProgress(_player.state.position, _player.state.duration);
  }

  void _commitProgress(Duration pos, Duration dur) {
    if (_info == null || dur.inSeconds <= 0 || pos.inSeconds < 15) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Watched (almost) to the end: forget it, or point to the next episode.
    if (pos.inMilliseconds / dur.inMilliseconds > 0.95) {
      final nx = _next;
      if (nx != null) {
        _history.record(HistoryEntry(
          id: widget.id,
          title: widget.title,
          cover: _cover,
          resourceId: widget.resourceId,
          season: nx.season,
          episode: nx.episode,
          positionMs: 0,
          durationMs: 0,
          updatedAt: now,
          series: true,
        ));
      } else {
        _history.remove(widget.id);
      }
      return;
    }

    _history.record(HistoryEntry(
      id: widget.id,
      title: widget.title,
      cover: _cover,
      resourceId: widget.resourceId,
      season: widget.season,
      episode: widget.episode,
      positionMs: pos.inMilliseconds,
      durationMs: dur.inMilliseconds,
      updatedAt: now,
      series: _isSeries,
    ));
  }

  /// Works out the cover / "is this a series" / "what is the next episode".
  Future<void> _prepareSeriesInfo() async {
    if (widget.localPath != null) {
      // Offline: "Next" = the next episode you have downloaded.
      final done = ref
          .read(downloadManagerProvider)
          .where((t) => t.id == widget.id && t.isCompleted && t.filePath != null)
          .toList()
        ..sort((a, b) => a.season != b.season
            ? a.season.compareTo(b.season)
            : a.episode.compareTo(b.episode));
      final i = done.indexWhere(
          (t) => t.season == widget.season && t.episode == widget.episode);
      if (i >= 0 && i + 1 < done.length && mounted) {
        final n = done[i + 1];
        setState(() => _next = _Ep(n.season, n.episode, n.filePath));
      }
      return;
    }
    try {
      if (_cover == null) {
        final d = ref.read(detailProvider(widget.id)).asData?.value;
        if (d != null) {
          _cover = d.movie.cover;
          _isSeries = _isSeries || !d.movie.isMovie;
        }
      }
      if (!_isSeries) return;
      final seasons = await ref.read(episodesProvider(widget.id).future);
      if (!mounted) return;
      final cur = seasons.indexWhere((s) => s.number == widget.season);
      if (cur < 0) return;
      final eps = seasons[cur].episodes;
      final i = eps.indexWhere((e) => e.number == widget.episode);
      _Ep? nx;
      if (i >= 0 && i + 1 < eps.length) {
        nx = _Ep(seasons[cur].number, eps[i + 1].number);
      } else if (cur + 1 < seasons.length && seasons[cur + 1].episodes.isNotEmpty) {
        nx = _Ep(seasons[cur + 1].number, seasons[cur + 1].episodes.first.number);
      }
      if (mounted) setState(() => _next = nx);
    } catch (_) {
      // Next-episode is a bonus feature; never break playback because of it.
    }
  }

  void _goNext() {
    final nx = _next;
    if (nx == null || !mounted) return;
    context.pushReplacement(playLocation(widget.id,
        title: widget.title,
        season: nx.season,
        episode: nx.episode,
        resourceId: widget.resourceId,
        localPath: nx.path));
  }

  void _onCompleted() {
    if (!mounted || _loading || _info == null) return;
    if (_player.state.duration.inSeconds <= 0) return;
    if (_next != null) {
      _commitProgress(_player.state.duration, _player.state.duration);
      _goNext();
    } else {
      _history.remove(widget.id);
      _controlsVisible.value = true;
    }
  }

  // ------------------------------------------------------------------ loading

  /// Sets raw libmpv options. Safe no-op on platforms without them.
  Future<void> _mpv(String key, String value) async {
    if (kIsWeb) return;
    try {
      await (_player.platform as dynamic).setProperty(key, value);
    } catch (_) {}
  }

  Future<void> _load({Duration? resume}) async {
    setState(() {
      _loading = true;
      _error = null;
      _trackId = null;
      _tracks = const [];
    });
    try {
      final PlayInfo info;
      if (widget.localPath != null) {
        if (!await File(widget.localPath!).exists()) {
          throw 'This downloaded file is missing. Delete it and download again.';
        }
        info = PlayInfo(widget.localPath!, const {}, '', const [], null, 'Offline', const []);
      } else {
        info = await ref.read(apiClientProvider).play(
              widget.id,
              season: widget.season,
              episode: widget.episode,
              resourceId: widget.resourceId,
              quality: _quality,
            );
      }

      // Same CDN requirements the backend's mpv launcher uses.
      await _mpv('ytdl', 'no');
      final ua = info.headers['User-Agent'];
      final referer = info.headers['Referer'];
      if (ua != null) await _mpv('user-agent', ua);
      if (referer != null) await _mpv('referrer', referer);
      final cookie = info.headers['Cookie'];
      // DASH sub-requests do not inherit http-header-fields; pass to the demuxer too.
      if (cookie != null && info.url.contains('.mpd')) {
        await _mpv('demuxer-lavf-o', 'headers=Cookie: $cookie');
      }

      await _player.open(
        Media(
          info.url,
          httpHeaders: info.headers,
          start: (resume != null && resume > Duration.zero) ? resume : null,
        ),
        play: true,
      );
      if (_speed != 1.0) await _player.setRate(_speed);

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
      _showControls();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<_QOpt> _qualityOptions() {
    if (_tracks.length > 1) {
      return [
        const _QOpt('Auto', trackMode: true),
        for (final t in _tracks) _QOpt('${t.h}p', track: t, trackMode: true),
      ];
    }
    final q = _info?.qualities ?? const <String>[];
    if (q.length > 1) {
      return [const _QOpt('Default'), for (final x in q) _QOpt(x, serverQuality: x)];
    }
    return const [];
  }

  bool _isSelected(_QOpt o) {
    if (o.trackMode) return _trackId == o.track?.id;
    final current = _quality ?? _info?.quality;
    if (o.serverQuality == null) return _quality == null;
    return current?.toLowerCase() == o.serverQuality!.toLowerCase();
  }

  void _pick(_QOpt o) {
    if (o.trackMode) {
      setState(() => _trackId = o.track?.id);
      _player.setVideoTrack(o.track ?? VideoTrack.auto());
    } else {
      _quality = o.serverQuality;
      _load(resume: _player.state.position); // keep the current position
    }
    _showControls();
  }

  // ------------------------------------------------------------------ orientation / fullscreen

  /// Keeps the system bars in sync with the real orientation, so the UI can
  /// never end up "landscape without controls" like before.
  void _syncChrome(bool landscape) {
    if (!_mobile || _lastLandscape == landscape) return;
    _lastLandscape = landscape;
    if (landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    }
  }

  bool get _isLandscape =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  Future<void> _toggleFullscreen() async {
    if (!_mobile) return;
    if (_isLandscape) {
      await _exitFullscreen();
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (mounted) _showControls();
  }

  Future<void> _exitFullscreen() async {
    // Force portrait first, then hand control back to the sensor/OS.
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) await SystemChrome.setPreferredOrientations(const []);
  }

  // ------------------------------------------------------------------ subtitles

  Future<void> _openSubtitles() async {
    _hideTimer?.cancel();
    final choice = await showSubtitleSheet(
      context,
      title: widget.title,
      series: _isSeries,
      season: widget.season,
      episode: widget.episode,
      builtIn: _info?.subtitles ?? const <SubtitleItem>[],
      downloaded: List.of(_downloaded),
      activeLabel: _activeSub,
      scale: _subScale,
      onScale: (v) {
        if (mounted) setState(() => _subScale = v);
      },
    );
    if (!mounted) return;
    if (choice != null) await _applySubtitle(choice);
    if (mounted) _showControls();
  }

  Future<void> _applySubtitle(SubtitleChoice c) async {
    try {
      if (c.isOff) {
        await _player.setSubtitleTrack(SubtitleTrack.no());
      } else if (c.data != null) {
        await _player.setSubtitleTrack(SubtitleTrack.data(c.data!,
            title: c.label, language: c.language));
        if (!_downloaded.any((d) => d.label == c.label)) _downloaded.add(c);
      } else {
        await _player.setSubtitleTrack(SubtitleTrack.uri(c.url!, title: c.label));
      }
      if (mounted) setState(() => _activeSub = c.isOff ? null : c.label);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load this subtitle.')));
      }
    }
  }

  // ------------------------------------------------------------------ controls logic

  void _showControls() {
    _hideTimer?.cancel();
    _controlsVisible.value = true;
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (_player.state.playing && _scrub.value == null) {
        _controlsVisible.value = false;
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible.value) {
      _hideTimer?.cancel();
      _controlsVisible.value = false;
    } else {
      _showControls();
    }
  }

  void _seekBy(int seconds) {
    final dur = _player.state.duration;
    var t = (_seekTarget ?? _player.state.position) + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (dur > Duration.zero && t > dur) t = dur;
    _seekTarget = t;
    _seekTargetTimer?.cancel();
    _seekTargetTimer = Timer(const Duration(milliseconds: 900), () => _seekTarget = null);
    _player.seek(t);

    // Little "+10 s" bubble, accumulating while you keep tapping.
    final current = _flash.value;
    final same = current != null && (current < 0) == (seconds < 0);
    _flash.value = (same ? current! : 0) + seconds;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 800), () => _flash.value = null);
  }

  void _playPause() {
    _player.playOrPause();
    _showControls();
  }

  String _fmt(Duration d) => formatMs(d.inMilliseconds);

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final landscape = _mobile && _isLandscape;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncChrome(landscape);
    });

    final stage = _stage(landscape);

    return PopScope(
      // In landscape the back button first returns to portrait, then leaves.
      canPop: !landscape,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: landscape
            ? SizedBox.expand(child: stage)
            : SafeArea(
                child: Column(children: [
                  AspectRatio(aspectRatio: 16 / 9, child: stage),
                  Expanded(child: _infoPanel()),
                ]),
              ),
      ),
    );
  }

  /// Video + gestures + controls. Same widget in portrait and landscape.
  Widget _stage(bool landscape) {
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      if (_loading)
        const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Finding the best stream\u2026',
                style: TextStyle(color: Colors.white70)),
          ]),
        )
      else if (_error != null)
        ErrorView(_error!, onRetry: () => _load(resume: _resumeFrom))
      else ...[
        Video(
          key: _videoKey,
          controller: _video,
          controls: NoVideoControls,
          fit: _fit,
          fill: Colors.black,
          subtitleViewConfiguration: SubtitleViewConfiguration(
            style: TextStyle(
              height: 1.35,
              fontSize: (landscape ? 32.0 : 20.0) * _subScale,
              color: Colors.white,
              backgroundColor: const Color(0x99000000),
            ),
            textAlign: TextAlign.center,
            padding: EdgeInsets.fromLTRB(16, 0, 16, landscape ? 64 : 32),
          ),
        ),
        _gestureLayer(),
        _bufferingSpinner(),
        _flashBubble(),
        _controlsOverlay(landscape),
      ],
      if (_loading || _error != null) _simpleBackBar(landscape),
    ]);
  }

  Widget _simpleBackBar(bool landscape) => Align(
        alignment: Alignment.topLeft,
        child: SafeArea(
          bottom: false,
          child: IconButton(
            color: Colors.white,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      );

  Widget _gestureLayer() => LayoutBuilder(builder: (_, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTapDown: (d) => _tapX = d.localPosition.dx,
          onDoubleTap: () => _seekBy(_tapX < c.maxWidth / 2 ? -10 : 10),
        );
      });

  Widget _bufferingSpinner() => IgnorePointer(
        child: StreamBuilder<bool>(
          stream: _player.stream.buffering,
          initialData: _player.state.buffering,
          builder: (_, s) => s.data == true
              ? const Center(child: CircularProgressIndicator())
              : const SizedBox.shrink(),
        ),
      );

  Widget _flashBubble() => IgnorePointer(
        child: ValueListenableBuilder<int?>(
          valueListenable: _flash,
          builder: (_, v, __) {
            if (v == null) return const SizedBox.shrink();
            final left = v < 0;
            return Align(
              alignment: Alignment(left ? -0.6 : 0.6, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(left ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
                      color: Colors.white),
                  const SizedBox(width: 6),
                  Text('${v.abs()} s',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
            );
          },
        ),
      );

  // ------------------------------------------------------------------ controls overlay

  Widget _controlsOverlay(bool landscape) {
    return ValueListenableBuilder<bool>(
      valueListenable: _controlsVisible,
      builder: (_, visible, child) => IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        // Dark gradients for readability. Ignores touches so taps reach the video.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
                stops: [0, 0.3, 0.65, 1],
              ),
            ),
          ),
        ),
        // In landscape we are full screen, so respect notches / gesture bars.
        SafeArea(
          top: landscape,
          bottom: landscape,
          left: landscape,
          right: landscape,
          child: Column(children: [
            _topBar(),
            Expanded(child: Center(child: _centerButtons())),
            _bottomBar(landscape),
          ]),
        ),
      ]),
    );
  }

  Widget _topBar() {
    final qualityOpts = _qualityOptions();
    final shown = _info?.quality;
    final sub = [
      if (widget.season > 1 || widget.episode > 1 || _isSeries)
        'S${widget.season} \u00B7 E${widget.episode}',
      if (shown != null && shown.isNotEmpty) shown,
    ].join('  \u2022  ');

    return Row(children: [
      IconButton(
        color: Colors.white,
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          if (sub.isNotEmpty)
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
      if (qualityOpts.isNotEmpty)
        PopupMenuButton<_QOpt>(
          icon: const Icon(Icons.high_quality_outlined, color: Colors.white),
          tooltip: 'Quality',
          onOpened: () => _hideTimer?.cancel(),
          onCanceled: _showControls,
          onSelected: _pick,
          itemBuilder: (_) => [
            for (final o in qualityOpts)
              PopupMenuItem(
                value: o,
                child: Row(children: [
                  Text(o.label),
                  const Spacer(),
                  if (_isSelected(o)) const Icon(Icons.check, size: 18),
                ]),
              ),
          ],
        ),
      IconButton(
        icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
        tooltip: 'Subtitles',
        onPressed: _openSubtitles,
      ),
    ]);
  }

  Widget _centerButtons() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        iconSize: 40,
        color: Colors.white,
        tooltip: 'Back 10 seconds',
        icon: const Icon(Icons.replay_10_rounded),
        onPressed: () {
          _seekBy(-10);
          _showControls();
        },
      ),
      const SizedBox(width: 24),
      StreamBuilder<bool>(
        stream: _player.stream.buffering,
        initialData: _player.state.buffering,
        builder: (_, b) => StreamBuilder<bool>(
          stream: _player.stream.playing,
          initialData: _player.state.playing,
          builder: (_, p) {
            if (b.data == true) return const SizedBox(width: 72, height: 72);
            return IconButton(
              iconSize: 64,
              color: Colors.white,
              icon: Icon(p.data == true
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded),
              onPressed: _playPause,
            );
          },
        ),
      ),
      const SizedBox(width: 24),
      IconButton(
        iconSize: 40,
        color: Colors.white,
        tooltip: 'Forward 10 seconds',
        icon: const Icon(Icons.forward_10_rounded),
        onPressed: () {
          _seekBy(10);
          _showControls();
        },
      ),
    ]);
  }

  Widget _bottomBar(bool landscape) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _seekBar(),
      ),
      Row(children: [
        const SizedBox(width: 4),
        PopupMenuButton<double>(
          tooltip: 'Speed',
          onOpened: () => _hideTimer?.cancel(),
          onCanceled: _showControls,
          onSelected: (v) {
            setState(() => _speed = v);
            _player.setRate(v);
            _showControls();
          },
          itemBuilder: (_) => [
            for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              PopupMenuItem(
                value: v,
                child: Row(children: [
                  Text(v == 1.0 ? 'Normal' : '${v}x'),
                  const Spacer(),
                  if (_speed == v) const Icon(Icons.check, size: 18),
                ]),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.speed_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 4),
              Text(_speed == 1.0 ? '1x' : '${_speed}x',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
          ),
        ),
        IconButton(
          color: Colors.white,
          tooltip: 'Fit / fill screen',
          icon: Icon(_fit == BoxFit.contain
              ? Icons.zoom_out_map_rounded
              : Icons.zoom_in_map_rounded),
          onPressed: () {
            setState(() => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);
            _showControls();
          },
        ),
        if (_next != null)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Next'),
            onPressed: _goNext,
          ),
        const Spacer(),
        if (_mobile)
          IconButton(
            color: Colors.white,
            tooltip: landscape ? 'Exit full screen' : 'Full screen',
            icon: Icon(landscape
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded),
            onPressed: _toggleFullscreen,
          ),
        const SizedBox(width: 4),
      ]),
    ]);
  }

  Widget _seekBar() {
    return StreamBuilder<Duration>(
      stream: _player.stream.duration,
      initialData: _player.state.duration,
      builder: (_, ds) {
        final dur = ds.data ?? Duration.zero;
        final maxMs = dur.inMilliseconds.toDouble();
        return StreamBuilder<Duration>(
          stream: _player.stream.buffer,
          initialData: _player.state.buffer,
          builder: (_, bs) => StreamBuilder<Duration>(
            stream: _player.stream.position,
            initialData: _player.state.position,
            builder: (_, ps) => ValueListenableBuilder<Duration?>(
              valueListenable: _scrub,
              builder: (_, scrub, __) {
                final pos = scrub ?? ps.data ?? Duration.zero;
                final hasDur = maxMs > 0;
                final value = hasDur
                    ? pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble()
                    : 0.0;
                final buf = hasDur
                    ? (bs.data ?? Duration.zero)
                        .inMilliseconds
                        .clamp(0, dur.inMilliseconds)
                        .toDouble()
                    : 0.0;
                return Row(children: [
                  Text(_fmt(pos),
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 16),
                        inactiveTrackColor: Colors.white24,
                        secondaryActiveTrackColor: Colors.white38,
                      ),
                      child: Slider(
                        min: 0,
                        max: hasDur ? maxMs : 1,
                        value: value,
                        secondaryTrackValue: hasDur ? buf : null,
                        onChangeStart: (_) => _hideTimer?.cancel(),
                        onChanged: hasDur
                            ? (x) => _scrub.value = Duration(milliseconds: x.round())
                            : null,
                        onChangeEnd: (x) {
                          _player.seek(Duration(milliseconds: x.round()));
                          _scrub.value = null;
                          _showControls();
                        },
                      ),
                    ),
                  ),
                  Text(_fmt(dur),
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ]);
              },
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ portrait info panel

  /// Everything under the video in portrait. Scrollable, so it can never overflow.
  Widget _infoPanel() {
    final shown = _info?.quality;
    final sub = [
      if (_isSeries || widget.season > 1 || widget.episode > 1)
        'Season ${widget.season} \u00B7 Episode ${widget.episode}',
      if (shown != null && shown.isNotEmpty) shown,
    ].join('  \u2022  ');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: Colors.white70)),
        ],
        if (_next != null) ...[
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _goNext,
            icon: const Icon(Icons.skip_next_rounded),
            label: Text('Next: S${_next!.season} \u00B7 E${_next!.episode}'),
          ),
        ],
      ]),
    );
  }
}