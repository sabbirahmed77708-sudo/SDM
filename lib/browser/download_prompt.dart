import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../download_manager.dart';
import '../folder_picker.dart';
import '../models.dart';
import '../theme.dart';
import '../l10n.dart';

/// A download the browser wants to hand over to SDM.
class DownloadRequest {
  final String url;
  final String? fileName;
  final String? mimeType;
  final int? size;
  final String? userAgent;
  final String? referer;
  const DownloadRequest({
    required this.url,
    this.fileName,
    this.mimeType,
    this.size,
    this.userAgent,
    this.referer,
  });
}

String _guessName(String url) {
  final u = Uri.tryParse(url);
  var n = (u != null && u.pathSegments.isNotEmpty) ? u.pathSegments.last : '';
  try {
    n = Uri.decodeComponent(n);
  } catch (_) {}
  return n.isEmpty ? 'download' : n;
}

bool _looksLikeFileName(String n) =>
    RegExp(r'\.[A-Za-z0-9]{1,5}$').hasMatch(n);

String _typeLabel(String name, String? mime) {
  final e = name.contains('.') ? name.split('.').last.toUpperCase() : '';
  if (e.isNotEmpty && e.length <= 5) return '$e file';
  if (mime != null && mime.isNotEmpty && mime != 'application/octet-stream') {
    return mime;
  }
  return 'File';
}

/// Quick save locations shown as chips in the popup.
const List<(String, String)> _quickFolders = [
  ('SDM folder', ''), // the real path comes from the download manager
  ('Downloads', '$kStorageRoot/Download'),
  ('Movies', '$kStorageRoot/Movies'),
  ('Music', '$kStorageRoot/Music'),
  ('Documents', '$kStorageRoot/Documents'),
];

/// Shows the SDM download popup as a box in the middle of the screen. It
/// floats up with a soft bounce, lists every detail of the file, lets the
/// person rename it and pick where it is saved.
/// Returns true when the download started.
Future<bool> showDownloadPrompt(
    BuildContext context, DownloadRequest req) async {
  // The file check starts BEFORE the popup opens. The popup waits a moment for
  // it (at most 0.9 s), so it opens already complete: real name, size, type.
  // On a slow server it opens anyway and fills in when the answer arrives.
  final pre = _preload(req);
  ProbeResult? ready;
  try {
    ready = await pre.timeout(const Duration(milliseconds: 900));
  } catch (_) {}
  if (!context.mounted) return false;
  // the remembered folder is known without waiting, so the popup opens at once
  // and complete
  final dir = DownloadManager.instance.preferredDirSync;
  // set when the download starts: the popup then flies up to the downloads icon
  var flying = false;
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, __, ___) => _PromptSheet(
        req: req,
        initialDir: dir,
        pre: pre,
        ready: ready,
        onLaunch: () => flying = true),
    // In: rises and grows a little while fading in. Out after "Download":
    // shrinks and flies to the downloads icon (top right). Out after Cancel:
    // just sinks away. Drawn as one cached layer.
    transitionBuilder: (context, anim, _, child) {
      final c = CurvedAnimation(
          parent: anim,
          curve: const Cubic(0.16, 1, 0.3, 1), // fast start, long soft landing
          reverseCurve: Curves.easeInCubic);
      final cached = RepaintBoundary(child: child);
      return AnimatedBuilder(
        animation: c,
        child: cached,
        builder: (ctx, ch) {
          final v = c.value;
          final out = flying && anim.status == AnimationStatus.reverse;
          final size = MediaQuery.sizeOf(ctx);
          final scale = out ? 0.12 + 0.88 * v : 0.88 + 0.12 * v;
          final dx = out ? (1 - v) * size.width * 0.40 : 0.0;
          final dy = out
              ? -(1 - v) * size.height * 0.45
              : (1 - v) * size.height * 0.05;
          final opacity = out ? (v * 1.8).clamp(0.0, 1.0) : v;
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Transform.scale(scale: scale, child: ch),
            ),
          );
        },
      );
    },
  );
  return result == true;
}

Future<Map<String, String>> _buildHeaders(DownloadRequest r) async {
  final h = <String, String>{};
  if (r.userAgent != null && r.userAgent!.isNotEmpty) {
    h['User-Agent'] = r.userAgent!;
  }
  if (r.referer != null && r.referer!.startsWith('http')) {
    h['Referer'] = r.referer!;
  }
  try {
    // never let the cookie lookup hold the popup back
    final cookies = await CookieManager.instance()
        .getCookies(url: WebUri(r.url))
        .timeout(const Duration(milliseconds: 400));
    if (cookies.isNotEmpty) {
      h['Cookie'] = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    }
  } catch (_) {}
  return h;
}

/// Checks the file (name, size, resume support) with the same headers the
/// download will use. Never throws: a failed check is reported as unknown.
Future<ProbeResult> _preload(DownloadRequest r) async {
  try {
    final headers = await _buildHeaders(r);
    return await DownloadManager.instance
        .inspect(r.url, headers: headers)
        .timeout(const Duration(seconds: 12));
  } catch (_) {
    return const ProbeResult(-1, false, null, null);
  }
}

class _PromptSheet extends StatefulWidget {
  final DownloadRequest req;
  final String? initialDir;
  final Future<ProbeResult> pre;
  final ProbeResult? ready; // the check already finished before opening
  final VoidCallback? onLaunch;
  const _PromptSheet(
      {required this.req,
      this.initialDir,
      required this.pre,
      this.ready,
      this.onLaunch});

  @override
  State<_PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<_PromptSheet> {
  late final Future<ProbeResult> _probe;
  late final TextEditingController _nameCtrl;
  bool _nameEdited = false;
  bool _editing = false;
  String? _dir; // base folder (the person's choice, or the default)
  bool _dirManual = false; // folder picked by hand: no automatic type folder

  /// Where the file really goes: the picked folder, or the type folder
  /// (Video, Music ...) inside the default folder.
  String? get _effectiveDir {
    final d = _dir;
    if (d == null) return null;
    if (_dirManual) return d;
    return DownloadManager.instance.sortedDir(d, _nameCtrl.text);
  }

  bool get _autoSorted =>
      !_dirManual && DownloadManager.instance.sortByType && _dir != null;
  ProbeResult? _info; // what the file check found (reused when starting)
  bool _busy = false;
  bool _copied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.req;
    // Same name no matter how the link arrived (browser, paste, share):
    // the file name in the link wins over the browser's own guess
    // (e.g. "main.mkv"); the server's real name replaces both once checked.
    final fromUrl = _guessName(r.url);
    final given = r.fileName ?? '';
    _nameCtrl = TextEditingController(
        text: _looksLikeFileName(fromUrl)
            ? fromUrl
            : (given.isNotEmpty ? given : fromUrl));
    _dir = widget.initialDir;
    if (_dir == null) _initDir();
    final ready = widget.ready;
    if (ready != null) {
      _applyInfo(ready);
      _probe = Future.value(ready);
    } else {
      // slow server: show the popup now, fill in when the check finishes
      _probe = widget.pre.then((info) {
        _applyInfo(info);
        return info;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDir() async {
    final d = await DownloadManager.instance.preferredDir();
    if (mounted) setState(() => _dir = d);
  }

  void _applyInfo(ProbeResult info) {
    _info = info;
    // the server's real file name wins, unless the person already typed one
    final real = info.fileName;
    if (!_nameEdited && real != null && real.isNotEmpty && mounted) {
      _nameCtrl.text = real;
    }
  }

  Future<void> _chooseFolder() async {
    final p = await pickFolder(context, start: _dir);
    if (p != null && mounted) {
      setState(() {
        _dir = p;
        _dirManual = true;
      });
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.req.url));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _start() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a file name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final headers = await _buildHeaders(widget.req);
      final dm = DownloadManager.instance;
      await dm.addUrl(
        widget.req.url,
        headers: headers,
        suggestedName: name,
        dirPath: _effectiveDir,
        probe: _info, // already checked: no second round trip to the server
      );
      // only a folder picked by hand becomes the new default
      if (_dir != null && _dirManual) await dm.setPreferredDir(_dir!);
      if (mounted) {
        widget.onLaunch?.call();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.req;
    return FutureBuilder<ProbeResult>(
      future: _probe,
      initialData: widget.ready,
      builder: (context, snap) {
        final loading =
            widget.ready == null && snap.connectionState != ConnectionState.done;
        final info = snap.data ?? widget.ready;
        final name = _nameCtrl.text;
        final size =
            (r.size != null && r.size! > 0) ? r.size! : (info?.total ?? -1);
        final mime = r.mimeType ?? info?.contentType;
        final kind = FileKind.of(name);
        final ct = (info?.contentType ?? '').toLowerCase();
        final isPage = ct.startsWith('text/html') &&
            !name.toLowerCase().endsWith('.html') &&
            !name.toLowerCase().endsWith('.htm');
        final probeError = snap.hasError ? snap.error.toString() : null;
        final blocked = isPage || probeError != null;
        final host = Uri.tryParse(r.url)?.host ?? r.url;

        final rows = <Widget>[
          _row(cs, Icons.public_rounded, 'Source', host),
          _row(
            cs,
            Icons.bolt_rounded,
            'Download mode',
            info == null
                ? tr('checking…')
                : (info.hls
                    ? tr('Video stream · saved in pieces, resumable')
                    : info.range
                    ? tr('Fast multi-part · resumable')
                    : tr('Single stream · no resume')),
          ),
          _row(
            cs,
            Icons.link_rounded,
            'Link',
            r.url,
            maxLines: 3,
            onTap: _copyLink,
            trailing: Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
              color: _copied ? const Color(0xFF16A34A) : cs.outline,
            ),
          ),
        ];

        return Center(
          child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            elevation: 8,
            backgroundColor: Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Appear(
                      key: const ValueKey('head'),
                      index: 0,
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _BobIcon(color: cs.primary),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: T('Download file',
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          tooltip: tr('Cancel'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context, false),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    _Appear(
                      key: const ValueKey('file'),
                      index: 1,
                      child: _fileCard(cs, kind, name, mime, size, loading),
                    ),
                    const SizedBox(height: 12),
                    _Appear(
                      key: const ValueKey('details'),
                      index: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0)
                              Divider(
                                  height: 1,
                                  indent: 14,
                                  endIndent: 14,
                                  color: cs.outlineVariant),
                            rows[i],
                          ],
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Appear(
                      key: const ValueKey('save'),
                      index: 3,
                      child: _saveSection(cs),
                    ),
                    if (isPage)
                      _note(cs,
                          'This link returns a web page, not a downloadable file.'),
                    if (probeError != null) _note(cs, probeError),
                    if (_error != null) _note(cs, _error!),
                    const SizedBox(height: 18),
                    _Appear(
                      key: const ValueKey('buttons'),
                      index: 4,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.pop(context, false),
                              child: const T('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: (_busy ||
                                      blocked ||
                                      _dir == null)
                                  ? null
                                  : _start,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.download_rounded),
                              label: Text(size > 0
                                  ? '${tr('Download')} · ${formatBytes(size)}'
                                  : tr('Download')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The file: icon, the FULL file name (wraps, never cut), type and size.
  Widget _fileCard(ColorScheme cs, FileKind kind, String name, String? mime,
      int size, bool loading) {
    Widget chip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: kind.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: kind.color),
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kind.color)),
          ]),
        );

    // A long random name taken from the link is not shown: a calm placeholder
    // holds the space until the real name is known, then it fades in, so the
    // popup never opens with a huge block of text that jumps afterwards.
    final known = !loading || (_looksLikeFileName(name) && name.length <= 80);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.07),
        border: Border.all(color: kind.color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: kind.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(kind.icon, color: kind.color, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (cur, prev) => Stack(
                alignment: Alignment.topLeft,
                children: [...prev, if (cur != null) cur],
              ),
              child: !known
                  ? Column(
                      key: const ValueKey('skeleton'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        _Skel(width: double.infinity, height: 15),
                        const SizedBox(height: 8),
                        const _Skel(width: 150, height: 15),
                        const SizedBox(height: 14),
                        const Row(children: [
                          _Skel(width: 70, height: 24, radius: 12),
                          SizedBox(width: 6),
                          _Skel(width: 70, height: 24, radius: 12),
                        ]),
                      ],
                    )
                  : Column(
              key: const ValueKey('name'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_editing)
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    minLines: 1,
                    maxLines: null,
                    onChanged: (_) => setState(() => _nameEdited = true),
                    decoration: InputDecoration(
                      labelText: tr('File name'),
                      isDense: true,
                    ),
                  )
                else
                  SelectableText(
                    name,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    chip(Icons.description_outlined, _typeLabel(name, mime)),
                    chip(
                        Icons.straighten_rounded,
                        size > 0
                            ? formatBytes(size)
                            : (loading
                                ? tr('checking…')
                                : tr('size unknown'))),
                  ],
                ),
              ],
            ),
            ),
          ),
          IconButton(
            tooltip: tr(_editing ? 'Done' : 'Rename'),
            visualDensity: VisualDensity.compact,
            icon: Icon(_editing ? Icons.check_rounded : Icons.edit_rounded,
                size: 20),
            onPressed: _busy ? null : () => setState(() => _editing = !_editing),
          ),
        ],
      ),
    );
  }

  Widget _saveSection(ColorScheme cs) {
    final dir = _effectiveDir;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const T('Save to',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : _chooseFolder,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded, color: Color(0xFFF59E0B)),
                const SizedBox(width: 10),
                Expanded(
                  child: dir == null
                      ? const Text('…')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(folderName(dir),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14.5)),
                              ),
                              if (_autoSorted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(tr('Auto by file type'),
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: cs.primary)),
                                ),
                              ],
                            ]),
                            Text(prettyPath(dir),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurfaceVariant)),
                          ],
                        ),
                ),
                TextButton(
                  onPressed: _busy ? null : _chooseFolder,
                  child: const T('Change'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final q in [
                for (final f in _quickFolders)
                  (f.$1, f.$2.isEmpty ? DownloadManager.instance.defaultDirSync : f.$2),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tr(q.$1)),
                    selected: _dirManual && _dir == q.$2,
                    showCheckmark: false,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                              _dir = q.$2;
                              _dirManual = true;
                            }),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.folder_open_rounded, size: 18),
                label: const T('Choose folder'),
                onPressed: _busy ? null : _chooseFolder,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(ColorScheme cs, IconData icon, String label, String value,
      {Widget? trailing, VoidCallback? onTap, int maxLines = 2}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Text(tr(label),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    );
  }

  Widget _note(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
            const SizedBox(width: 6),
            Expanded(
                child: Text(tr(text),
                    style: TextStyle(color: cs.error, fontSize: 13))),
          ],
        ),
      );
}

/// Fades and slides a section up a little, one after another, once the popup
/// has floated in.
class _Appear extends StatefulWidget {
  final int index;
  final Widget child;
  const _Appear({super.key, required this.index, required this.child});

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> {
  // No per-block animation any more: moving the whole box is smooth, and extra
  // fades running at the same time made the opening stutter.
  @override
  Widget build(BuildContext context) => widget.child;
}

/// The download arrow in the popup's header: it gently bobs, so the box feels alive.
class _BobIcon extends StatefulWidget {
  final Color color;
  const _BobIcon({required this.color});

  @override
  State<_BobIcon> createState() => _BobIconState();
}

class _BobIconState extends State<_BobIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    // idle loops start after the box has landed (they repaint the whole box)
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.translate(
          offset: Offset(0, -2 + 4 * Curves.easeInOut.transform(_c.value)),
          child: Icon(Icons.download_rounded, color: widget.color),
        ),
      );
}

/// Soft pulsing placeholder bar.
class _Skel extends StatefulWidget {
  final double width, height, radius;
  const _Skel({required this.width, required this.height, this.radius = 7});

  @override
  State<_Skel> createState() => _SkelState();
}

class _SkelState extends State<_Skel> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.06 + 0.07 * _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
