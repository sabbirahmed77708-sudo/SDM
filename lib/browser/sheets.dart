import '../pull_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'browser_controller.dart';
import 'browser_screen.dart';
import 'browser_tab.dart';
import 'download_prompt.dart';
import '../l10n.dart';

/// Lists the resources the current page requested.
Future<void> showResourcesSheet(
  BuildContext context,
  BrowserTab tab,
  void Function(DownloadRequest) onDownload,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _UrlListSheet(
      title: 'Page resources',
      emptyText: 'No resources were recorded for this page yet.',
      entries: [for (final r in tab.resources.reversed) (r.url, r.type)],
      onDownload: (u) {
        Navigator.pop(ctx);
        onDownload(DownloadRequest(url: u, referer: tab.url));
      },
    ),
  );
}

/// Lists direct audio/video files found on the page ("Capture Audio/Video").
class _UrlListSheet extends StatefulWidget {
  final String title;
  final String emptyText;
  final List<(String, String)> entries;
  final void Function(String url) onDownload;

  const _UrlListSheet({
    required this.title,
    required this.emptyText,
    required this.entries,
    required this.onDownload,
  });

  @override
  State<_UrlListSheet> createState() => _UrlListSheetState();
}

class _UrlListSheetState extends State<_UrlListSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = widget.entries
        .where((e) => _q.isEmpty || e.$1.toLowerCase().contains(_q))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              Expanded(
                child: Text('${tr(widget.title)} (${widget.entries.length})',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          if (widget.entries.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v.toLowerCase()),
                decoration: InputDecoration(
                  hintText: tr('Filter'),
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(tr(widget.emptyText),
                        style: TextStyle(color: cs.outline)))
                : PullRefresh(child: ListView.separated(physics: kPullPhysics, 
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final (url, type) = list[i];
                      return ListTile(
                        dense: true,
                        title: Text(url,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(type),
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: T('Link copied')));
                        },
                        trailing: IconButton(
                          tooltip: tr('Download with SDM'),
                          icon: const Icon(Icons.download_rounded),
                          onPressed: () => widget.onDownload(url),
                        ),
                      );
                    },
                  )),
          ),
        ],
      ),
    );
  }
}

/// Small site icon: the saved page icon, else a letter.
class SiteIcon extends StatelessWidget {
  final String url;
  final double size;
  const SiteIcon({super.key, required this.url, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final host = (Uri.tryParse(url)?.host ?? '').replaceFirst('www.', '');
    final bytes = BrowserController.instance.iconFor(url);
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: host.isEmpty
          ? Icon(Icons.public_rounded, size: size * 0.55, color: cs.primary)
          : Text(host[0].toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.45,
                  color: cs.onPrimaryContainer)),
    );
    Widget img;
    if (bytes != null) {
      img = Image.memory(bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => letter);
    } else if (host.isNotEmpty) {
      // not saved yet: try the site's own icon, fall back to the letter
      img = Image.network('https://$host/favicon.ico',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => letter);
    } else {
      img = letter;
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(size / 4), child: img),
    );
  }
}

class _Row {
  final String title;
  final String url;
  final Object key;
  final String? sub;
  const _Row(this.title, this.url, this.key, {this.sub});
}

/// Browsing history + bookmarks. Long-press selects; select as many as you
/// like and delete them together.
class HistoryScreen extends StatefulWidget {
  final BrowserController browser;

  /// Opened from the main home page: open the tapped page in the browser.
  final bool fromHome;
  const HistoryScreen({super.key, required this.browser, this.fromHome = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging && _sel.isNotEmpty) setState(_sel.clear);
    });
  final Set<Object> _sel = {};

  BrowserController get browser => widget.browser;
  bool get _selecting => _sel.isNotEmpty;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<_Row> get _history => [
        for (final h in browser.history)
          _Row(h.title, h.url, h, sub: _when(h.time)),
      ];
  List<_Row> get _bookmarks => [
        for (final b in browser.bookmarks) _Row(b.name, b.url, b),
      ];

  String _when(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final today = t.year == now.year && t.month == now.month && t.day == now.day;
    final hm = '${two(t.hour)}:${two(t.minute)}';
    return today ? hm : '${t.day}/${t.month}/${t.year} $hm';
  }

  List<_Row> get _current => _tabs.index == 0 ? _history : _bookmarks;

  void _toggle(_Row r) {
    setState(() {
      if (!_sel.remove(r.key)) _sel.add(r.key);
    });
  }

  void _selectAll() {
    final keys = _current.map((e) => e.key).toSet();
    setState(() {
      if (_sel.containsAll(keys)) {
        _sel.clear();
      } else {
        _sel.addAll(keys);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final n = _sel.length;
    final isHistory = _tabs.index == 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.instance.isBn
            ? '$n টি মুছবেন?'
            : 'Delete $n item${n == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const T('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const T('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final keys = _sel.toList();
    setState(_sel.clear);
    if (isHistory) {
      await browser.removeHistory(keys.whereType<HistoryEntry>());
    } else {
      for (final b in keys.whereType<Shortcut>()) {
        await browser.removeBookmark(b);
      }
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const T('Clear history?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const T('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const T('Clear')),
        ],
      ),
    );
    if (ok == true) await browser.clearHistory();
  }

  void _open(String url) {
    browser.navigate(url);
    if (widget.fromHome) {
      Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute(builder: (_) => const BrowserScreen()),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_sel.clear);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selecting
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(_sel.clear),
                )
              : null,
          title: Text(_selecting
              ? (L10n.instance.isBn
                  ? '${_sel.length} টি বাছাই'
                  : '${_sel.length} selected')
              : tr('History')),
          actions: _selecting
              ? [
                  IconButton(
                    tooltip: tr('Select all'),
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: _selectAll,
                  ),
                  IconButton(
                    tooltip: tr('Delete'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _deleteSelected,
                  ),
                ]
              : [
                  IconButton(
                    tooltip: tr('Clear history'),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: _clearAll,
                  ),
                ],
          bottom: TabBar(
            controller: _tabs,
            tabs: [Tab(text: tr('History')), Tab(text: tr('Bookmarks'))],
          ),
        ),
        body: ListenableBuilder(
          listenable: browser,
          builder: (context, _) => TabBarView(controller: _tabs, children: [
            _list(context, _history, 'No history yet'),
            _list(context, _bookmarks, 'No bookmarks yet'),
          ]),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<_Row> items, String empty) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(
          child: Text(tr(empty), style: TextStyle(color: cs.outline)));
    }
    return PullRefresh(child: ListView.separated(physics: kPullPhysics, 
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = items[i];
        final selected = _sel.contains(r.key);
        return ListTile(
          selected: selected,
          selectedTileColor: cs.primaryContainer.withValues(alpha: 0.6),
          leading: selected
              ? Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: cs.primary, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, color: cs.onPrimary),
                )
              : SiteIcon(url: r.url),
          title: Text(r.title.isEmpty ? r.url : r.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(r.sub != null ? '${r.sub} · ${r.url}' : r.url,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: _selecting ? () => _toggle(r) : () => _open(r.url),
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _toggle(r);
          },
        );
      },
    ));
  }
}

/// Browser settings.
class BrowserSettingsScreen extends StatelessWidget {
  final BrowserController browser;
  const BrowserSettingsScreen({super.key, required this.browser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const T('Settings')),
      body: ListenableBuilder(
        listenable: browser,
        builder: (context, _) => PullRefresh(child: ListView(physics: kPullPhysics, 
          children: [
            SwitchListTile(
              title: const T('Block ads'),
              subtitle: const T('Blocks common ad and tracker domains'),
              value: browser.blockAds,
              onChanged: browser.setBlockAds,
            ),
            SwitchListTile(
              title: const T('Desktop mode'),
              subtitle: const T('Request the desktop version of sites'),
              value: browser.desktopMode,
              onChanged: browser.setDesktopMode,
            ),
            SwitchListTile(
              title: const T('Capture audio / video'),
              subtitle:
                  const T('Lists direct media files found on a page'),
              value: browser.captureMedia,
              onChanged: browser.setCaptureMedia,
            ),
            const Divider(),
            ListTile(
              title: const T('Theme'),
              trailing: DropdownButton<ThemeMode>(
                value: browser.themeMode,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                      value: ThemeMode.system, child: T('System')),
                  DropdownMenuItem(value: ThemeMode.light, child: T('Light')),
                  DropdownMenuItem(value: ThemeMode.dark, child: T('Dark')),
                ],
                onChanged: (m) {
                  if (m != null) browser.setThemeMode(m);
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: const T('Clear browsing data'),
              subtitle: const T('History, cache, cookies and site data'),
              onTap: () => confirmClearData(context, browser),
            ),
          ],
        )),
      ),
    );
  }
}

Future<void> confirmClearData(
    BuildContext context, BrowserController browser) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const T('Clear browsing data?'),
      content: Text(
          tr('This removes history, cache, cookies and saved site data. ') +
              tr('You will be signed out of websites.')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const T('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const T('Clear')),
      ],
    ),
  );
  if (ok == true) {
    await browser.clearBrowsingData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('Browsing data cleared')));
    }
  }
}
