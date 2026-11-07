import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_manager.dart';
import 'patcher.dart';

/// GitHub repository that publishes SDM builds as Releases.
const String kRepo = 'sabbirahmed77708-sudo/SDM';

class UpdateInfo {
  final int build;
  final String name;
  final String notes;
  final String apkUrl;
  final int size;

  /// Small patch from the installed build to this one (optional): only the
  /// changed part is downloaded, the app rebuilds the full APK from it.
  final String? patchUrl;
  final int patchSize;
  final String? shaUrl; // hash of the full new APK, to check the rebuilt file
  final DateTime? published; // when this build was released (local time)
  const UpdateInfo({
    required this.build,
    required this.name,
    required this.notes,
    required this.apkUrl,
    required this.size,
    this.patchUrl,
    this.patchSize = 0,
    this.shaUrl,
    this.published,
  });

  bool get hasPatch => patchUrl != null && shaUrl != null && patchSize > 0;

  /// What really has to be downloaded.
  int get downloadSize => hasPatch ? patchSize : size;
}

const MethodChannel _appCh = MethodChannel('drom/app');

enum UpdatePhase { idle, downloading, patching, ready, error }

/// Looks for a newer SDM build in the GitHub Releases of [kRepo].
///
/// The CI publishes every build as a release tagged `build-<number>`; the app
/// compares that number with its own build number.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  bool checking = false;
  bool checkedOnce = false; // a check finished without a network error
  String? error;
  UpdateInfo? available;

  String version = '';
  int build = 0;

  bool get hasUpdate => available != null;

  // ---- in-app update: download, then open the installer
  UpdatePhase phase = UpdatePhase.idle;
  int received = 0;
  int totalBytes = 0;
  String? updateError;
  String? _apkPath;
  int _readyBuild = 0; // build of the APK that is downloaded and waiting
  int _patchFailedBuild = 0; // patch did not work for this build: use full APK

  /// True while only the small patch (not the whole APK) is being downloaded.
  bool usingPatch = false;
  CancelToken? _token;

  /// Build number the "update available" pop-up was already shown for.
  int promptedBuild = 0;

  /// The "update ready" banner on the home screen was closed for this build.
  int bannerClosedBuild = 0;
  void closeReadyBanner() {
    bannerClosedBuild = _readyBuild;
    notifyListeners();
  }

  /// Home screen banner: only when the download is finished and waiting.
  bool get showReadyBanner =>
      phase == UpdatePhase.ready &&
      available != null &&
      bannerClosedBuild != _readyBuild;

  // ---- automatic update (like the Play Store / Messenger)
  /// When ON, a new version is downloaded by itself in the background
  /// (on Wi-Fi only) and only the final "Install" tap is left.
  bool autoUpdate = true;
  bool _settingsLoaded = false;

  /// Download speed (bytes/s, smoothed) and time left for the progress line.
  double speed = 0;
  int get etaSeconds => (speed > 0 && totalBytes > received)
      ? ((totalBytes - received) / speed).round()
      : -1;

  /// True when the new version was downloaded by itself and is waiting for
  /// the person to tap "Install".
  bool autoDownloaded = false;

  Future<void> loadSettings() async {
    if (_settingsLoaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      autoUpdate = p.getBool('auto_update') ?? true;
      _settingsLoaded = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setAutoUpdate(bool v) async {
    autoUpdate = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('auto_update', v);
    } catch (_) {}
    if (v) _maybeAutoDownload();
  }

  /// Starts the background download by itself when allowed.
  /// [manual]: the person tapped "Check for update", so it starts at once on
  /// any network; the by-itself background check waits for Wi-Fi.
  Future<void> _maybeAutoDownload({bool manual = false}) async {
    final info = available;
    if (!autoUpdate || info == null) return;
    if (phase != UpdatePhase.idle || _autoStarting) return;
    _autoStarting = true;
    try {
      // mobile data is not used for a big update without asking
      if (!manual && !await DownloadManager.instance.onWifi()) return;
      await startUpdate(auto: true);
    } finally {
      _autoStarting = false;
      // lets the screen ask the person instead (e.g. not on Wi-Fi)
      if (phase == UpdatePhase.idle) notifyListeners();
    }
  }

  bool _autoStarting = false;

  /// An update download is running, or is about to start by itself.
  bool get busy => phase != UpdatePhase.idle || _autoStarting;

  double get progress =>
      totalBytes > 0 ? (received / totalBytes).clamp(0.0, 1.0).toDouble() : 0;

  /// Downloads the new APK inside SDM and opens the installer when done.
  ///
  /// With [auto] the installer is not opened by itself: the person is asked
  /// first (see [maybePromptUpdate]).
  Future<void> startUpdate({bool auto = false}) async {
    final info = available;
    if (info == null ||
        phase == UpdatePhase.downloading ||
        phase == UpdatePhase.patching) {
      return;
    }
    phase = UpdatePhase.downloading;
    received = 0;
    speed = 0;
    usingPatch = info.hasPatch && _patchFailedBuild != info.build;
    totalBytes = usingPatch ? info.patchSize : info.size;
    updateError = null;
    autoDownloaded = auto;
    notifyListeners();
    final token = _token = CancelToken();
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/DROM-update-${info.build}.apk';
      final tmp = '$path.part';

      // already downloaded earlier (app was closed before installing)?
      final done = File(path);
      if (await done.exists() &&
          (info.size <= 0 || await done.length() == info.size)) {
        _apkPath = path;
        received = totalBytes = await done.length();
        await _rememberPending(info);
        _readyBuild = info.build;
        phase = UpdatePhase.ready;
        notifyListeners();
        if (!auto) await install();
        return;
      }
      // old / other update files are not needed any more
      for (final f in dir.listSync()) {
        if (f is File &&
            f.path.contains('DROM-update-') &&
            f.path != path) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        followRedirects: true,
        maxRedirects: 8,
        headers: {'User-Agent': 'SDM-app'},
      ));
      // 1) the small patch: download only what changed and rebuild the APK
      var rebuilt = false;
      if (usingPatch) {
        try {
          rebuilt = await _tryPatch(dio, info, path, tmp, token);
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) rethrow;
        } catch (_) {}
        if (!rebuilt) {
          // anything went wrong: the full APK takes over, safe and simple
          _patchFailedBuild = info.build;
          usingPatch = false;
          phase = UpdatePhase.downloading;
          received = 0;
          speed = 0;
          totalBytes = info.size;
          notifyListeners();
        }
      }
      // 2) the full APK
      if (!rebuilt) {
        await _downloadFile(dio, info.apkUrl, tmp, token);
        final f = File(tmp);
        if (info.size > 0 && await f.length() != info.size) {
          await f.delete();
          throw 'Update download incomplete';
        }
        await f.rename(path);
      }
      _apkPath = path;
      speed = 0;
      await _rememberPending(info);
      _readyBuild = info.build;
      phase = UpdatePhase.ready;
      notifyListeners();
      if (!auto) await install();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        phase = UpdatePhase.idle;
      } else {
        phase = UpdatePhase.error;
        updateError = 'Update download failed. Check your internet and try again.';
      }
      notifyListeners();
    } catch (e) {
      phase = UpdatePhase.error;
      updateError = e.toString();
      notifyListeners();
    }
  }

  /// Downloads [url] to [savePath] and keeps progress / speed up to date.
  Future<void> _downloadFile(
      Dio dio, String url, String savePath, CancelToken token) async {
    received = 0;
    var tick = DateTime.now();
    var lastBytes = 0;
    await dio.download(
      url,
      savePath,
      cancelToken: token,
      onReceiveProgress: (r, t) {
        received = r;
        if (t > 0) totalBytes = t;
        final now = DateTime.now();
        final ms = now.difference(tick).inMilliseconds;
        // update the screen about 8 times a second, and at the very end
        if (ms > 120 || (t > 0 && r >= t)) {
          final inst = (r - lastBytes) * 1000 / ms;
          speed = speed == 0 ? inst : speed * 0.7 + inst * 0.3;
          lastBytes = r;
          tick = now;
          notifyListeners();
        }
      },
    );
  }

  /// Downloads the small patch, rebuilds the new APK from the installed one
  /// and checks it against the published SHA-256. Returns false on any problem
  /// (the caller then downloads the full APK).
  Future<bool> _tryPatch(Dio dio, UpdateInfo info, String path, String tmp,
      CancelToken token) async {
    final patchPath = '$path.patch';
    // hash of the finished APK (a tiny text file)
    final r = await dio.get<String>(info.shaUrl!,
        cancelToken: token,
        options: Options(responseType: ResponseType.plain));
    final sha = (r.data ?? '').trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return false;

    await _downloadFile(dio, info.patchUrl!, patchPath, token);
    if (await File(patchPath).length() != info.patchSize) return false;

    phase = UpdatePhase.patching;
    speed = 0;
    notifyListeners();
    final oldApk =
        await const MethodChannel('drom/app').invokeMethod<String>('apkPath');
    if (oldApk == null || !File(oldApk).existsSync()) return false;
    final got = await applyDromPatchInBackground(oldApk, patchPath, tmp);
    try {
      File(patchPath).deleteSync();
    } catch (_) {}
    if (got != sha) {
      try {
        File(tmp).deleteSync();
      } catch (_) {}
      return false;
    }
    await File(tmp).rename(path);
    return true;
  }

  void cancelUpdate() {
    _token?.cancel('cancelled');
  }

  /// Opens Android's installer for the downloaded APK.
  Future<void> install() async {
    final path = _apkPath;
    if (path == null || !File(path).existsSync()) {
      phase = UpdatePhase.idle;
      notifyListeners();
      return;
    }
    try {
      // Android's own message ("package conflicts...") is cryptic: check the
      // signing key first and explain.
      try {
        final c = await _appCh.invokeMethod<String>('apkCompat', {'path': path});
        if (c == 'signature') {
          phase = UpdatePhase.error;
          updateError =
              'This build was signed with a different key, so Android will not install it over the current app. Uninstall SDM once and install the new version; after that updates install normally.';
          notifyListeners();
          return;
        }
        if (c == 'invalid') {
          try {
            File(path).deleteSync();
          } catch (_) {}
          phase = UpdatePhase.error;
          updateError = 'The downloaded update file is damaged. Try again.';
          _apkPath = null;
          notifyListeners();
          return;
        }
      } catch (_) {}
      if (!await Permission.requestInstallPackages.isGranted) {
        // opens "Install unknown apps" for SDM, once
        await Permission.requestInstallPackages.request();
      }
      final r = await OpenFilex.open(path,
          type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        phase = UpdatePhase.error;
        updateError = 'Could not open the installer. Allow "Install unknown apps" for SDM.';
        notifyListeners();
      }
    } catch (_) {
      phase = UpdatePhase.error;
      updateError = 'Could not open the installer.';
      notifyListeners();
    }
  }

  // ---- "What's new" after the update is installed
  /// Saves the release notes of the version being installed, so they can be
  /// shown once the app starts again on the new version.
  Future<void> _rememberPending(UpdateInfo info) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('pending_build', info.build);
      await p.setString('pending_name', info.name);
      await p.setString('pending_notes', info.notes);
    } catch (_) {}
  }

  /// Returns the notes of the update that was just installed (once), or null.
  /// Also removes the downloaded APK, which is not needed any more.
  Future<UpdateInfo?> takeWhatsNew() async {
    try {
      await loadVersion();
      final p = await SharedPreferences.getInstance();
      final pending = p.getInt('pending_build') ?? 0;
      if (pending <= 0 || build < pending) return null; // not installed yet
      final info = UpdateInfo(
        build: pending,
        name: p.getString('pending_name') ?? '',
        notes: p.getString('pending_notes') ?? '',
        apkUrl: '',
        size: 0,
      );
      await p.remove('pending_build');
      await p.remove('pending_name');
      await p.remove('pending_notes');
      try {
        final dir = await getTemporaryDirectory();
        for (final f in dir.listSync()) {
          if (f is File && f.path.contains('DROM-update-')) f.deleteSync();
        }
      } catch (_) {}
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<void> loadVersion() async {
    if (version.isNotEmpty) return;
    try {
      final p = await PackageInfo.fromPlatform();
      version = p.version;
      build = int.tryParse(p.buildNumber) ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> check({bool silent = false}) async {
    if (checking) return;
    checking = true;
    if (!silent) error = null;
    notifyListeners();
    try {
      await loadVersion();
      await loadSettings();
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'SDM-app',
        },
        validateStatus: (s) => s != null && (s < 400 || s == 404),
      ));
      final r = await dio.get<dynamic>(
          'https://api.github.com/repos/$kRepo/releases/latest');
      if (r.statusCode == 404 || r.data is! Map) {
        // no release published yet: nothing newer exists
        available = null;
        checkedOnce = true;
        error = null;
        return;
      }
      final data = Map<String, dynamic>.from(r.data as Map);
      final tag = (data['tag_name'] ?? '').toString();
      final m = RegExp(r'(\d+)\s*$').firstMatch(tag);
      final remote = m != null ? int.parse(m.group(1)!) : 0;

      String? apk, patchUrl, shaUrl;
      var size = 0, patchSize = 0;
      final patchName = 'drom-patch-from-$build.bin';
      for (final a in (data['assets'] as List? ?? const [])) {
        final am = Map<String, dynamic>.from(a as Map);
        final n = (am['name'] ?? '').toString().toLowerCase();
        final url = am['browser_download_url']?.toString();
        final sz = (am['size'] as num?)?.toInt() ?? 0;
        if (n.endsWith('.apk') && apk == null) {
          apk = url;
          size = sz;
        } else if (build > 0 && n == patchName) {
          patchUrl = url;
          patchSize = sz;
        } else if (n == 'drom.sha256') {
          shaUrl = url;
        }
      }

      if (remote > build && apk != null) {
        available = UpdateInfo(
          build: remote,
          name: (data['name'] ?? tag).toString(),
          notes: (data['body'] ?? '').toString().trim(),
          apkUrl: apk,
          size: size,
          patchUrl: patchUrl,
          patchSize: patchSize,
          shaUrl: shaUrl,
          published:
              DateTime.tryParse((data['published_at'] ?? '').toString())
                  ?.toLocal(),
        );
      } else {
        available = null;
      }
      // a newer build than the downloaded one came out: start over for it
      if (phase == UpdatePhase.ready &&
          available != null &&
          available!.build != _readyBuild) {
        phase = UpdatePhase.idle;
        _apkPath = null;
        autoDownloaded = false;
      }
      checkedOnce = true;
      error = null;
    } on DioException {
      error = 'Could not check for updates';
    } catch (_) {
      error = 'Could not check for updates';
    } finally {
      checking = false;
      notifyListeners();
      // new version found: fetch it quietly in the background
      if (available != null) _maybeAutoDownload(manual: !silent);
    }
  }
}
