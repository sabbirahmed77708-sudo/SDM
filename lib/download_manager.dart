import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hls.dart';
import 'models.dart';

/// Pieces of a download started by an older version (no marker file).
const int kSegments = 4;

/// Big files are split into more pieces (more connections = more speed).
const int kBigFileBytes = 16 << 20;
const int kBigFileSegments = 8;
const String _ua =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0 Mobile Safari/537.36';

/// Result of inspecting a URL before downloading it.
/// Hosts SDM does not download from (YouTube's terms forbid it).
const unsupportedMessage =
    'YouTube links are not supported. Use YouTube Premium for offline videos.';

bool isUnsupportedHost(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  const blocked = [
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
    'googlevideo.com',
  ];
  return blocked.any((b) => host == b || host.endsWith('.$b'));
}

class ProbeResult {
  final int total;
  final bool range;
  final String? fileName;
  final String? contentType;
  final bool hls;
  final String? validator; // ETag or Last-Modified of the file
  const ProbeResult(this.total, this.range, this.fileName, this.contentType,
      {this.hls = false, this.validator});
}

bool _looksHls(String url, String? ct) {
  final c = (ct ?? '').toLowerCase();
  if (c.contains('mpegurl')) return true;
  final p = (Uri.tryParse(url)?.path ?? '').toLowerCase();
  return p.endsWith('.m3u8');
}

bool _isHtmlType(String? ct) {
  final c = (ct ?? '').toLowerCase();
  return c.startsWith('text/html') || c.startsWith('application/xhtml');
}

bool _nameIsWebPage(String name) {
  final n = name.toLowerCase();
  return n.endsWith('.html') || n.endsWith('.htm') || n.endsWith('.xhtml');
}

class _Run {
  final CancelToken token = CancelToken();
  Timer? ticker;
  List<int> segBytes = [];
  int startBytes = 0;
  int nextFree = 0; // speed limit pacing (microseconds)
  double speed = 0; // current speed (bytes/s), for the fair-share check
  final int startedAt = DateTime.now().microsecondsSinceEpoch;
  int lowSince = 0; // since when it is far below its fair share (microseconds)

  /// Set when the download itself failed and the other pieces were stopped
  /// (as opposed to the person pausing / removing it).
  bool failed = false;

  /// The error that made [failed] true: the stopped pieces only report a
  /// cancel, and this keeps the real cause for the retry / failure message.
  Object? failure;
  StackTrace? failureTrace;
}

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'User-Agent': _ua},
    followRedirects: true,
    maxRedirects: 8,
  ));

  final List<DownloadItem> items = [];
  final Map<String, _Run> _runs = {};
  SharedPreferences? _prefs;
  String? _dir;

  // Wi-Fi only: when ON, downloads run only on Wi-Fi / Ethernet.
  static const MethodChannel _net = MethodChannel('drom/net');
  bool wifiOnly = false;
  final Set<String> _waitingForWifi = {};
  Timer? _wifiTimer;

  bool isWaitingForWifi(DownloadItem d) => _waitingForWifi.contains(d.id);

  // ---- queue, speed limit, automatic retry
  /// How many downloads run at the same time; the rest wait in the queue.
  int maxActive = 3;

  /// Speed limit for all downloads together, bytes per second (0 = none).
  int speedLimit = 0;

  /// Extra limit while the browser screen is open (0 = off).
  int browserLimit = 0;
  bool browserOpen = false;

  /// Resume by itself when the internet is back / after a network error.
  bool autoRetry = true;

  /// Put every file into a folder for its type (Video, Music, ...) inside the
  /// download folder, unless the person picked a folder by hand.
  bool sortByType = true;

  final Set<String> _waitingForNet = {};

  /// Resume was asked while the cancelled run was still shutting down.
  final Set<String> _startAfterStop = {};
  final Map<String, int> _retryAt = {};
  final Map<String, int> _failStreak = {};
  int _offlineTicks = 0;

  bool isWaitingForNet(DownloadItem d) => _waitingForNet.contains(d.id);

  /// Why a not-running download is waiting (null = it is just paused).
  String? waitReason(DownloadItem d) {
    if (d.status == DlStatus.queued) return 'Queued';
    if (d.status != DlStatus.paused) return null;
    if (_waitingForWifi.contains(d.id)) return 'Waiting for Wi-Fi';
    if (_waitingForNet.contains(d.id)) return 'Waiting for internet';
    return null;
  }

  Future<void> _saveSettings() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt('max_active', maxActive);
    await p.setInt('speed_limit', speedLimit);
    await p.setInt('browser_limit', browserLimit);
    await p.setBool('auto_retry', autoRetry);
    await p.setBool('sort_by_type', sortByType);
  }

  Future<void> setSortByType(bool v) async {
    sortByType = v;
    await _saveSettings();
    notifyListeners();
  }

  /// Folder name for a file, by its extension.
  static String typeFolder(String fileName) {
    final e = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    if (const ['mp4', 'mkv', 'webm', 'avi', 'mov', '3gp', 'ts', 'flv', 'wmv', 'm4v'].contains(e)) return 'Video';
    if (const ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma'].contains(e)) return 'Music';
    if (const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'].contains(e)) return 'Images';
    if (e == 'apk' || e == 'xapk' || e == 'apks') return 'Apps';
    if (const ['zip', 'rar', '7z', 'tar', 'gz', 'iso', 'bz2', 'xz'].contains(e)) return 'Archives';
    if (const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'epub', 'csv'].contains(e)) return 'Documents';
    return 'Other';
  }

  /// [base]/Video, [base]/Music ... when sorting is on, otherwise [base].
  String sortedDir(String base, String fileName) =>
      sortByType ? '$base/${typeFolder(fileName)}' : base;

  Future<void> setMaxActive(int v) async {
    maxActive = v.clamp(1, 10);
    notifyListeners();
    await _saveSettings();
    _pump();
  }

  Future<void> setSpeedLimit(int bytesPerSec) async {
    speedLimit = bytesPerSec < 0 ? 0 : bytesPerSec;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setBrowserLimit(int bytesPerSec) async {
    browserLimit = bytesPerSec < 0 ? 0 : bytesPerSec;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAutoRetry(bool v) async {
    autoRetry = v;
    if (!v) {
      // stop waiting for the internet: they simply stay paused
      _waitingForNet.clear();
    }
    notifyListeners();
    await _saveSettings();
  }

  void setBrowserOpen(bool v) {
    if (browserOpen == v) return;
    browserOpen = v;
    notifyListeners();
  }

  /// The limit that applies right now (bytes/s, 0 = none).
  int get effectiveLimit {
    var lim = speedLimit;
    if (browserOpen && browserLimit > 0) {
      lim = lim > 0 ? (lim < browserLimit ? lim : browserLimit) : browserLimit;
    }
    return lim;
  }

  /// Slows a download down so that every running download gets the same
  /// share of the limit. Awaiting here makes the network wait too.
  Future<void> _pace(_Run run, int bytes) async {
    final lim = effectiveLimit;
    double share;
    if (lim > 0) {
      share = lim / (_runs.isEmpty ? 1 : _runs.length);
    } else {
      // no limit set: still keep the running downloads even, so one cannot
      // grab the whole connection and starve the other
      share = _fairShare(run);
      if (share <= 0) return;
    }
    final now = DateTime.now().microsecondsSinceEpoch;
    if (run.nextFree < now) run.nextFree = now;
    run.nextFree += (bytes / share * 1000000).round();
    final wait = run.nextFree - now;
    if (wait > 4000) await Future.delayed(Duration(microseconds: wait));
  }

  double _aggPeak = 0; // best total speed seen with the current set of downloads
  int _peakRuns = 0;

  /// Bytes/s one running download may use so that all of them keep about the
  /// same speed (0 = no cap).
  ///
  /// Every download is held to a little above the CURRENT average of all
  /// running downloads, so a fast one can never starve a slower one: what the
  /// fast one gives up goes to the others and the speeds meet in the middle.
  /// A download that was started a few seconds ago counts even while its speed
  /// is still near zero (that is exactly the starved one). Only a download
  /// that stays far below the average for 15 s (a really slow server) is left
  /// alone, and what it cannot use goes to the others.
  double _fairShare(_Run run) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final active = _runs.values
        .where((r) => r.speed > 0 || now - r.startedAt > 6000000)
        .toList();
    final n = active.length;
    if (n < 2) {
      _aggPeak = 0;
      _peakRuns = n;
      return 0;
    }
    if (_peakRuns != n) {
      _peakRuns = n;
      _aggPeak = 0;
    }
    var sum = 0.0;
    for (final r in active) {
      sum += r.speed;
    }
    if (sum > _aggPeak) _aggPeak = sum;
    final mean = sum / n;
    if (mean < 100 * 1024) return 0; // not measured yet / tiny
    const slowFor = 15000000; // 15 s in microseconds
    var limitedSum = 0.0;
    var limited = 0;
    for (final r in active) {
      if (r.speed < mean * 0.25) {
        if (r.lowSince == 0) r.lowSince = now;
      } else {
        r.lowSince = 0;
      }
      if (r.lowSince != 0 && now - r.lowSince > slowFor) {
        limitedSum += r.speed;
        limited++;
      }
    }
    if (run.lowSince != 0 && now - run.lowSince > slowFor) return 0;
    var cap = mean * 1.1;
    if (limited > 0 && limited < n) {
      final rest = (_aggPeak - limitedSum) / (n - limited) * 1.1;
      if (rest > cap) cap = rest;
    }
    return cap;
  }

  /// Starts waiting downloads while there is room.
  void _pump() {
    if (wifiOnly) {
      // a waiting download must not slip onto mobile data
      _pumpOnWifi();
      return;
    }
    while (_runs.length < maxActive) {
      final next = items
          .where((e) => e.status == DlStatus.queued && !_runs.containsKey(e.id))
          .firstOrNull;
      if (next == null) return;
      _begin(next);
    }
  }

  bool _pumpingWifi = false;

  /// [_pump] for "Wi-Fi only": queued downloads start only while on Wi-Fi,
  /// otherwise they wait for it.
  Future<void> _pumpOnWifi() async {
    if (_pumpingWifi) return;
    _pumpingWifi = true;
    try {
      final wifi = await _onWifi();
      var changed = false;
      while (_runs.length < maxActive) {
        final next = items
            .where(
                (e) => e.status == DlStatus.queued && !_runs.containsKey(e.id))
            .firstOrNull;
        if (next == null) break;
        changed = true;
        if (wifi || !wifiOnly) {
          _begin(next);
        } else {
          next.status = DlStatus.paused;
          next.speed = 0;
          _waitingForWifi.add(next.id);
        }
      }
      if (changed) {
        notifyListeners();
        await _save();
      }
    } finally {
      _pumpingWifi = false;
    }
  }

  Future<bool> _hasInternet() async {
    for (final host in const ['1.1.1.1', '8.8.8.8']) {
      try {
        final s = await Socket.connect(host, 443,
            timeout: const Duration(seconds: 3));
        s.destroy();
        return true;
      } catch (_) {}
    }
    return false;
  }

  /// Every few seconds: pause on lost internet, resume when it is back.
  bool _netBusy = false;

  Future<void> _netTick() async {
    if (_netBusy) return; // the previous check (up to ~6 s) is still running
    _netBusy = true;
    try {
      await _netCheck();
    } finally {
      _netBusy = false;
    }
  }

  Future<void> _netCheck() async {
    if (!autoRetry) return;
    final running = items.any((e) => e.status == DlStatus.downloading);
    if (!running && _waitingForNet.isEmpty) {
      _offlineTicks = 0;
      return;
    }
    // bytes are arriving right now: the internet is clearly there, whatever
    // the test servers say
    final flowing = items.any(
        (e) => e.status == DlStatus.downloading && e.speed > 0);
    final online = flowing || await _hasInternet();
    if (!online) {
      if (running && ++_offlineTicks >= 2) {
        for (final it
            in items.where((e) => e.status == DlStatus.downloading).toList()) {
          pause(it);
          _waitingForNet.add(it.id);
          _retryAt[it.id] = 0;
        }
        notifyListeners();
      }
      return;
    }
    _offlineTicks = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in _waitingForNet.toList()) {
      if ((_retryAt[id] ?? 0) > now) continue;
      final it = items.where((e) => e.id == id).firstOrNull;
      _waitingForNet.remove(id);
      if (it != null && it.status == DlStatus.paused) start(it);
    }
  }

  /// Network-type problems are retried by themselves; others are final.
  bool _isTransient(Object e) {
    if (!autoRetry) return false;
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return true;
        case DioExceptionType.badResponse:
          final c = e.response?.statusCode ?? 0;
          return c >= 500 || c == 429 || c == 408;
        case DioExceptionType.unknown:
          final x = e.error;
          return x is SocketException || x is HttpException || x is TlsException;
        default:
          return false;
      }
    }
    if (e is SocketException || e is HttpException || e is TlsException) {
      return true;
    }
    if (e is String) {
      return e.startsWith('Connection timed out') ||
          e.startsWith('No internet connection') ||
          e.startsWith('Server error (5');
    }
    return false;
  }

  /// Put a download that hit a network problem on the retry list. False when
  /// it failed too many times without any progress (then it is a real failure).
  bool _scheduleRetry(DownloadItem item, _Run run) {
    if (item.downloaded > run.startBytes) _failStreak[item.id] = 0;
    final n = (_failStreak[item.id] ?? 0) + 1;
    _failStreak[item.id] = n;
    if (n > 12) return false;
    final secs = (5 * (1 << (n > 4 ? 4 : n - 1))).clamp(5, 60);
    _retryAt[item.id] =
        DateTime.now().millisecondsSinceEpoch + secs * 1000;
    _waitingForNet.add(item.id);
    item.status = DlStatus.paused;
    item.speed = 0;
    return true;
  }

  // ---------------------------------------------------------------- init

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    wifiOnly = _prefs!.getBool('wifi_only') ?? false;
    maxActive = _prefs!.getInt('max_active') ?? 3;
    speedLimit = _prefs!.getInt('speed_limit') ?? 0;
    browserLimit = _prefs!.getInt('browser_limit') ?? 0;
    autoRetry = _prefs!.getBool('auto_retry') ?? true;
    sortByType = _prefs!.getBool('sort_by_type') ?? true;
    _wifiTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      _wifiTick();
      _netTick();
    });
    final raw = _prefs!.getString('items');
    if (raw != null) {
      try {
        // one damaged entry must not make the whole list disappear
        for (final e in jsonDecode(raw) as List) {
          try {
            items.add(DownloadItem.fromJson(e as Map<String, dynamic>));
          } catch (_) {}
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setString(
        'items', jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// Download folder: Download/SDM (falls back to the app's own folder without
  /// permission). A folder from the old name "FastGet" is kept if it exists, so
  /// earlier downloads stay together with new ones.
  Future<String> downloadDir() async {
    if (_dir != null) return _dir!;
    String? path;
    if (Platform.isAndroid) {
      var st = await Permission.manageExternalStorage.status;
      if (!st.isGranted) st = await Permission.manageExternalStorage.request();
      if (!st.isGranted) {
        final s2 = await Permission.storage.request();
        if (s2.isGranted) st = s2;
      }
      if (st.isGranted) {
        final d = await _appFolder('/storage/emulated/0/Download');
        try {
          await d.create(recursive: true);
          path = d.path;
        } catch (_) {}
      }
    }
    if (path == null) {
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final d = await _appFolder(base.path);
      await d.create(recursive: true);
      path = d.path;
    }
    return _dir = path;
  }

  static const _folderName = 'SDM';
  static const _legacyFolderName = 'FastGet';

  Future<Directory> _appFolder(String root) async {
    final old = Directory('$root/$_legacyFolderName');
    try {
      if (await old.exists()) return old;
    } catch (_) {}
    return Directory('$root/$_folderName');
  }

  /// The default download folder as far as it is known right now (before the
  /// first download it is the usual place).
  String get defaultDirSync =>
      _dir ?? '/storage/emulated/0/Download/$_folderName';

  // ----------------------------------------------------------------- add

  /// Folder last chosen in the download popup; falls back to the default folder.
  Future<String> preferredDir() async {
    final saved = _prefs?.getString('save_dir');
    if (saved != null && saved.isNotEmpty) {
      try {
        if (await Directory(saved).exists()) return saved;
      } catch (_) {}
    }
    return downloadDir();
  }

  Future<void> setPreferredDir(String path) async {
    await _prefs?.setString('save_dir', path);
  }

  Future<DownloadItem> addUrl(String rawUrl,
      {Map<String, String>? headers,
      String? suggestedName,
      String? dirPath,
      ProbeResult? probe}) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw 'Enter a valid http/https link';
    }
    final given = (dirPath != null && dirPath.isNotEmpty) ? dirPath : null;
    final hasDir = given != null;
    if (given != null) {
      try {
        await Directory(given).create(recursive: true);
      } catch (_) {
        throw 'Cannot save to this folder. Please choose another one.';
      }
    }
    final hdrs = headers ?? const <String, String>{};
    final info = probe ?? await inspect(url, headers: hdrs);
    var baseName = (suggestedName != null && suggestedName.trim().isNotEmpty
            ? _sanitize(suggestedName)
            : null) ??
        info.fileName ??
        _nameFromUrl(uri);
    if (info.hls) {
      baseName = baseName.replaceAll(RegExp(r'\.m3u8$', caseSensitive: false), '');
      if (!baseName.contains('.')) baseName = '$baseName.ts';
    }
    // no folder given: the type folder inside the download folder
    var dir = given ?? sortedDir(await preferredDir(), baseName);
    if (!hasDir) {
      try {
        await Directory(dir).create(recursive: true);
      } catch (_) {
        dir = await preferredDir();
      }
    }
    final name = _uniqueName(dir, baseName);
    if (info.contentType != null &&
        _isHtmlType(info.contentType) &&
        !_nameIsWebPage(name)) {
      throw 'This link opens a web page, not a downloadable file';
    }
    final item = DownloadItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: url,
      fileName: name,
      dirPath: dir,
      total: info.total,
      rangeSupported: info.range,
      hls: info.hls,
      headers: hdrs,
      validator: info.validator,
    );
    items.insert(0, item);
    await _save();
    notifyListeners();
    start(item);
    return item;
  }

  // ------------------------------------------------------------- control

  void start(DownloadItem item) {
    final live = _runs[item.id];
    if (live != null) {
      // paused a moment ago and resumed at once: the old run is still
      // stopping, so start again as soon as it is gone
      if (live.token.isCancelled) _startAfterStop.add(item.id);
      return;
    }
    _waitingForNet.remove(item.id);
    if (item.status == DlStatus.completed) return;
    if (wifiOnly) {
      // Decide asynchronously; the item shows "Waiting for Wi-Fi" meanwhile.
      _startWhenAllowed(item);
      return;
    }
    _begin(item);
  }

  Future<void> _startWhenAllowed(DownloadItem item) async {
    if (await _onWifi()) {
      _waitingForWifi.remove(item.id);
      _begin(item);
    } else {
      item.status = DlStatus.paused;
      item.speed = 0;
      _waitingForWifi.add(item.id);
      notifyListeners();
      await _save();
    }
  }

  /// True on Wi-Fi / Ethernet (also true when it cannot be told).
  Future<bool> onWifi() => _onWifi();

  Future<bool> _onWifi() async {
    try {
      return await _net.invokeMethod<bool>('isWifi') ?? true;
    } catch (_) {
      return true; // not Android, or channel missing: don't block downloads
    }
  }

  Future<void> setWifiOnly(bool v) async {
    wifiOnly = v;
    await _prefs?.setBool('wifi_only', v);
    notifyListeners();
    await _wifiTick();
  }

  Future<void> _wifiTick() async {
    if (!wifiOnly) {
      _resumeWifiWaiters();
      return;
    }
    final wifi = await _onWifi();
    if (!wifi) {
      for (final it in items
          .where((e) => e.status == DlStatus.downloading)
          .toList()) {
        pause(it);
        _waitingForWifi.add(it.id); // after pause(), which clears it
      }
    } else {
      _resumeWifiWaiters();
    }
  }

  /// Starts the downloads that were waiting for Wi-Fi.
  void _resumeWifiWaiters() {
    if (_waitingForWifi.isEmpty) return;
    final ids = _waitingForWifi.toList();
    _waitingForWifi.clear();
    for (final it in items.where((e) => ids.contains(e.id))) {
      if (it.status == DlStatus.paused) start(it);
    }
  }

  /// Deletes what was downloaded so far and starts the file again from zero.
  Future<void> redownload(DownloadItem item) async {
    final run = _runs[item.id];
    run?.token.cancel('redownload');
    _waitingForWifi.remove(item.id);
    item.status = DlStatus.paused;
    item.speed = 0;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 400));
    await _deleteParts(item);
    try {
      final f = File(item.savePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    item.downloaded = 0;
    item.segDone = 0;
    item.error = null;
    await _save();
    notifyListeners();
    start(item);
  }

  void _begin(DownloadItem item) {
    if (_runs.containsKey(item.id)) return;
    if (_runs.length >= maxActive) {
      // all slots busy: wait in the queue
      item.status = DlStatus.queued;
      item.speed = 0;
      item.error = null;
      notifyListeners();
      _save();
      return;
    }
    item.status = DlStatus.downloading;
    item.error = null;
    final run = _Run()..startBytes = item.downloaded;
    _runs[item.id] = run;
    notifyListeners();
    _execute(item, run);
  }

  void pause(DownloadItem item) {
    // a "start again when the old run stops" request is void once paused
    _startAfterStop.remove(item.id);
    _waitingForNet.remove(item.id);
    _waitingForWifi.remove(item.id);
    final run = _runs[item.id];
    item.status = DlStatus.paused;
    item.speed = 0;
    run?.token.cancel('paused');
    notifyListeners();
    _save();
  }

  /// Pauses everything that is running (notification "Pause all").
  void pauseAll() {
    for (final it
        in items.where((e) => e.status == DlStatus.downloading).toList()) {
      pause(it);
    }
  }

  /// Resumes everything that is paused (notification "Resume all").
  void resumeAll() {
    for (final it in items
        .where((e) =>
            e.status == DlStatus.paused || e.status == DlStatus.queued)
        .toList()) {
      start(it);
    }
  }

  /// True when something is downloading right now.
  bool get anyRunning => items.any((e) => e.status == DlStatus.downloading);

  /// True when there is at least one unfinished (running or paused) download,
  /// i.e. the home screen's on/off switch has something to control.
  bool get hasUnfinished => items.any((e) =>
      e.status == DlStatus.downloading ||
      e.status == DlStatus.paused ||
      e.status == DlStatus.queued);

  /// Master switch on the home screen: ON resumes everything, OFF pauses it.
  void setDownloadsOn(bool on) {
    if (on) {
      resumeAll();
    } else {
      pauseAll();
    }
  }

  /// Pull-to-refresh on the home list: re-checks Wi-Fi waiting items and
  /// redraws the list.
  Future<void> refresh() async {
    await _wifiTick();
    await _save();
    notifyListeners();
  }

  /// Folder chosen as default (shown in settings).
  String get preferredDirSync =>
      _prefs?.getString('save_dir') ?? defaultDirSync;

  /// Removes several downloads at once.
  Future<void> removeMany(Iterable<DownloadItem> list,
      {bool deleteFiles = false}) async {
    final all = list.toList();
    for (final it in all) {
      _runs[it.id]?.token.cancel('removed');
      items.remove(it);
      _waitingForNet.remove(it.id);
      _waitingForWifi.remove(it.id);
      _startAfterStop.remove(it.id);
      _retryAt.remove(it.id);
      _failStreak.remove(it.id);
    }
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 300));
    for (final it in all) {
      await _deleteParts(it);
      if (deleteFiles) {
        try {
          final f = File(it.savePath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    await _save();
  }

  Future<void> remove(DownloadItem item, {bool deleteFile = false}) =>
      removeMany([item], deleteFiles: deleteFile);

  // ------------------------------------------------------------- engine

  Future<void> _execute(DownloadItem item, _Run run) async {
    try {
      // Re-probe if metadata is unknown
      if (!item.hls && item.total <= 0) {
        final p = await inspect(item.url, headers: item.headers);
        item.total = p.total;
        item.rangeSupported = p.range;
      }

      // A paused download is only resumed if the file on the server is still
      // the same one; otherwise the old pieces would be glued to new data and
      // give a broken file. Changed file: start again from zero.
      if (!item.hls && item.validator != null && item.downloaded > 0) {
        try {
          final p = await inspect(item.url, headers: item.headers);
          if (p.validator != null && p.validator != item.validator) {
            await _deleteParts(item);
            item.downloaded = 0;
            item.total = p.total;
            item.rangeSupported = p.range;
            item.validator = p.validator;
          }
        } catch (_) {} // no answer now: the normal retry logic handles it
      }

      run.ticker = _startTicker(item, run);

      if (item.hls) {
        await _hlsDownload(item, run);
      } else if (item.rangeSupported && item.total > 0) {
        await _multiSegment(item, run);
      } else {
        await _singleStream(item, run);
      }

      run.ticker?.cancel();
      item.downloaded = item.total > 0 ? item.total : item.downloaded;
      item.status = DlStatus.completed;
      item.speed = 0;
    } on DioException catch (e) {
      run.ticker?.cancel();
      item.speed = 0;
      if (CancelToken.isCancel(e)) {
        // pause()/remove() already set the status
      } else if (_isTransient(e) && _scheduleRetry(item, run)) {
        // network problem: retried automatically
      } else {
        item.status = DlStatus.failed;
        item.error = _dioMessage(e);
      }
    } catch (e) {
      run.ticker?.cancel();
      item.speed = 0;
      if (run.token.isCancelled && !run.failed) {
        // paused / removed: the status is already set
      } else if (_isTransient(e) && _scheduleRetry(item, run)) {
        // network problem: retried automatically
      } else {
        item.status = DlStatus.failed;
        item.error = e.toString();
      }
    } finally {
      // stop any request of this run that is still open
      if (!run.token.isCancelled) run.token.cancel('run finished');
      _runs.remove(item.id);
      if (item.status == DlStatus.completed) {
        _failStreak.remove(item.id);
        _retryAt.remove(item.id);
      }
      notifyListeners();
      await _save();
      if (_startAfterStop.remove(item.id) &&
          items.contains(item) &&
          item.status == DlStatus.paused) {
        start(item);
      }
      _pump(); // a slot is free: start the next queued download
    }
  }

  Timer _startTicker(DownloadItem item, _Run run) {
    var last = item.downloaded;
    var lastTime = DateTime.now();
    var save = 0;
    return Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now();
      final dt = now.difference(lastTime).inMilliseconds / 1000.0;
      if (dt <= 0) return;
      final cur = item.downloaded;
      final inst = (cur - last) / dt;
      item.speed = item.speed == 0 ? inst : item.speed * 0.6 + inst * 0.4;
      run.speed = item.speed;
      last = cur;
      lastTime = now;
      notifyListeners();
      if (++save % 10 == 0) _save();
    });
  }

  Future<void> _multiSegment(DownloadItem item, _Run run) async {
    final total = item.total;
    final n = _segCountFor(item);
    final base = total ~/ n;
    final starts = <int>[];
    final ends = <int>[];
    for (var i = 0; i < n; i++) {
      starts.add(i * base);
      ends.add(i == n - 1 ? total - 1 : (i + 1) * base - 1);
    }

    run.segBytes = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final f = File(_partPath(item, i));
      if (await f.exists()) {
        var len = await f.length();
        final segLen = ends[i] - starts[i] + 1;
        if (len > segLen) {
          final raf = await f.open(mode: FileMode.append);
          await raf.truncate(segLen);
          await raf.close();
          len = segLen;
        }
        run.segBytes[i] = len;
      }
    }
    _syncDownloaded(item, run);

    // If one piece fails, stop the others at once (and wait for them), so that
    // nothing keeps writing to the part files while a retry starts over them.
    try {
      await Future.wait(
        [
          for (var i = 0; i < n; i++)
            _downloadSegment(item, run, i, starts[i], ends[i]).catchError(
              (Object e, StackTrace st) {
                if (!run.token.isCancelled) {
                  run.failed = true;
                  run.failure = e;
                  run.failureTrace = st;
                  run.token.cancel('piece failed');
                }
                Error.throwWithStackTrace(e, st);
              },
            ),
        ],
        eagerError: false,
      );
    } catch (e, st) {
      // report the piece that really failed, not a stopped piece's cancel
      final real = run.failure;
      if (real != null) Error.throwWithStackTrace(real, run.failureTrace ?? st);
      rethrow;
    }

    // every piece must be complete before they are joined
    for (var i = 0; i < n; i++) {
      if (run.segBytes[i] != ends[i] - starts[i] + 1) {
        throw const HttpException('Connection closed before the piece was complete');
      }
    }
    await _merge(item, run);
  }

  Future<void> _downloadSegment(
      DownloadItem item, _Run run, int index, int start, int end) async {
    final already = run.segBytes[index];
    final from = start + already;
    if (from > end) return; // this segment is already complete

    final resp = await _dio.get<ResponseBody>(
      item.url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...item.headers, 'Range': 'bytes=$from-$end'},
        receiveTimeout: const Duration(seconds: 60),
      ),
      cancelToken: run.token,
    );
    if (resp.statusCode != 206) {
      throw 'Server did not honour Range request (${resp.statusCode})';
    }
    if (_isHtmlType(resp.headers.value('content-type')) &&
        !_nameIsWebPage(item.fileName)) {
      throw 'Server returned a web page instead of the file';
    }

    final sink = File(_partPath(item, index)).openWrite(mode: FileMode.append);
    try {
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        run.segBytes[index] += chunk.length;
        _syncDownloaded(item, run);
        await _pace(run, chunk.length);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  void _syncDownloaded(DownloadItem item, _Run run) {
    var sum = 0;
    for (final b in run.segBytes) {
      sum += b;
    }
    item.downloaded = sum;
  }

  /// Plain GET of a small text file (playlists). Used by the browser too.
  Future<String> fetchText(String url, {Map<String, String>? headers}) async {
    if (isUnsupportedHost(url)) throw unsupportedMessage;
    try {
      final r = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      return r.data ?? '';
    } on DioException catch (e) {
      throw _dioMessage(e);
    }
  }

  /// HLS (.m3u8): pieces are fetched a few at a time, written in order into
  /// one file, and can be paused / resumed at a piece boundary.
  Future<void> _hlsDownload(DownloadItem item, _Run run) async {
    var url = Uri.parse(item.url);
    var text = (await _dio.get<String>(
      item.url,
      options: Options(responseType: ResponseType.plain, headers: item.headers),
      cancelToken: run.token,
    ))
            .data ??
        '';
    if (isMasterPlaylist(text)) {
      final m = parseMaster(text, url);
      if (m.variants.isEmpty) throw 'No video found in this stream';
      url = m.variants.first.url; // best quality
      text = (await _dio.get<String>(
        url.toString(),
        options:
            Options(responseType: ResponseType.plain, headers: item.headers),
        cancelToken: run.token,
      ))
              .data ??
          '';
    }
    final media = parseMedia(text, url);
    if (media.encrypted) {
      throw 'Protected (encrypted) streams cannot be downloaded';
    }
    if (media.live) throw 'Live streams cannot be downloaded';
    if (media.segments.isEmpty) throw 'No video found in this stream';

    final part = File(_partPath(item, 0));
    if (item.segDone > 0 && await part.exists()) {
      // drop anything written after the last saved position
      final raf = await part.open(mode: FileMode.append);
      try {
        if (await raf.length() > item.downloaded) {
          await raf.truncate(item.downloaded);
        }
      } finally {
        await raf.close();
      }
    } else {
      item.segDone = 0;
      item.downloaded = 0;
      if (await part.exists()) await part.delete();
    }

    Future<List<int>> fetch(Uri u) async {
      Object? last;
      for (var attempt = 0; attempt < 4; attempt++) {
        if (run.token.isCancelled) throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel);
        try {
          final r = await _dio.get<List<int>>(
            u.toString(),
            options: Options(
                responseType: ResponseType.bytes, headers: item.headers),
            cancelToken: run.token,
          );
          final data = r.data ?? const <int>[];
          await _pace(run, data.length);
          return data;
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) rethrow;
          last = e;
          await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
        }
      }
      throw last is DioException ? _dioMessage(last) : 'Download failed';
    }

    final sink = part.openWrite(mode: FileMode.append);
    try {
      if (item.segDone == 0 && media.init != null) {
        final b = await fetch(media.init!);
        sink.add(b);
        item.downloaded += b.length;
      }
      final segs = media.segments;
      const window = 6;
      final inflight = <int, Future<List<int>>>{};
      var next = item.segDone;
      void fill() {
        while (inflight.length < window && next < segs.length) {
          final i = next++;
          final f = fetch(segs[i]);
          f.ignore(); // errors are handled when awaited in order
          inflight[i] = f;
        }
      }

      fill();
      for (var i = item.segDone; i < segs.length; i++) {
        final bytes = await inflight.remove(i)!;
        sink.add(bytes);
        item.downloaded += bytes.length;
        item.segDone = i + 1;
        // estimate the total so the progress bar and ETA work
        item.total = (item.downloaded / item.segDone * segs.length).round();
        fill();
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    item.total = item.downloaded;
    // fMP4 / audio streams get a fitting extension instead of .ts
    final first = media.segments.first.path.toLowerCase();
    String? ext;
    if (first.endsWith('.aac')) {
      ext = 'aac';
    } else if (first.endsWith('.mp3')) {
      ext = 'mp3';
    } else if (media.init != null ||
        first.endsWith('.m4s') ||
        first.endsWith('.mp4')) {
      ext = 'mp4';
    }
    final out0 = item.savePath;
    if (ext != null && item.fileName.toLowerCase().endsWith('.ts')) {
      final nn = '${item.fileName.substring(0, item.fileName.length - 3)}.$ext';
      if (!File('${item.dirPath}/$nn').existsSync()) {
        final tmp = File(out0);
        if (await tmp.exists()) await tmp.delete();
        final target = '${item.dirPath}/$nn';
        await part.rename(target);
        item.fileName = nn;
        return;
      }
    }
    final out = File(out0);
    if (await out.exists()) await out.delete();
    await part.rename(out0);
  }

  Future<void> _singleStream(DownloadItem item, _Run run) async {
    final part = File(_partPath(item, 0));
    if (await part.exists()) await part.delete(); // cannot resume a single stream
    item.downloaded = 0;

    final resp = await _dio.get<ResponseBody>(
      item.url,
      options:
          Options(responseType: ResponseType.stream, headers: item.headers),
      cancelToken: run.token,
    );
    if (_isHtmlType(resp.headers.value('content-type')) &&
        !_nameIsWebPage(item.fileName)) {
      throw 'Server returned a web page instead of the file';
    }
    final sink = part.openWrite();
    try {
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        item.downloaded += chunk.length;
        await _pace(run, chunk.length);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (item.total > 0 && await part.length() != item.total) {
      throw 'Download incomplete (size mismatch)';
    }
    final out = File(item.savePath);
    if (await out.exists()) await out.delete();
    await part.rename(item.savePath);
  }

  Future<void> _merge(DownloadItem item, _Run run) async {
    final n = _segCountFor(item);
    final out = File(item.savePath);
    if (await out.exists()) await out.delete();
    final sink = out.openWrite();
    try {
      for (var i = 0; i < n; i++) {
        // paused or removed while joining: stop; the pieces are kept
        if (run.token.isCancelled && !run.failed) {
          throw DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.cancel);
        }
        final p = File(_partPath(item, i));
        if (await p.exists()) {
          await sink.addStream(p.openRead());
        }
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      try {
        await out.delete(); // never leave a half-joined file behind
      } catch (_) {}
      rethrow;
    }
    await sink.close();
    if (item.total > 0 && await out.length() != item.total) {
      try {
        await out.delete();
      } catch (_) {}
      for (var i = 0; i < n; i++) {
        try {
          final f = File(_partPath(item, i));
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      throw 'Download incomplete (size mismatch)';
    }
    await _deleteParts(item);
  }

  Future<void> _deleteParts(DownloadItem item) async {
    final n = _segCountFor(item, create: false);
    for (var i = 0; i < n; i++) {
      try {
        final f = File(_partPath(item, i));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    try {
      final m = File(_segMarkerPath(item));
      if (await m.exists()) await m.delete();
    } catch (_) {}
  }

  String _segMarkerPath(DownloadItem item) =>
      '${item.dirPath}/.${item.fileName}.segs';

  /// How many pieces this download is split into. Decided once per download
  /// (and remembered in a tiny marker file) so a resumed download always uses
  /// the same split as the pieces already on disk.
  int _segCountFor(DownloadItem item, {bool create = true}) {
    try {
      final marker = File(_segMarkerPath(item));
      if (marker.existsSync()) {
        final n = int.tryParse(marker.readAsStringSync().trim());
        if (n != null && n >= 1 && n <= 32) return n;
      }
      // started by an older version: 4 pieces and no marker
      if (File(_partPath(item, 0)).existsSync()) return kSegments;
      final n = item.total >= kBigFileBytes ? kBigFileSegments : kSegments;
      if (create) marker.writeAsStringSync('$n');
      return n;
    } catch (_) {
      return kSegments;
    }
  }

  String _partPath(DownloadItem item, int i) =>
      '${item.dirPath}/.${item.fileName}.part$i';

  // ------------------------------------------------------------- helpers

  /// Inspects [url] (without downloading the body): size, Range support,
  /// file name and content type.
  Future<ProbeResult> inspect(String url,
      {Map<String, String>? headers}) async {
    if (isUnsupportedHost(url)) throw unsupportedMessage;
    if (_looksHls(url, null)) {
      return const ProbeResult(-1, true, null, 'application/vnd.apple.mpegurl',
          hls: true);
    }
    final token = CancelToken();
    try {
      final resp = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...?headers, 'Range': 'bytes=0-0'},
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: token,
      );
      final h = resp.headers;
      var total = -1;
      var range = false;
      if (resp.statusCode == 206) {
        range = true;
        final cr = h.value('content-range'); // bytes 0-0/12345
        final slash = cr?.lastIndexOf('/') ?? -1;
        if (cr != null && slash >= 0) {
          total = int.tryParse(cr.substring(slash + 1)) ?? -1;
        }
      } else {
        total = int.tryParse(h.value('content-length') ?? '') ?? -1;
      }
      final name = _nameFromDisposition(h.value('content-disposition'));
      final type = h.value('content-type');
      token.cancel('probe done');
      if (_looksHls(url, type)) {
        return const ProbeResult(-1, true, null, 'application/vnd.apple.mpegurl',
            hls: true);
      }
      final validator = h.value('etag') ?? h.value('last-modified');
      return ProbeResult(total, range && total > 0, name, type,
          validator: validator);
    } on DioException catch (e) {
      throw _dioMessage(e);
    }
  }

  String? _nameFromDisposition(String? cd) {
    if (cd == null) return null;
    final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)",
            caseSensitive: false)
        .firstMatch(cd);
    if (star != null) {
      try {
        return _sanitize(Uri.decodeComponent(star.group(1)!.trim()));
      } catch (_) {}
    }
    final plain =
        RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false)
            .firstMatch(cd);
    if (plain != null) return _sanitize(plain.group(1)!.trim());
    return null;
  }

  String _nameFromUrl(Uri uri) {
    var n = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    try {
      n = Uri.decodeComponent(n);
    } catch (_) {}
    n = _sanitize(n);
    return n.isEmpty ? 'download_${DateTime.now().millisecondsSinceEpoch}' : n;
  }

  String _sanitize(String n) {
    final s = n.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    // "." and ".." would point at a folder, not a file
    return RegExp(r'^\.+$').hasMatch(s) ? '_' : s;
  }

  String _uniqueName(String dir, String name) {
    final taken = items.map((e) => e.fileName).toSet();
    bool exists(String n) => taken.contains(n) || File('$dir/$n').existsSync();
    if (!exists(name)) return name;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (exists('$stem ($i)$ext')) {
      i++;
    }
    return '$stem ($i)$ext';
  }

  String _dioMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection timed out';
      case DioExceptionType.connectionError:
        return 'No internet connection or server unreachable';
      case DioExceptionType.badResponse:
        return 'Server error (${e.response?.statusCode})';
      default:
        return e.message ?? 'Unknown error';
    }
  }
}
