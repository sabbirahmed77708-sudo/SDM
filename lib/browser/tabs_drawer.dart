import '../pull_refresh.dart';
import 'package:flutter/material.dart';

import 'browser_controller.dart';
import 'browser_tab.dart';
import '../l10n.dart';

/// Left-side navigation panel listing every open tab, live.
class TabsDrawer extends StatefulWidget {
  final BrowserController browser;
  final VoidCallback onClose;
  const TabsDrawer({super.key, required this.browser, required this.onClose});

  @override
  State<TabsDrawer> createState() => _TabsDrawerState();
}

class _TabsDrawerState extends State<TabsDrawer> {
  bool _searching = false;
  String _query = '';

  BrowserController get b => widget.browser;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      width: 330,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: b,
          builder: (context, _) {
            final q = _query.trim().toLowerCase();
            final indices = <int>[
              for (var i = 0; i < b.tabs.length; i++)
                if (q.isEmpty ||
                    b.tabs[i].displayTitle.toLowerCase().contains(q) ||
                    b.tabs[i].url.toLowerCase().contains(q))
                  i,
            ];
            return Column(
              children: [
                _header(cs),
                const Divider(height: 1),
                Expanded(
                  child: indices.isEmpty
                      ? Center(
                          child: T('No matching tabs',
                              style: TextStyle(color: cs.outline)))
                      : PullRefresh(child: ListView.builder(physics: kPullPhysics, 
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          itemCount: indices.length,
                          itemBuilder: (_, k) {
                            final i = indices[k];
                            return _TabTile(
                              key: ValueKey(b.tabs[i].id),
                              tab: b.tabs[i],
                              number: i + 1,
                              active: i == b.active,
                              onTap: () {
                                b.switchTo(i);
                                widget.onClose();
                              },
                              onClose: () => b.closeTab(i),
                            );
                          },
                        )),
                ),
                const Divider(height: 1),
                _bottomBar(cs),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: tr('Search tabs'),
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _searching = false;
              _query = '';
            }),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(children: [
        Icon(Icons.view_list_rounded, color: cs.primary),
        const SizedBox(width: 12),
        const Expanded(
          child: T('Tabs',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: tr('Search tabs'),
          icon: const Icon(Icons.search_rounded),
          onPressed: () => setState(() => _searching = true),
        ),
      ]),
    );
  }

  Widget _bottomBar(ColorScheme cs) {
    // Re-evaluate Back/Forward state whenever the active tab changes.
    return ListenableBuilder(
      listenable: b.current,
      builder: (context, _) {
        final t = b.current;
        final canBack = t.canGoBack || (t.showHome && t.controller != null);
        final canFwd = t.canGoForward && !t.showHome;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _action(Icons.arrow_back_rounded, 'Back',
                  canBack ? () => b.goBack() : null),
              _action(Icons.home_rounded, 'Home', () {
                b.goHome();
                widget.onClose();
              }),
              _action(Icons.arrow_forward_rounded, 'Forward',
                  canFwd ? () => b.goForward() : null),
              _action(Icons.add_rounded, 'New tab', () {
                b.newTab();
                widget.onClose();
              }, filled: true),
            ],
          ),
        );
      },
    );
  }

  Widget _action(IconData icon, String tip, VoidCallback? onTap,
      {bool filled = false}) {
    return filled
        ? IconButton.filled(tooltip: tr(tip), icon: Icon(icon), onPressed: onTap)
        : IconButton(tooltip: tr(tip), icon: Icon(icon), onPressed: onTap);
  }
}

class _TabTile extends StatelessWidget {
  final BrowserTab tab;
  final int number;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabTile({
    super.key,
    required this.tab,
    required this.number,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Each tile follows its own tab, so title / URL / favicon / loading state
    // are always current.
    return ListenableBuilder(
      listenable: tab,
      builder: (context, _) {
        final loading = tab.isLoading;
        final subtitle = tab.url.isEmpty
            ? tr('Homepage')
            : (tab.host.isNotEmpty ? tab.host : tab.url);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer.withValues(alpha: 0.55) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? cs.primary : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 2, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text('$number',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: active ? cs.primary : cs.outline)),
                        ),
                        _favicon(cs),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tab.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                loading
                                    ? '${tr('Loading…')} ${tab.progress}%'
                                    : subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: loading
                                        ? cs.primary
                                        : cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: tr('Close tab'),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                ),
                if (loading)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: tab.progress / 100,
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _favicon(ColorScheme cs) {
    final fav = tab.favicon;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: fav != null && fav.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(fav,
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _letter(cs)),
            )
          : _letter(cs),
    );
  }

  Widget _letter(ColorScheme cs) {
    final src = tab.host.isNotEmpty ? tab.host : '';
    if (src.isEmpty) {
      return Icon(Icons.public_rounded, size: 18, color: cs.outline);
    }
    return Text(src[0].toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary));
  }
}
