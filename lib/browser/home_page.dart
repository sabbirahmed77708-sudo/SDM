import 'package:flutter/material.dart';

import 'browser_controller.dart';
import '../l10n.dart';

/// Browser start page: wordmark, search field and editable shortcuts.
class HomePage extends StatefulWidget {
  final BrowserController browser;
  const HomePage({super.key, required this.browser});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ctrl = TextEditingController();

  BrowserController get b => widget.browser;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _search() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    b.navigate(t);
    _ctrl.clear();
  }

  Future<void> _addShortcut() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const T('Add shortcut'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(hintText: tr('Name')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(hintText: tr('Website address')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const T('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const T('Add')),
        ],
      ),
    );
    if (ok == true && url.text.trim().isNotEmpty) {
      await b.addShortcut(name.text, url.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        // Pull down to refresh, like Chrome.
        child: RefreshIndicator(
          onRefresh: b.refreshHome,
          child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 40),
          child: ListenableBuilder(
            listenable: b,
            builder: (context, _) => Column(
              children: [
                _wordmark(cs),
                const SizedBox(height: 6),
                T('Fast. Private. Yours.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1B222C) : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: isDark
                            ? const Color(0xFF2B3440)
                            : const Color(0xFFE1E6EF)),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 16,
                                offset: const Offset(0, 6)),
                          ],
                  ),
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.search,
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: tr('Search or type a URL'),
                      filled: false,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: tr('Search'),
                        icon: Icon(Icons.arrow_forward_rounded,
                            color: cs.primary),
                        onPressed: _search,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final s in b.shortcuts) _shortcut(cs, s),
                    _addTile(cs),
                  ],
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _wordmark(ColorScheme cs) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
    ];
    const letters = ['S', 'D', 'M'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < letters.length; i++)
          Text(letters[i],
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: colors[i],
              )),
      ],
    );
  }

  Widget _shortcut(ColorScheme cs, Shortcut s) {
    final letter = s.name.isNotEmpty ? s.name[0].toUpperCase() : '?';
    final color = Colors.primaries[s.name.hashCode.abs() % Colors.primaries.length];
    return SizedBox(
      width: 72,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => b.navigate(s.url),
        onLongPress: () async {
          final del = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('${tr('Remove')} "${s.name}"?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const T('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const T('Remove')),
              ],
            ),
          );
          if (del == true) await b.removeShortcut(s);
        },
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // white tile so every site logo is clearly visible
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE1E6EF)),
              ),
              child: _logo(s, letter, color),
            ),
            const SizedBox(height: 6),
            Text(s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// The site's own logo; the first letter shows while it loads or if it fails.
  Widget _logo(Shortcut s, String letter, MaterialColor color) {
    final host = Uri.tryParse(s.url.contains('://') ? s.url : 'https://${s.url}')
            ?.host ??
        '';
    final fallback = Text(letter,
        style: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700, color: color.shade700));
    if (host.isEmpty) return fallback;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$host&sz=128',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Center(child: fallback),
        loadingBuilder: (_, child, p) =>
            p == null ? child : Center(child: fallback),
      ),
    );
  }

  Widget _addTile(ColorScheme cs) => SizedBox(
        width: 72,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _addShortcut,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.add_rounded, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              const T('Add shortcut',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
}
