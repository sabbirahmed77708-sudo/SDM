import 'pull_refresh.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'l10n.dart';

/// Root of the phone's internal storage.
const String kStorageRoot = '/storage/emulated/0';

/// "/storage/emulated/0/Download/SDM" -> "Internal storage/Download/SDM"
String prettyPath(String p) => p.startsWith(kStorageRoot)
    ? '${tr('Internal storage')}${p.substring(kStorageRoot.length)}'
    : p;

/// Last folder name of [p].
String folderName(String p) {
  final parts = p.split('/').where((e) => e.isNotEmpty).toList();
  if (p == kStorageRoot || parts.isEmpty) return tr('Internal storage');
  return parts.last;
}

/// Lets the person browse the phone's folders and pick one.
/// Returns the chosen folder path, or null when cancelled.
Future<String?> pickFolder(BuildContext context, {String? start}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 380),
      reverseDuration: Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _FolderPicker(start: start),
    ),
  );
}

class _FolderPicker extends StatefulWidget {
  final String? start;
  const _FolderPicker({this.start});

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late String _cwd;
  List<Directory> _dirs = [];
  bool _loading = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    final s = widget.start;
    _cwd = (s != null && s.startsWith(kStorageRoot)) ? s : kStorageRoot;
    _open(_cwd);
  }

  Future<void> _open(String path) async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      var st = await Permission.manageExternalStorage.status;
      if (!st.isGranted) st = await Permission.manageExternalStorage.request();

      // the starting folder may not exist yet: go up to one that does
      var p = path;
      while (p != kStorageRoot && !await Directory(p).exists()) {
        p = Directory(p).parent.path;
      }
      final list = <Directory>[];
      await for (final e in Directory(p).list(followLinks: false)) {
        if (e is Directory) {
          final name = e.path.split('/').last;
          if (!name.startsWith('.')) list.add(e);
        }
      }
      list.sort((a, b) => a.path
          .split('/')
          .last
          .toLowerCase()
          .compareTo(b.path.split('/').last.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _cwd = p;
        _dirs = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dirs = [];
        _loading = false;
        _denied = true;
      });
    }
  }

  void _up() {
    if (_cwd == kStorageRoot) return;
    final parent = Directory(_cwd).parent.path;
    _open(parent.startsWith(kStorageRoot) ? parent : kStorageRoot);
  }

  Future<void> _newFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const T('New folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Folder name')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const T('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const T('Create')),
        ],
      ),
    );
    final clean = (name ?? '')
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim();
    if (clean.isEmpty) return;
    try {
      final d = Directory('$_cwd/$clean');
      await d.create(recursive: true);
      await _open(d.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(tr('Cannot save to this folder. Please choose another one.')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: tr('Back'),
                icon: const Icon(Icons.arrow_upward_rounded),
                onPressed: _cwd == kStorageRoot ? null : _up,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const T('Choose folder',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(prettyPath(_cwd),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('New folder'),
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _denied ? null : _newFolder,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body(cs)),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _denied ? null : () => Navigator.pop(context, _cwd),
                icon: const Icon(Icons.check_rounded),
                label: const T('Select this folder'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 40, color: cs.outline),
              const SizedBox(height: 12),
              const T('Storage permission is needed to browse folders.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: () async {
                  await Permission.manageExternalStorage.request();
                  _open(_cwd);
                },
                child: const T('Allow access'),
              ),
            ],
          ),
        ),
      );
    }
    if (_dirs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded, size: 44, color: cs.outline),
            const SizedBox(height: 8),
            T('No folders here', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    return PullRefresh(onRefresh: () => _open(_cwd), child: ListView.builder(physics: kPullPhysics, 
      itemCount: _dirs.length,
      itemBuilder: (_, i) {
        final d = _dirs[i];
        return ListTile(
          leading: const Icon(Icons.folder_rounded, color: Color(0xFFF59E0B)),
          title: Text(d.path.split('/').last,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(d.path),
        );
      },
    ));
  }
}
