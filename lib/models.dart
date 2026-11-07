enum DlStatus { queued, downloading, paused, completed, failed }

class DownloadItem {
  final String id;
  final String url;
  String fileName;
  String dirPath;
  int total; // -1 = unknown
  int downloaded;
  bool rangeSupported;
  bool hls; // HLS stream downloaded piece by piece
  int segDone; // HLS pieces already saved
  Map<String, String> headers; // cookies / UA / referer from the browser
  DlStatus status;
  String? error;

  /// The server's ETag / Last-Modified when the file was first checked: used
  /// to notice that the file changed before a paused download is resumed.
  String? validator;

  // runtime only (not persisted)
  double speed = 0; // bytes/sec

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.dirPath,
    this.total = -1,
    this.downloaded = 0,
    this.rangeSupported = false,
    this.hls = false,
    this.segDone = 0,
    this.headers = const {},
    this.status = DlStatus.queued,
    this.error,
    this.validator,
  });

  String get savePath => '$dirPath/$fileName';

  double get progress =>
      total > 0 ? (downloaded / total).clamp(0.0, 1.0).toDouble() : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'dirPath': dirPath,
        'total': total,
        'downloaded': downloaded,
        'rangeSupported': rangeSupported,
        'hls': hls,
        'segDone': segDone,
        'headers': headers,
        'status': status.name,
        'error': error,
        'validator': validator,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) {
    var st = DlStatus.values.firstWhere(
      (e) => e.name == j['status'],
      orElse: () => DlStatus.paused,
    );
    // anything that was running when the app closed is now paused
    if (st == DlStatus.downloading || st == DlStatus.queued) {
      st = DlStatus.paused;
    }
    return DownloadItem(
      id: j['id'] as String,
      url: j['url'] as String,
      fileName: j['fileName'] as String,
      dirPath: j['dirPath'] as String,
      total: (j['total'] as num?)?.toInt() ?? -1,
      downloaded: (j['downloaded'] as num?)?.toInt() ?? 0,
      rangeSupported: j['rangeSupported'] as bool? ?? false,
      hls: j['hls'] as bool? ?? false,
      segDone: (j['segDone'] as num?)?.toInt() ?? 0,
      headers: ((j['headers'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      status: st,
      error: j['error'] as String?,
      validator: j['validator'] as String?,
    );
  }
}

String formatBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  double v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${u[i]}';
}

String formatEta(DownloadItem d) {
  if (d.total <= 0 || d.speed <= 0) return '--';
  final s = ((d.total - d.downloaded) / d.speed).round();
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
  return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
}
