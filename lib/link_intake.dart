import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser/browser_controller.dart';
import 'browser/browser_screen.dart';
import 'browser/download_prompt.dart';
import 'download_manager.dart';
import 'models.dart';
import 'open_file.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Handles links that arrive from outside the app: Android "Share" and
/// links copied to the clipboard. Both end in the normal SDM download prompt,
/// which checks that the link is a real file before anything is downloaded.
class LinkIntake with WidgetsBindingObserver {
  LinkIntake._();
  static final LinkIntake instance = LinkIntake._();

  static const _channel = MethodChannel('drom/share');
  static const _fileExt = {
    'mp4', 'mkv', 'webm', 'avi', 'mov', '3gp', 'mp3', 'm4a', 'aac', 'wav',
    'flac', 'ogg', 'zip', 'rar', '7z', 'tar', 'gz', 'apk', 'pdf', 'iso',
    'exe', 'msi', 'torrent', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'doc',
    'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'epub',
  };

  static const _prefKey = 'last_clipboard_offer';
  String? _lastClipboard;
  bool _loadedLast = false;
  bool _busy = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShared' && call.arguments is String) {
        await handleText(call.arguments as String);
      } else if (call.method == 'onOpen' && call.arguments is String) {
        _openFinished(call.arguments as String);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final open = await _channel.invokeMethod<String>('getInitialOpen');
        if (open != null && open.isNotEmpty) _openFinished(open);
        final initial = await _channel.invokeMethod<String>('getInitialText');
        if (initial != null && initial.isNotEmpty) {
          await handleText(initial);
        } else {
          await _checkClipboard();
        }
      } on MissingPluginException {
        // not running on Android
      } catch (_) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // let the shared-text callback (if any) win first
      Future.delayed(const Duration(milliseconds: 600), _checkClipboard);
    }
  }

  /// Tapped "Download complete" notification: open that file.
  void _openFinished(String id) {
    for (final it in DownloadManager.instance.items) {
      if (it.id == id && it.status == DlStatus.completed) {
        openDownloaded(it.savePath);
        return;
      }
    }
  }

  /// Drops punctuation that belongs to the sentence around a link, not to the
  /// link ("get it at https://x.com/a.zip." must not end in "a.zip.").
  static String _trimLinkEnd(String u) {
    var s = u;
    while (s.isNotEmpty) {
      final c = s[s.length - 1];
      final strayClose = (c == ')' && !s.contains('(')) ||
          (c == ']' && !s.contains('['));
      if ('.,;:!?\''.contains(c) || strayClose) {
        s = s.substring(0, s.length - 1);
      } else {
        break;
      }
    }
    return s;
  }

  static String? extractUrl(String text) {
    final m = RegExp(r'https?://[^\s<>"]+').firstMatch(text);
    if (m != null) return _trimLinkEnd(m.group(0)!);
    // "www.example.com/page" without the https://
    final w = RegExp(r'\bwww\.[^\s<>"]+').firstMatch(text);
    return w == null ? null : 'https://${_trimLinkEnd(w.group(0)!)}';
  }

  static bool looksLikeFile(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return false;
    final last = uri.pathSegments.last;
    if (!last.contains('.')) return false;
    return _fileExt.contains(last.split('.').last.toLowerCase());
  }

  /// A link shared into the app ("Share" -> SDM).
  /// A direct file link goes to the download prompt; any other web page opens
  /// in the SDM browser (files started from that page are caught there).
  Future<void> handleText(String text) async {
    final url = extractUrl(text);
    if (url == null) return;
    if (looksLikeFile(url)) {
      await _offer(url);
    } else {
      _openInBrowser(url);
    }
  }

  /// Opens [url] in a new SDM browser tab and brings the browser forward.
  void _openInBrowser(String url) {
    final nav = rootNavigatorKey.currentState;
    final ctx = rootNavigatorKey.currentContext;
    if (nav == null || ctx == null) return;
    if (isUnsupportedHost(url)) {
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(unsupportedMessage),
      ));
      return;
    }
    final b = BrowserController.instance;
    b.newTab(url: url);
    if (b.screenOpen) {
      // browser is already somewhere in the stack (maybe under Downloads)
      nav.popUntil((r) => r.isFirst || r.settings.name == kBrowserRoute);
    } else {
      nav.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: kBrowserRoute),
        builder: (_) => const BrowserScreen(),
      ));
    }
  }

  /// A copied link: only offered when it clearly points at a file.
  Future<void> _checkClipboard() async {
    try {
      if (!_loadedLast) {
        // remembered across app restarts, so the same copied link is not
        // offered again every time the app opens
        _loadedLast = true;
        final p = await SharedPreferences.getInstance();
        _lastClipboard ??= p.getString(_prefKey);
      }
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim();
      if (text == null || text.isEmpty || text == _lastClipboard) return;
      final url = extractUrl(text);
      if (url == null || !looksLikeFile(url) || isUnsupportedHost(url)) return;
      _lastClipboard = text;
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, text);
      await _offer(url);
    } catch (_) {}
  }

  Future<void> _offer(String url) async {
    if (_busy) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    if (isUnsupportedHost(url)) {
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(unsupportedMessage),
      ));
      return;
    }
    _busy = true;
    try {
      await showDownloadPrompt(ctx, DownloadRequest(url: url));
    } finally {
      _busy = false;
    }
  }
}
