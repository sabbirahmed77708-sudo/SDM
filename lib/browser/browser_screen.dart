import 'package:flutter/material.dart';

import '../screens/app_settings_screen.dart';
import '../screens/home_screen.dart';
import 'browser_controller.dart';
import 'browser_menu.dart';
import 'browser_tab.dart';
import 'download_prompt.dart';
import 'media_ui.dart';
import 'sheets.dart';
import 'tab_view.dart';
import 'tabs_drawer.dart';
import '../download_manager.dart';
import '../l10n.dart';

/// The SDM browser: toolbar, tabs drawer, WebViews, menu and find bar.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final browser = BrowserController.instance;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final _urlCtrl = TextEditingController();
  final _urlFocus = FocusNode();
  bool _editing = false;

  final _findCtrl = TextEditingController();
  final _findFocus = FocusNode();
  bool _findVisible = false;

  bool _promptOpen = false;

  @override
  void initState() {
    super.initState();
    browser.screenOpen = true;
    DownloadManager.instance.setBrowserOpen(true);
    _urlFocus.addListener(() {
      if (!_urlFocus.hasFocus && _editing && mounted) {
        setState(() => _editing = false);
      }
    });
  }

  @override
  void dispose() {
    browser.screenOpen = false;
    DownloadManager.instance.setBrowserOpen(false);
    browser.detachAll(); // WebViews die with this screen
    _urlCtrl.dispose();
    _urlFocus.dispose();
    _findCtrl.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ actions

  Future<void> _handleDownload(DownloadRequest r) async {
    if (_promptOpen || !mounted) return;
    _promptOpen = true;
    try {
      await showDownloadPrompt(context, r);
    } finally {
      _promptOpen = false;
    }
  }

  void _openDownloads() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const HomeScreen(embedded: true)));
  }

  void _startEditing() {
    final t = browser.current;
    setState(() {
      _editing = true;
      _urlCtrl.text = t.showHome ? '' : t.url;
      _urlCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _urlCtrl.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _urlFocus.requestFocus();
    });
  }

  void _submitUrl(String v) {
    setState(() => _editing = false);
    _urlFocus.unfocus();
    browser.navigate(v);
  }

  void _openFind() {
    setState(() => _findVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  }

  void _closeFind() {
    browser.current.findController?.clearMatches();
    setState(() {
      _findVisible = false;
      _findCtrl.clear();
    });
  }

  Future<void> _onBack() async {
    if (_findVisible) {
      _closeFind();
      return;
    }
    if (_editing) {
      _urlFocus.unfocus();
      setState(() => _editing = false);
      return;
    }
    final t = browser.current;
    if (t.showHome && t.controller != null) {
      t.setShowHome(false); // back to the page hidden behind the homepage
      return;
    }
    if (!t.showHome) {
      if (await (t.controller?.canGoBack() ?? Future.value(false))) {
        await t.controller!.goBack();
        return;
      }
      if (browser.tabs.length > 1) {
        browser.closeTab(browser.active);
      } else {
        browser.goHome();
      }
      return;
    }
    if (browser.tabs.length > 1) {
      browser.closeTab(browser.active);
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  void _showMenu() {
    showBrowserMenu(
      context,
      browser,
      MenuActions(
        onDownloads: _openDownloads,
        onReturn: () => Navigator.pop(context),
        onFind: () {
          if (browser.current.showHome) return;
          _openFind();
        },
        onResources: () =>
            showResourcesSheet(context, browser.current, _handleDownload),
        onHistory: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => HistoryScreen(browser: browser))),
        onSettings: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => BrowserSettingsScreen(browser: browser))),
        onClearData: () => confirmClearData(context, browser),
        onAbout: () => showAboutDrom(context),
      ),
    );
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      // Outer builder follows tab list / active index changes; the inner one
      // follows live changes of the active tab (title, URL, loading ...).
      child: ListenableBuilder(
        listenable: browser,
        builder: (context, _) => ListenableBuilder(
          listenable: browser.current,
          builder: (context, _) => _scaffold(context),
        ),
      ),
    );
  }

  Widget _scaffold(BuildContext context) {
    final t = browser.current;
    final cs = Theme.of(context).colorScheme;
    final showMedia =
        browser.captureMedia && !t.showHome && t.media.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      drawer: TabsDrawer(
        browser: browser,
        onClose: () => _scaffoldKey.currentState?.closeDrawer(),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 60,
        titleSpacing: 0,
        leadingWidth: 56,
        leading: Center(child: _tabCounter(cs)),
        title: _urlBar(t, cs),
        actions: [
          // the SDM logo: back to the download manager (SDM home)
          IconButton(
            tooltip: tr('Return to SDM'),
            icon: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/icon/logo.png',
                  width: 28, height: 28, filterQuality: FilterQuality.high),
            ),
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
          ),
          IconButton(
            tooltip: tr('Menu'),
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: _showMenu,
          ),
          const SizedBox(width: 2),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: (t.isLoading && !t.showHome)
              ? LinearProgressIndicator(
                  value: t.progress > 0 ? t.progress / 100 : null,
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                )
              : const SizedBox(height: 3),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: browser.active,
                  children: [
                    for (final tab in browser.tabs)
                      TabView(
                        key: ValueKey('tab_${tab.id}'),
                        tab: tab,
                        browser: browser,
                        onDownload: _handleDownload,
                      ),
                  ],
                ),
              ),
              if (_findVisible) _findBar(t, cs),
            ],
          ),
          if (showMedia)
            Positioned.fill(
              // keep clear of the find bar when it is open
              bottom: _findVisible ? 64 : 0,
              child: MediaBubble(
                key: ValueKey('bubble_${t.id}'),
                browser: browser,
                tab: t,
                onDownload: _handleDownload,
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabCounter(ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        FocusScope.of(context).unfocus();
        _scaffoldKey.currentState?.openDrawer();
      },
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.onSurface, width: 1.8),
        ),
        child: Text('${browser.tabs.length}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ),
    );
  }

  Widget _urlBar(BrowserTab t, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onHome = t.showHome || t.url.isEmpty;

    Widget leading;
    if (onHome) {
      leading = Icon(Icons.search_rounded, size: 20, color: cs.outline);
    } else if (t.isSecure) {
      leading = const Icon(Icons.lock_rounded,
          size: 18, color: Color(0xFF16A34A));
    } else if (t.isHttp) {
      leading = const Icon(Icons.lock_open_rounded,
          size: 18, color: Color(0xFFF59E0B));
    } else {
      leading = Icon(Icons.info_outline_rounded, size: 18, color: cs.outline);
    }

    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B222C) : const Color(0xFFE9EDF5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(
            child: _editing
                ? TextField(
                    controller: _urlCtrl,
                    focusNode: _urlFocus,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: _submitUrl,
                    style: const TextStyle(fontSize: 14.5),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      hintText: tr('Search or type a URL'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _startEditing,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        onHome
                            ? 'Search or type a URL'
                            : (t.host.isNotEmpty ? t.host : t.url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            color: onHome ? cs.outline : cs.onSurface),
                      ),
                    ),
                  ),
          ),
          if (_editing && _urlCtrl.text.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(_urlCtrl.clear),
            )
          else
            IconButton(
              tooltip: t.isLoading ? tr('Stop') : tr('Refresh'),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                  t.isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                  size: 20),
              onPressed: onHome ? null : () => browser.reload(),
            ),
        ],
      ),
    );
  }

  Widget _findBar(BrowserTab t, ColorScheme cs) {
    final has = _findCtrl.text.isNotEmpty;
    return Material(
      color: Theme.of(context).cardTheme.color ?? cs.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findCtrl,
                  focusNode: _findFocus,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) {
                    setState(() {});
                    if (v.isEmpty) {
                      t.findController?.clearMatches();
                    } else {
                      t.findController?.findAll(find: v);
                    }
                  },
                  onSubmitted: (_) => t.findController?.findNext(forward: true),
                  decoration: InputDecoration(
                    hintText: tr('Find in page'),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                has
                    ? (t.findTotal == 0
                        ? '0/0'
                        : '${t.findActive + 1}/${t.findTotal}')
                    : '',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              IconButton(
                tooltip: tr('Previous'),
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                onPressed: has
                    ? () => t.findController?.findNext(forward: false)
                    : null,
              ),
              IconButton(
                tooltip: tr('Next'),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                onPressed: has
                    ? () => t.findController?.findNext(forward: true)
                    : null,
              ),
              IconButton(
                tooltip: tr('Close'),
                icon: const Icon(Icons.close_rounded),
                onPressed: _closeFind,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
