import 'package:flutter/material.dart';

import 'browser_controller.dart';
import '../l10n.dart';

class MenuActions {
  final VoidCallback onDownloads;
  final VoidCallback onReturn;
  final VoidCallback onFind;
  final VoidCallback onResources;
  final VoidCallback onHistory;
  final VoidCallback onSettings;
  final VoidCallback onClearData;
  final VoidCallback onAbout;

  const MenuActions({
    required this.onDownloads,
    required this.onReturn,
    required this.onFind,
    required this.onResources,
    required this.onHistory,
    required this.onSettings,
    required this.onClearData,
    required this.onAbout,
  });
}

/// Right-side popup menu anchored under the three-dot button.
Future<void> showBrowserMenu(
  BuildContext context,
  BrowserController b,
  MenuActions a,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Menu'),
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) {
      final top = MediaQuery.of(ctx).padding.top + 56;
      return Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: top, right: 8, left: 8, bottom: 8),
          child: Material(
            color: Theme.of(ctx).cardTheme.color ??
                Theme.of(ctx).colorScheme.surface,
            elevation: 12,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 300,
                maxHeight: MediaQuery.of(ctx).size.height - top - 16,
              ),
              child: _MenuBody(browser: b, actions: a),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

class _MenuBody extends StatelessWidget {
  final BrowserController browser;
  final MenuActions actions;
  const _MenuBody({required this.browser, required this.actions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    void close() => Navigator.pop(context);

    Widget quick(IconData icon, String tip, VoidCallback? onTap,
            {bool highlight = false}) =>
        IconButton(
          tooltip: tr(tip),
          icon: Icon(icon, color: highlight ? cs.primary : null),
          onPressed: onTap,
        );

    Widget item(IconData icon, String label, VoidCallback onTap,
            {bool? checked, bool keepOpen = false}) =>
        InkWell(
          onTap: () {
            if (!keepOpen) close();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 22, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(tr(label), style: const TextStyle(fontSize: 15))),
              if (checked != null)
                Icon(
                  checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: checked ? cs.primary : cs.outline,
                ),
            ]),
          ),
        );

    return ListenableBuilder(
      listenable: Listenable.merge([browser, browser.current]),
      builder: (context, _) {
        final t = browser.current;
        final canBack = t.canGoBack || (t.showHome && t.controller != null);
        final canFwd = t.canGoForward && !t.showHome;
        final bookmarked = browser.isBookmarked(t.url);
        final onPage = !t.showHome && t.url.isNotEmpty;

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    quick(Icons.arrow_back_rounded, 'Back',
                        canBack ? () {
                          close();
                          browser.goBack();
                        } : null),
                    quick(Icons.arrow_forward_rounded, 'Forward',
                        canFwd ? () {
                          close();
                          browser.goForward();
                        } : null),
                    quick(
                        bookmarked
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        'Bookmark',
                        onPage ? () => browser.toggleBookmark(t) : null,
                        highlight: bookmarked),
                    quick(Icons.refresh_rounded, 'Refresh', onPage ? () {
                      close();
                      browser.reload();
                    } : null),
                    quick(Icons.settings_outlined, 'Settings', () {
                      close();
                      actions.onSettings();
                    }),
                  ],
                ),
              ),
              const Divider(height: 1),
              item(Icons.add_box_outlined, 'New Tab', () => browser.newTab()),
              item(Icons.shield_outlined, 'Block Ads',
                  () => browser.setBlockAds(!browser.blockAds),
                  checked: browser.blockAds, keepOpen: true),
              item(Icons.graphic_eq_rounded, 'Capture Audio/Video',
                  () => browser.setCaptureMedia(!browser.captureMedia),
                  checked: browser.captureMedia, keepOpen: true),
              item(Icons.list_alt_rounded, 'View Page Resources',
                  actions.onResources),
              item(Icons.history_rounded, 'History', actions.onHistory),
              item(Icons.find_in_page_outlined, 'Find in Page', actions.onFind),
              item(Icons.desktop_windows_outlined, 'Desktop Mode',
                  () => browser.setDesktopMode(!browser.desktopMode),
                  checked: browser.desktopMode, keepOpen: true),
              item(Icons.delete_outline_rounded, 'Clear Browsing Data',
                  actions.onClearData),
              const Divider(height: 1),
              item(Icons.info_outline_rounded, 'About SDM', actions.onAbout),
            ],
          ),
        );
      },
    );
  }
}
