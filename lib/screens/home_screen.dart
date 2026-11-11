
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_share.dart';
import '../browser/download_prompt.dart';
import '../download_manager.dart';
import '../models.dart';
import '../open_file.dart';
import '../theme.dart';
import '../update_ui.dart';
import '../updater.dart';
import '../browser/browser_controller.dart';
import '../browser/browser_screen.dart';
import 'app_settings_screen.dart';
import '../l10n.dart';

enum _Filter { all, active, completed }

class HomeScreen extends StatefulWidget {
  /// true when opened from the browser's "Downloads" menu entry.
  final bool embedded;
  const HomeScreen({super.key, this.embedded = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final dm = DownloadManager.instance;
  _Filter _filter = _Filter.all;
  final Set<String> _sel = {};

  bool get _selecting => _sel.isNotEmpty;

  @override
  void initState() {
    super.initState();
    dm.addListener(_rebuild);
    UpdateChecker.instance.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.embedded) {
        maybeShowWhatsNew(context);
        maybePromptUpdate(context);
      }
    });
  }

  @override
  void dispose() {
    dm.removeListener(_rebuild);
    UpdateChecker.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
    if (!widget.embedded && UpdateChecker.instance.hasUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          maybePromptUpdate(context);
        }
      });
    }
  }

  Future<void> _refresh() async {
    await dm.refresh();
    await UpdateChecker.instance.check(silent: true);
  }

  // ------------------------------------------------------------ actions

  Future<void> _showAddSheet() async {
    final ctrl = TextEditingController();
    // starts empty: the person pastes the link themselves (paste button)
    if (!mounted) return;

    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 420),
        reverseDuration: Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const T('New download',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            T('Paste a direct link to a file',
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: tr('https://example.com/file.zip'),
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  tooltip: tr('Paste'),
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final c = await Clipboard.getData('text/plain');
                    if (c?.text != null) ctrl.text = c!.text!.trim();
                  },
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                icon: const Icon(Icons.download_rounded),
                label: const T('Start download'),
              ),
            ),
          ],
        ),
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    await _add(url);
  }

  /// A pasted link goes through the same download popup as the browser:
  /// details, file name and save folder are shown before anything starts.
  Future<void> _add(String url) async {
    final u = url.trim();
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(tr('Enter a valid http/https link')),
        ),
      );
      return;
    }
    if (!mounted) return;
    await showDownloadPrompt(context, DownloadRequest(url: u));
  }

  // ------------------------------------------------------- selection

  void _toggle(DownloadItem d) {
    setState(() {
      if (!_sel.remove(d.id)) _sel.add(d.id);
    });
  }

  void _selectAll() {
    setState(() {
      final ids = _visible.map((e) => e.id).toSet();
      if (_sel.containsAll(ids)) {
        _sel.clear();
      } else {
        _sel.addAll(ids);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final chosen = dm.items.where((e) => _sel.contains(e.id)).toList();
    if (chosen.isEmpty) return;
    var withFiles = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(L10n.instance.isBn
              ? '${chosen.length} টি ডাউনলোড মুছবেন?'
              : 'Delete ${chosen.length} download${chosen.length == 1 ? '' : 's'}?'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: withFiles,
            onChanged: (v) => setD(() => withFiles = v ?? false),
            title: const T('Also delete the files from the phone'),
          ),
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
      ),
    );
    if (ok != true) return;
    setState(_sel.clear);
    await dm.removeMany(chosen, deleteFiles: withFiles);
  }

  Future<void> _openBrowser() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: kBrowserRoute),
        builder: (_) => const BrowserScreen(),
      ),
    );
  }

  Future<void> _confirmRemove(DownloadItem d) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const T('Redownload'),
              onTap: () => Navigator.pop(ctx, 'redo'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const T('Copy link'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_remove_rounded),
              title: const T('Remove from list'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error),
              title: T('Delete file too',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: d.url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: T('Link copied')));
      }
    } else if (choice == 'redo') {
      await _redownload(d);
    } else if (choice == 'remove') {
      await dm.remove(d);
    } else if (choice == 'delete') {
      await dm.remove(d, deleteFile: true);
    }
  }

  /// Opens a finished file; says so when it was deleted or moved.
  Future<void> _openFile(DownloadItem d) => openDownloaded(d.savePath);

  Future<void> _redownload(DownloadItem d) async {
    if (d.downloaded > 0 || d.status == DlStatus.completed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const T('Redownload this file?'),
          content: const T(
              'The partial or finished file will be deleted and downloaded again.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const T('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const T('Redownload')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await dm.redownload(d);
  }

  // ------------------------------------------------------------ app menu

  Widget _appMenu() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    PopupMenuItem<String> entry(String value, IconData icon, String label,
        {IconData? trailing, String? note}) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(tr(label))),
            if (note != null)
              Text(note,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline)),
            if (trailing != null) Icon(trailing, size: 22),
          ],
        ),
      );
    }

    final hasUpdate = UpdateChecker.instance.hasUpdate;
    return PopupMenuButton<String>(
      tooltip: tr('More'),
      // a small dot shows when a new version is available
      icon: Badge(
        isLabelVisible: hasUpdate,
        smallSize: 9,
        child: const Icon(Icons.more_vert_rounded),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: _onMenu,
      itemBuilder: (_) => [
        entry('wifi', Icons.wifi_rounded, 'Wi-Fi only',
            trailing: dm.wifiOnly
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded),
        entry('theme', dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            dark ? 'Light mode' : 'Night mode'),
        entry('lang', Icons.language_rounded, 'Language',
            note: L10n.instance.isBn ? 'বাংলা' : 'English'),
        const PopupMenuDivider(),
        entry('share', Icons.share_rounded, 'Share app'),
        entry('settings', Icons.settings_outlined, 'Settings'),
        entry('about', Icons.info_outline_rounded, 'About',
            note: hasUpdate ? tr('New update') : null),
        entry('exit', Icons.exit_to_app_rounded, 'Exit'),
      ],
    );
  }

  Future<void> _onMenu(String v) async {
    switch (v) {
      case 'wifi':
        await dm.setWifiOnly(!dm.wifiOnly);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content:
              Text(tr(dm.wifiOnly ? 'Wi-Fi only is on' : 'Wi-Fi only is off')),
        ));
        break;
      case 'theme':
        final dark = Theme.of(context).brightness == Brightness.dark;
        await BrowserController.instance
            .setThemeMode(dark ? ThemeMode.light : ThemeMode.dark);
        break;
      case 'lang':
        await showLanguageDialog(context);
        break;
      case 'share':
        await shareApp();
        break;
      case 'settings':
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
        );
        break;
      case 'about':
        showAboutDrom(context);
        break;
      case 'exit':
        await SystemNavigator.pop();
        break;
    }
  }

  // -------------------------------------------------------------- build

  List<DownloadItem> get _visible {
    switch (_filter) {
      case _Filter.active:
        return dm.items
            .where((e) => e.status != DlStatus.completed)
            .toList();
      case _Filter.completed:
        return dm.items
            .where((e) => e.status == DlStatus.completed)
            .toList();
      case _Filter.all:
        return dm.items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    _sel.removeWhere((id) => !dm.items.any((e) => e.id == id));
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_sel.clear);
      },
      child: Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(_sel.clear),
              ),
              title: Text(L10n.instance.isBn
                  ? '${_sel.length} টি বাছাই'
                  : '${_sel.length} selected'),
              actions: [
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
                const SizedBox(width: 4),
              ],
            )
          : AppBar(
        title: Text(widget.embedded ? tr('Downloads') : 'SDM'),
        actions: [
          // Browser icon and the three-dot menu are always there.
          IconButton.filledTonal(
            tooltip: tr('Browser'),
            icon: const Icon(Icons.public_rounded),
            // opened from the browser's Downloads entry: go back to it
            onPressed:
                widget.embedded ? () => Navigator.pop(context) : _openBrowser,
          ),
          _appMenu(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const UpdateBanner(),
          _summary(),
          _filters(),
          Expanded(
            // Pull down to refresh, like Chrome.
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: items.isEmpty
                  ? LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: box.maxHeight,
                          child: _empty(),
                        ),
                      ),
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _tile(items[i]),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton:
          _selecting ? null : _AddLinkButton(onTap: _showAddSheet),
    ));
  }

  Widget _summary() {
    final cs = Theme.of(context).colorScheme;
    final active =
        dm.items.where((e) => e.status == DlStatus.downloading).toList();
    final speed = active.fold<double>(0, (a, b) => a + b.speed);
    final done =
        dm.items.where((e) => e.status == DlStatus.completed).length;

    // on/off switch: shown while there is something running or paused
    final showSwitch = dm.hasUnfinished;
    final on = dm.anyRunning;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [cs.primary, Color.lerp(cs.primary, Colors.indigo, 0.55)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    T('Current speed',
                        style: TextStyle(
                            color: cs.onPrimary.withValues(alpha: 0.8),
                            fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('${formatBytes(speed)}/s',
                        style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                  ],
                ),
              ),
              _stat(cs, '${active.length}', 'Active'),
              const SizedBox(width: 20),
              _stat(cs, '$done', 'Done'),
            ],
          ),
          if (showSwitch) ...[
            const SizedBox(height: 6),
            Divider(height: 1, color: cs.onPrimary.withValues(alpha: 0.25)),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(on ? Icons.downloading_rounded : Icons.pause_circle_outline,
                    size: 20, color: cs.onPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr(on ? 'Downloads on' : 'Downloads off'),
                      style: TextStyle(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
                SizedBox(
                  height: 34,
                  child: FittedBox(
                    child: Switch(
                      value: on,
                      onChanged: dm.setDownloadsOn,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeThumbColor: cs.primary,
                      activeTrackColor: cs.onPrimary,
                      inactiveThumbColor: cs.onPrimary,
                      inactiveTrackColor: cs.onPrimary.withValues(alpha: 0.3),
                      trackOutlineColor:
                          WidgetStateProperty.all(Colors.transparent),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(ColorScheme cs, String value, String label) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: cs.onPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          Text(tr(label),
              style: TextStyle(
                  color: cs.onPrimary.withValues(alpha: 0.8), fontSize: 12)),
        ],
      );

  Widget _filters() {
    Widget chip(String label, _Filter f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(tr(label)),
            selected: _filter == f,
            showCheckmark: false,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            onSelected: (_) => setState(() => _filter = f),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          chip('All', _Filter.all),
          chip('Active', _Filter.active),
          chip('Completed', _Filter.completed),
        ],
      ),
    );
  }

  Widget _empty() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_download_outlined,
                  size: 44, color: cs.primary),
            ),
            const SizedBox(height: 18),
            const T('No downloads here',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              tr('Tap "Add link" to paste a file URL,\nor use the browser to find files.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(DownloadItem d) {
    final cs = Theme.of(context).colorScheme;
    final kind = FileKind.of(d.fileName);
    final done = d.status == DlStatus.completed;
    final running = d.status == DlStatus.downloading;
    final failed = d.status == DlStatus.failed;

    // left side under the bar: "15.3 MB of 6.0 GB"
    final sizeText = d.total > 0
        ? trOf(formatBytes(d.downloaded), formatBytes(d.total))
        : formatBytes(d.downloaded);
    // right side under the bar: "42%"
    final percent =
        d.total > 0 ? '${(d.progress * 100).toStringAsFixed(0)}%' : '…';

    String status;
    Color statusColor = cs.onSurfaceVariant;
    if (done) {
      status =
          '${tr('Completed')} · ${formatBytes(d.total > 0 ? d.total : d.downloaded)}';
      statusColor = const Color(0xFF16A34A);
    } else if (failed) {
      status = tr(d.error ?? 'Failed');
      statusColor = cs.error;
    } else if (d.status == DlStatus.paused || d.status == DlStatus.queued) {
      status = tr(dm.waitReason(d) ?? 'Paused');
    } else {
      status = '${formatBytes(d.speed)}/s · ${formatEta(d)}';
    }

    final nameStyle = const TextStyle(
        fontWeight: FontWeight.w700, fontSize: 16.5, height: 1.25);

    final selected = _sel.contains(d.id);
    return Card(
      margin: EdgeInsets.zero,
      color: selected ? cs.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _selecting
            ? () => _toggle(d)
            : (done ? () => _openFile(d) : null),
        // long-press selects; tap more to select any number, delete together
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _toggle(d);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kind.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: selected
                        ? Icon(Icons.check_circle_rounded,
                            color: cs.primary, size: 26)
                        : Icon(kind.icon, color: kind.color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  // the full file name, up to three lines
                  Expanded(
                    child: done
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.fileName,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: nameStyle),
                              const SizedBox(height: 2),
                              Text(status,
                                  style: TextStyle(
                                      fontSize: 13, color: statusColor)),
                            ],
                          )
                        : Text(d.fileName,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle),
                  ),
                  if (_selecting)
                    Checkbox(value: selected, onChanged: (_) => _toggle(d))
                  else if (done)
                    IconButton(
                      tooltip: tr('Open'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.open_in_new_rounded),
                      onPressed: () => _openFile(d),
                    )
                  else if (running)
                    IconButton.filledTonal(
                      tooltip: tr('Pause'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.pause_rounded),
                      onPressed: () => dm.pause(d),
                    )
                  else
                    IconButton.filledTonal(
                      tooltip: failed ? tr('Retry') : tr('Resume'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(failed
                          ? Icons.refresh_rounded
                          : Icons.play_arrow_rounded),
                      onPressed: () => dm.start(d),
                    ),
                  if (!_selecting)
                    IconButton(
                      tooltip: tr('More'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.more_vert_rounded),
                      onPressed: () => _confirmRemove(d),
                    ),
                ],
              ),
              if (!done) ...[
                const SizedBox(height: 10),
                // thin progress line
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: d.total > 0 ? d.progress : (running ? null : 0),
                      color: failed ? cs.error : kind.color,
                      backgroundColor: kind.color.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                // MB on the left, percent on the right
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(sizeText,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text(percent,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: failed ? cs.error : kind.color)),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                // status / speed + ETA on the left, note on the right
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12.5, color: statusColor)),
                      ),
                      if (!d.rangeSupported && d.total > 0)
                        T('Single stream · no resume',
                            style:
                                TextStyle(fontSize: 11, color: cs.outline)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Add link" button: bounces and the + turns into a × while the sheet is open.
class _AddLinkButton extends StatefulWidget {
  final Future<void> Function() onTap;
  const _AddLinkButton({required this.onTap});

  @override
  State<_AddLinkButton> createState() => _AddLinkButtonState();
}

class _AddLinkButtonState extends State<_AddLinkButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 260));

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.86), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.86, end: 1.06), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0), weight: 30),
  ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  late final Animation<double> _turn = Tween<double>(begin: 0, end: 0.125)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));

  bool _opening = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (_opening) return;
    _opening = true;
    HapticFeedback.lightImpact();
    _c.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 220));
    await widget.onTap();
    if (mounted) await _c.reverse();
    _opening = false;
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FloatingActionButton.extended(
        onPressed: _tap,
        icon: RotationTransition(
            turns: _turn, child: const Icon(Icons.add_rounded)),
        label: const T('Add link',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
