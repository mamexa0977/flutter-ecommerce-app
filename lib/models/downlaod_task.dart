enum DownloadStatus { queued, preparing, downloading, paused, completed, failed }

/// One downloaded (or downloading) movie or episode.
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.title,
    required this.quality,
    required this.basePath,
    required this.createdAt,
    this.cover,
    this.isSeries = false,
    this.season = 1,
    this.episode = 1,
    this.episodeTitle = '',
    this.resourceId,
    this.filePath,
    this.status = DownloadStatus.queued,
    this.received = 0,
    this.total = -1,
    this.speedKbps = 0,
    this.error,
  });

  final String id; // movie / series id
  final String title;
  final String? cover;
  final bool isSeries;
  final int season, episode;
  final String episodeTitle;
  final String quality;
  final String? resourceId; // chosen audio track
  final String basePath; // file path WITHOUT extension (.mp4/.ts is added)
  final String? filePath; // final playable file once completed
  final DownloadStatus status;
  final int received; // bytes on disk
  final int total; // -1 = unknown
  final double speedKbps; // runtime only, not saved
  final String? error;
  final int createdAt;

  String get key => '$id|$season|$episode';

  bool get isCompleted => status == DownloadStatus.completed;
  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.preparing ||
      status == DownloadStatus.downloading;

  double? get progress => (total > 0) ? (received / total).clamp(0.0, 1.0) : null;

  String get label => isSeries
      ? 'S$season \u00B7 E$episode${episodeTitle.isNotEmpty ? '  $episodeTitle' : ''}'
      : title;

  static String formatBytes(int b) {
    if (b <= 0) return '0 MB';
    final mb = b / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  String get speedText => speedKbps >= 1024
      ? '${(speedKbps / 1024).toStringAsFixed(1)} MB/s'
      : '${speedKbps.toStringAsFixed(0)} KB/s';

  DownloadTask copyWith({
    DownloadStatus? status,
    int? received,
    int? total,
    double? speedKbps,
    String? error,
    bool clearError = false,
    String? filePath,
    String? basePath,
  }) =>
      DownloadTask(
        id: id,
        title: title,
        cover: cover,
        isSeries: isSeries,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
        quality: quality,
        resourceId: resourceId,
        basePath: basePath ?? this.basePath,
        filePath: filePath ?? this.filePath,
        createdAt: createdAt,
        status: status ?? this.status,
        received: received ?? this.received,
        total: total ?? this.total,
        speedKbps: speedKbps ?? this.speedKbps,
        error: clearError ? null : (error ?? this.error),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cover': cover,
        'isSeries': isSeries,
        'season': season,
        'episode': episode,
        'episodeTitle': episodeTitle,
        'quality': quality,
        'resourceId': resourceId,
        'basePath': basePath,
        'filePath': filePath,
        'status': status.name,
        'received': received,
        'total': total,
        'error': error,
        'createdAt': createdAt,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> j) => DownloadTask(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        cover: j['cover'] as String?,
        isSeries: j['isSeries'] == true,
        season: (j['season'] as num?)?.toInt() ?? 1,
        episode: (j['episode'] as num?)?.toInt() ?? 1,
        episodeTitle: '${j['episodeTitle'] ?? ''}',
        quality: '${j['quality'] ?? ''}',
        resourceId: j['resourceId'] as String?,
        basePath: '${j['basePath'] ?? ''}',
        filePath: j['filePath'] as String?,
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => DownloadStatus.paused,
        ),
        received: (j['received'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? -1,
        error: j['error'] as String?,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}