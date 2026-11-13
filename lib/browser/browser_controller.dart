import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../download_manager.dart';
import '../hls.dart';
import 'browser_tab.dart';

/// Route name of the browser screen (used to come back to it).
const String kBrowserRoute = 'drom_browser';

class Shortcut {
  final String name;
  final String url;
  const Shortcut(this.name, this.url);
  Map<String, dynamic> toJson() => {'name': name, 'url': url};
  factory Shortcut.fromJson(Map<String, dynamic> j) =>
      Shortcut(j['name'] as String, j['url'] as String);
}

class HistoryEntry {
  final String title;
  final String url;
  final int time; // millisecondsSinceEpoch
  const HistoryEntry(this.title, this.url, this.time);
  Map<String, dynamic> toJson() => {'t': title, 'u': url, 'm': time};
  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
      j['t'] as String, j['u'] as String, (j['m'] as num).toInt());
}

/// Domains / patterns blocked when "Block Ads" is on.
const List<String> _adPatterns = [
  r'.*doubleclick\.net.*',
  r'.*googlesyndication\.com.*',
  r'.*googleadservices\.com.*',
  r'.*adservice\.google\..*',
  r'.*google-analytics\.com.*',
  r'.*googletagmanager\.com.*',
  r'.*adnxs\.com.*',
  r'.*taboola\.com.*',
  r'.*outbrain\.com.*',
  r'.*popads\.net.*',
  r'.*popcash\.net.*',
  r'.*propellerads\.com.*',
  r'.*exoclick\.com.*',
  r'.*adsterra\.com.*',
  r'.*pubmatic\.com.*',
  r'.*criteo\.(com|net).*',
  r'.*amazon-adsystem\.com.*',
  r'.*/ads/.*\.js.*',
];

/// Shortcuts that older versions added by themselves: removed from the start
/// page (only Google stays). Shortcuts the person added are never touched.
const _retiredShortcutUrls = {
  'https://www.wikipedia.org',
  'https://github.com',
  'https://www.reddit.com',
};

List<Shortcut> _withoutRetired(List<Shortcut> l) =>
    l.where((s) => !_retiredShortcutUrls.contains(s.url)).toList();

const List<Shortcut> _defaultShortcuts = [
  Shortcut('Google', 'https://www.google.com'),
];

/// Central state of the browser: tabs, settings, bookmarks and history.
class BrowserController extends ChangeNotifier {
  BrowserController._();
  static final BrowserController instance = BrowserController._();

  final List<BrowserTab> tabs = [];
  /// Addresses of recently closed tabs (newest last) for "Reopen Closed Tab".
  final List<String> closedUrls = [];
  int active = 0;

  bool blockAds = false;
  bool captureMedia = false;
  bool desktopMode = false;
  ThemeMode themeMode = ThemeMode.system;

  List<Shortcut> shortcuts = [];
  List<Shortcut> bookmarks = [];
  List<HistoryEntry> history = [];

  SharedPreferences? _prefs;
  int _idSeed = 0;

  BrowserTab get current {
    // there is always one tab, even if saved tabs could not be read
    if (tabs.isEmpty) {
      tabs.add(BrowserTab(id: _nextId()));
      active = 0;
    }
    return tabs[active.clamp(0, tabs.length - 1)];
  }

  // ---------------------------------------------------------------- init

  /// Pull-to-refresh on the browser start page: re-reads shortcuts and redraws.
  Future<void> refreshHome() async {
    final p = _prefs;
    if (p != null) {
      shortcuts = p.containsKey('b_shortcuts')
          ? _withoutRetired(_readList(p, 'b_shortcuts', Shortcut.fromJson))
          : [..._defaultShortcuts];
    }
    await Future.delayed(const Duration(milliseconds: 400));
    notifyListeners();
  }

  Future<void> init() async {
    final p = _prefs = await SharedPreferences.getInstance();
    blockAds = p.getBool('b_blockAds') ?? false;
    // capturing is on by default now (key renamed so old 'off' is not kept)
    captureMedia = p.getBool('b_capture2') ?? true;
    bubbleX = p.getDouble('b_bx') ?? 1.0;
    bubbleY = p.getDouble('b_by') ?? 0.72;
    desktopMode = p.getBool('b_desktop') ?? false;
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == p.getString('b_theme'),
      orElse: () => ThemeMode.system,
    );

    shortcuts = _withoutRetired(_readList(p, 'b_shortcuts', Shortcut.fromJson));
    if (!p.containsKey('b_shortcuts')) shortcuts = [..._defaultShortcuts];
    bookmarks = _readList(p, 'b_bookmarks', Shortcut.fromJson);
    history = _readList(p, 'b_history', HistoryEntry.fromJson);
    try {
      final raw = p.getString('b_icons');
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          _icons[k] = base64Decode(v as String);
        });
      }
    } catch (_) {}

    // restore tabs
    try {
      final raw = p.getString('b_tabs');
      if (raw != null) {
        for (final e in jsonDecode(raw) as List) {
          final m = e as Map<String, dynamic>;
          final url = (m['url'] as String?) ?? '';
          tabs.add(BrowserTab(
            id: _nextId(),
            url: url.isEmpty ? null : url,
            title: (m['title'] as String?) ?? '',
            showHome: (m['showHome'] as bool?) ?? url.isEmpty,
          ));
        }
        if (tabs.isNotEmpty) {
          active = (p.getInt('b_active') ?? 0).clamp(0, tabs.length - 1);
        }
      }
    } catch (_) {
      tabs.clear();
    }
    if (tabs.isEmpty) {
      tabs.add(BrowserTab(id: _nextId()));
      active = 0;
    }
  }

  List<T> _readList<T>(SharedPreferences p, String key,
      T Function(Map<String, dynamic>) f) {
    try {
      final raw = p.getString(key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => f(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _nextId() => '${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}';

  // --------------------------------------------------------- persistence

  Future<void> save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setBool('b_blockAds', blockAds);
    await p.setBool('b_capture2', captureMedia);
    await p.setBool('b_desktop', desktopMode);
    await p.setString('b_theme', themeMode.name);
    await p.setString(
        'b_shortcuts', jsonEncode(shortcuts.map((e) => e.toJson()).toList()));
    await p.setString(
        'b_bookmarks', jsonEncode(bookmarks.map((e) => e.toJson()).toList()));
    await _saveHistory();
    await _saveIcons();
    await saveTabs();
  }

  Future<void> _saveHistory() async => _prefs?.setString('b_history',
      jsonEncode(history.take(500).map((e) => e.toJson()).toList()));

  Future<void> _saveIcons() async => _prefs?.setString('b_icons',
      jsonEncode(_icons.map((k, v) => MapEntry(k, base64Encode(v)))));

  // A page load touches history and the site icon: write each of them once,
  // a moment later, instead of re-saving everything on every page.
  Timer? _historyTimer;
  Timer? _iconsTimer;

  void _saveHistoryLater() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(seconds: 2), _saveHistory);
  }

  void _saveIconsLater() {
    _iconsTimer?.cancel();
    _iconsTimer = Timer(const Duration(seconds: 3), _saveIcons);
  }

  Future<void> saveTabs() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString('b_tabs', jsonEncode(tabs.map((t) => t.toJson()).toList()));
    await p.setInt('b_active', active);
  }

  // ---------------------------------------------------------------- tabs

  /// True while the browser screen is on the navigation stack.
  bool screenOpen = false;

  BrowserTab newTab({String? url, int? windowId, bool activate = true}) {
    final t = BrowserTab(
      id: _nextId(),
      url: url,
      windowId: windowId,
      showHome: url == null && windowId == null,
    );
    if (url != null) t.wantsWebView = true;
    tabs.add(t);
    if (activate) active = tabs.length - 1;
    saveTabs();
    notifyListeners();
    return t;
  }

  void switchTo(int i) {
    if (i < 0 || i >= tabs.length || i == active) return;
    active = i;
    saveTabs();
    notifyListeners();
  }

  void closeTab(int i) {
    if (i < 0 || i >= tabs.length) return;
    final t = tabs.removeAt(i);
    if (!t.showHome && t.url.startsWith('http')) {
      closedUrls.add(t.url);
      if (closedUrls.length > 10) closedUrls.removeAt(0);
    }
    if (tabs.isEmpty) {
      tabs.add(BrowserTab(id: _nextId()));
      active = 0;
    } else if (i < active) {
      active -= 1;
    } else if (active >= tabs.length) {
      active = tabs.length - 1;
    }
    // dispose after the frame so the WebView widget can be removed first
    WidgetsBinding.instance.addPostFrameCallback((_) => t.dispose());
    saveTabs();
    notifyListeners();
  }

  /// Opens the most recently closed tab again.
  void reopenClosedTab() {
    if (closedUrls.isEmpty) return;
    newTab(url: closedUrls.removeLast());
  }

  void closeTabById(String id) => closeTab(tabs.indexWhere((t) => t.id == id));

  /// The screen showing the WebViews is being destroyed.
  void detachAll() {
    for (final t in tabs) {
      t.detach();
    }
  }

  // ---------------------------------------------------------- navigation

  /// Turns whatever the user typed into a URL or a Google search.
  static String resolveInput(String input) {
    final t = input.trim();
    if (t.isEmpty) return t;
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return t;
    if (lower.startsWith('file://') || lower.startsWith('about:')) return t;
    final looksLikeHost = !t.contains(' ') &&
        (t.contains('.') || lower.startsWith('localhost')) &&
        !t.endsWith('.');
    if (looksLikeHost) {
      // local servers and IP addresses (router pages) are plain http
      final host = t.split(RegExp(r'[/:?#]')).first;
      final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
      return (isIp || lower.startsWith('localhost')) ? 'http://$t' : 'https://$t';
    }
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(t)}';
  }

  Future<void> navigate(String input, {BrowserTab? tab}) async {
    final t = tab ?? current;
    final url = resolveInput(input);
    if (url.isEmpty) return;
    t.error = null;
    t.setShowHome(false);
    final c = t.controller;
    if (c == null) {
      // WebView not created yet: it will be built with this URL
      t.pendingUrl = url;
      t.wantsWebView = true;
      t.setUrl(url);
    } else {
      t.setUrl(url);
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
    notifyListeners();
    saveTabs();
  }

  Future<void> goBack() async {
    final t = current;
    if (t.showHome && t.controller != null) {
      t.setShowHome(false); // return to the page hidden behind the homepage
      return;
    }
    if (await t.controller?.canGoBack() ?? false) {
      await t.controller!.goBack();
    }
  }

  Future<void> goForward() async {
    final t = current;
    if (t.showHome) return;
    if (await t.controller?.canGoForward() ?? false) {
      await t.controller!.goForward();
    }
  }

  void goHome() {
    current.setShowHome(true);
    notifyListeners();
    saveTabs();
  }

  Future<void> reload() async {
    final t = current;
    if (t.showHome) return;
    t.error = null;
    if (t.isLoading) {
      await t.controller?.stopLoading();
    } else {
      await t.controller?.reload();
    }
  }

  Future<void> refreshNavState(BrowserTab t) async {
    final c = t.controller;
    if (c == null) return;
    final b = await c.canGoBack();
    final f = await c.canGoForward();
    if (b != t.canGoBack || f != t.canGoForward) {
      t.update(() {
        t.canGoBack = b;
        t.canGoForward = f;
      });
    }
  }

  // ------------------------------------------------------------ settings

  InAppWebViewSettings webSettings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        useOnDownloadStart: true,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: true,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
        safeBrowsingEnabled: true,
        thirdPartyCookiesEnabled: true,
        domStorageEnabled: true,
        preferredContentMode: desktopMode
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.RECOMMENDED,
        contentBlockers: blockAds
            ? [
                for (final p in _adPatterns)
                  ContentBlocker(
                    trigger: ContentBlockerTrigger(urlFilter: p),
                    action:
                        ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
                  ),
              ]
            : [],
      );

  Future<void> _applySettings({bool reloadPages = false}) async {
    final s = webSettings();
    for (final t in tabs) {
      final c = t.controller;
      if (c == null) continue;
      try {
        await c.setSettings(settings: s);
        if (reloadPages && !t.showHome) await c.reload();
      } catch (_) {}
    }
  }

  Future<void> setBlockAds(bool v) async {
    blockAds = v;
    notifyListeners();
    await _applySettings(reloadPages: true);
    await save();
  }

  Future<void> setDesktopMode(bool v) async {
    desktopMode = v;
    notifyListeners();
    await _applySettings(reloadPages: true);
    await save();
  }

  Future<void> setCaptureMedia(bool v) async {
    captureMedia = v;
    if (!v) {
      for (final t in tabs) {
        t.media.clear();
      }
    }
    notifyListeners();
    await save();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await save();
  }

  // ----------------------------------------------------------- bookmarks

  bool isBookmarked(String url) => bookmarks.any((b) => b.url == url);

  Future<void> toggleBookmark(BrowserTab t) async {
    if (t.url.isEmpty) return;
    if (isBookmarked(t.url)) {
      bookmarks.removeWhere((b) => b.url == t.url);
    } else {
      bookmarks.insert(
          0, Shortcut(t.title.isNotEmpty ? t.title : t.host, t.url));
    }
    notifyListeners();
    await save();
  }

  Future<void> removeBookmark(Shortcut b) async {
    bookmarks.removeWhere((e) => e.url == b.url);
    notifyListeners();
    await save();
  }

  // ------------------------------------------------------------- history

  /// Page icons (favicons) by site, so History can show them later.
  final Map<String, Uint8List> _icons = {};

  Uint8List? iconFor(String url) {
    final h = Uri.tryParse(url)?.host ?? '';
    return _icons[h];
  }

  void rememberIcon(String url, Uint8List? icon) {
    final h = Uri.tryParse(url)?.host ?? '';
    if (h.isEmpty || icon == null || icon.isEmpty || icon.length > 24000) {
      return;
    }
    final old = _icons[h];
    if (old != null && old.length == icon.length) return;
    _icons.remove(h);
    _icons[h] = icon;
    while (_icons.length > 100) {
      _icons.remove(_icons.keys.first);
    }
    notifyListeners();
    _saveIconsLater();
  }

  void addHistory(BrowserTab t) {
    final u = t.url;
    if (u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))) {
      return;
    }
    rememberIcon(u, t.favicon);
    if (history.isNotEmpty && history.first.url == u) return;
    history.insert(
        0,
        HistoryEntry(t.title.isNotEmpty ? t.title : t.host, u,
            DateTime.now().millisecondsSinceEpoch));
    if (history.length > 500) history.removeRange(500, history.length);
    _saveHistoryLater();
  }

  Future<void> removeHistory(Iterable<HistoryEntry> list) async {
    final drop = list.toSet();
    history.removeWhere(drop.contains);
    notifyListeners();
    await save();
  }

  Future<void> clearHistory() async {
    history.clear();
    notifyListeners();
    await save();
  }

  // ----------------------------------------------------------- shortcuts

  Future<void> addShortcut(String name, String url) async {
    final u = resolveInput(url);
    final n = name.trim().isEmpty ? (Uri.tryParse(u)?.host ?? u) : name.trim();
    shortcuts.add(Shortcut(n, u));
    notifyListeners();
    await save();
  }

  Future<void> removeShortcut(Shortcut s) async {
    shortcuts.remove(s);
    notifyListeners();
    await save();
  }

  // -------------------------------------------------------- clear data

  Future<void> clearBrowsingData(
      {bool history = true, bool cache = true, bool cookies = true}) async {
    if (cache) {
      try {
        await InAppWebViewController.clearAllCache();
      } catch (_) {}
    }
    if (cookies) {
      try {
        await CookieManager.instance().deleteAllCookies();
      } catch (_) {}
      try {
        await WebStorageManager.instance().deleteAllData();
      } catch (_) {}
    }
    if (history) this.history.clear();
    notifyListeners();
    await save();
  }

  // -------------------------------------------------------------- media

  static const _audioExt = {'mp3', 'm4a', 'aac', 'ogg', 'wav', 'flac', 'opus'};
  static const _videoExt = {'mp4', 'webm', 'mkv', 'mov', '3gp', 'm4v'};

  static String _extOf(String url) {
    final u = Uri.tryParse(url);
    final last = (u != null && u.pathSegments.isNotEmpty) ? u.pathSegments.last : '';
    return last.contains('.') ? last.split('.').last.toLowerCase() : '';
  }

  /// Direct media files and HLS streams. YouTube and similar are skipped.
  bool isCapturableMedia(String url, {bool fromMediaElement = false}) {
    final u = Uri.tryParse(url);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) {
      return false;
    }
    final h = u.host.toLowerCase();
    if (h.endsWith('googlevideo.com') ||
        h.endsWith('youtube.com') ||
        h.endsWith('youtu.be')) {
      return false;
    }
    final ext = _extOf(url);
    if (ext == 'mpd') return false; // DASH is not supported
    return ext == 'm3u8' ||
        _audioExt.contains(ext) ||
        _videoExt.contains(ext) ||
        fromMediaElement;
  }

  /// Headers a site expects for its media (page as referer, cookies).
  Future<Map<String, String>> pageHeaders(BrowserTab t, String url) async {
    final h = <String, String>{};
    if (t.url.startsWith('http')) h['Referer'] = t.url;
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(url));
      if (cookies.isNotEmpty) {
        h['Cookie'] = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
    } catch (_) {}
    return h;
  }

  /// A media URL was seen on [t]. [element] = 'video' / 'audio' when it comes
  /// from a player on the page; [height] is the picture height if known.
  void addMedia(BrowserTab t, String url,
      {String? element, int height = 0, String label = ''}) {
    if (!captureMedia) return;
    if (!isCapturableMedia(url, fromMediaElement: element != null)) return;
    final ext = _extOf(url);
    final existing = t.media.where((e) => e.url == url).firstOrNull;
    if (existing != null) {
      if (height > 0 && existing.height == 0) {
        existing.height = height;
        t.update(() {});
      }
      return;
    }
    if (ext == 'm3u8') {
      _addHls(t, url);
      return;
    }
    final audio = element == 'audio' || _audioExt.contains(ext);
    t.media.add(MediaEntry(url, audio: audio, height: height, label: label));
    // pages that load many small pieces must not grow the list without end
    if (t.media.length > 80) t.media.removeRange(0, t.media.length - 80);
    t.update(() {});
  }

  Future<void> _addHls(BrowserTab t, String url) async {
    // reserve the URL so it is looked at only once
    final marker = MediaEntry(url, hls: true, live: true);
    t.media.add(marker);
    try {
      final dm = DownloadManager.instance;
      final headers = await pageHeaders(t, url);
      final text = await dm.fetchText(url, headers: headers);
      final base = Uri.parse(url);
      t.media.remove(marker);
      if (isMasterPlaylist(text)) {
        final m = parseMaster(text, base);
        for (final v in m.variants) {
          if (t.media.any((e) => e.url == v.url.toString())) continue;
          t.media.add(MediaEntry(v.url.toString(),
              hls: true,
              height: v.height,
              bandwidth: v.bandwidth,
              separateAudio: v.separateAudio));
        }
        for (final a in m.audios) {
          if (t.media.any((e) => e.url == a.url.toString())) continue;
          t.media.add(MediaEntry(a.url.toString(),
              hls: true, audio: true, label: a.name));
        }
      } else {
        final m = parseMedia(text, base);
        if (m.segments.isEmpty) {
          t.update(() {});
          return;
        }
        t.media.add(MediaEntry(url,
            hls: true,
            seconds: m.seconds,
            encrypted: m.encrypted,
            live: m.live,
            audio: m.init == null &&
                (m.segments.first.path.toLowerCase().endsWith('.aac') ||
                    m.segments.first.path.toLowerCase().endsWith('.mp3'))));
      }
    } catch (_) {
      t.media.remove(marker);
    }
    t.update(() {});
  }

  // --- floating media button: where the user left it (0..1 of the page area)
  double bubbleX = 1.0;
  double bubbleY = 0.72;

  Future<void> setBubble(double x, double y) async {
    bubbleX = x.clamp(0.0, 1.0);
    bubbleY = y.clamp(0.0, 1.0);
    try {
      final p = _prefs;
      await p?.setDouble('b_bx', bubbleX);
      await p?.setDouble('b_by', bubbleY);
    } catch (_) {}
  }
}
