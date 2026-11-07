import '../pull_refresh.dart';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../download_manager.dart';
import '../l10n.dart';
import '../models.dart';
import 'browser_controller.dart';
import 'browser_tab.dart';
import 'download_prompt.dart';

/// Slim floating capsule with a small download icon. Drag it anywhere; tap it
/// to see everything that was found and pick what to download.
class MediaBubble extends StatefulWidget {
  final BrowserController browser;
  final BrowserTab tab;
  final void Function(DownloadRequest) onDownload;
  const MediaBubble({
    super.key,
    required this.browser,
    required this.tab,
    required this.onDownload,
  });

  @override
  State<MediaBubble> createState() => _MediaBubbleState();
}

class _MediaBubbleState extends State<MediaBubble> {
  static const double _w = 70;
  static const double _h = 34;
  Offset? _drag; // pixel position while dragging

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tab = widget.tab;
    final n = tab.media.length;
    return LayoutBuilder(builder: (context, box) {
      final maxX = (box.maxWidth - _w).clamp(0.0, double.infinity);
      final maxY = (box.maxHeight - _h).clamp(0.0, double.infinity);
      final b = widget.browser;
      final rest = Offset(b.bubbleX * maxX, b.bubbleY * maxY);
      final pos = _drag ?? rest;
      return Stack(
        children: [
          AnimatedPositioned(
            duration:
                _drag == null ? const Duration(milliseconds: 220) : Duration.zero,
            curve: Curves.easeOutCubic,
            left: pos.dx,
            top: pos.dy,
            child: GestureDetector(
              onPanStart: (_) => setState(() => _drag = rest),
              onPanUpdate: (d) => setState(() {
                final p = (_drag ?? rest) + d.delta;
                _drag = Offset(p.dx.clamp(0.0, maxX), p.dy.clamp(0.0, maxY));
              }),
              onPanEnd: (_) {
                final p = _drag ?? rest;
                // stick to the nearer side edge
                final x = (maxX <= 0) ? 1.0 : (p.dx / maxX >= 0.5 ? 1.0 : 0.0);
                final y = maxY <= 0 ? 0.0 : p.dy / maxY;
                setState(() => _drag = null);
                b.setBubble(x, y);
              },
              onTap: () => showMediaSheet(context, tab, widget.onDownload),
              child: TweenAnimationBuilder<double>(
                // a small bounce every time a new item is found
                key: ValueKey('bubble_$n'),
                tween: Tween(begin: 0.8, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                // glass: see-through, frosted, so the page stays visible
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_h / 2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: _drag != null ? 14 : 8,
                          offset: const Offset(0, 3)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_h / 2),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: _w,
                        height: _h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_h / 2),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: dark ? 0.22 : 0.55),
                              Colors.white.withValues(alpha: dark ? 0.08 : 0.25),
                            ],
                          ),
                          border: Border.all(
                              color: Colors.white
                                  .withValues(alpha: dark ? 0.35 : 0.8)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.download_rounded,
                                color: const Color(0xFF5AB4FF),
                                size: 20),
                            if (n > 1) ...[
                              const SizedBox(width: 4),
                              Text('$n',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF5AB4FF))),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

String _urlName(String url) {
  final last = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
  try {
    return Uri.decodeComponent(last);
  } catch (_) {
    return last;
  }
}

String _safe(String s) {
  var n = s.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (n.length > 60) n = n.substring(0, 60).trim();
  return n;
}

String _qualityName(MediaEntry e) {
  if (e.audio) {
    if (e.label.isNotEmpty) return e.label;
    return tr('Audio');
  }
  final h = e.height;
  if (h <= 0) return e.label.isNotEmpty ? e.label : tr('Video');
  final tag = h >= 4320
      ? ' 8K'
      : h >= 2160
          ? ' 4K'
          : h >= 1440
              ? ' 2K'
              : h >= 1080
                  ? ' Full HD'
                  : h >= 720
                      ? ' HD'
                      : '';
  return '${h}p$tag';
}

String _fileNameFor(BrowserTab tab, MediaEntry e) {
  final base = _safe(tab.title.isNotEmpty ? tab.title : tab.host);
  final q = e.audio
      ? (e.label.isNotEmpty ? _safe(e.label) : 'audio')
      : (e.height > 0 ? '${e.height}p' : '');
  final name = [if (base.isNotEmpty) base else 'media', if (q.isNotEmpty) q].join(' ');
  return '$name.${e.ext}';
}

/// Lists the audio / video found on the page, best quality first.
Future<void> showMediaSheet(
  BuildContext context,
  BrowserTab tab,
  void Function(DownloadRequest) onDownload,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 420),
      reverseDuration: Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _MediaSheet(
      tab: tab,
      onPick: (e) {
        Navigator.pop(ctx);
        onDownload(DownloadRequest(
          url: e.url,
          fileName: _fileNameFor(tab, e),
          referer: tab.url,
        ));
      },
    ),
  );
}

class _MediaSheet extends StatefulWidget {
  final BrowserTab tab;
  final void Function(MediaEntry) onPick;
  const _MediaSheet({required this.tab, required this.onPick});

  @override
  State<_MediaSheet> createState() => _MediaSheetState();
}

class _MediaSheetState extends State<_MediaSheet> {
  bool? _audioTab; // null = pick automatically

  List<MediaEntry> _sorted(bool audio) {
    final l = widget.tab.media.where((e) => e.audio == audio).toList();
    l.sort((a, b) {
      final h = b.height.compareTo(a.height);
      if (h != 0) return h;
      final bw = b.bandwidth.compareTo(a.bandwidth);
      if (bw != 0) return bw;
      return b.size.compareTo(a.size);
    });
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.tab,
      builder: (context, _) {
        final videos = _sorted(false);
        final audios = _sorted(true);
        final audioTab = _audioTab ?? (videos.isEmpty && audios.isNotEmpty);
        final list = audioTab ? audios : videos;
        final best = list.where((e) => e.downloadable).firstOrNull;
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(children: [
                  Icon(Icons.download_for_offline_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: T('Audio / video on this page',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.movie_outlined),
                          label: Text('${tr('Video')} (${videos.length})')),
                      ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.music_note_outlined),
                          label: Text('${tr('Audio')} (${audios.length})')),
                    ],
                    selected: {audioTab},
                    onSelectionChanged: (s) =>
                        setState(() => _audioTab = s.first),
                  ),
                ),
              ),
              if (best != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => widget.onPick(best),
                      icon: const Icon(Icons.bolt_rounded),
                      label: Text(
                          '${tr('Download best quality')} · ${_qualityName(best)}'),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: T(
                            audioTab
                                ? 'No audio found yet. Play it on the page and it appears here.'
                                : 'No video found yet. Play it on the page and it appears here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                      )
                    : PullRefresh(child: ListView.separated(physics: kPullPhysics, 
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _MediaRow(
                          key: ValueKey(list[i].url),
                          tab: widget.tab,
                          entry: list[i],
                          isBest: i == 0 && list[i].downloadable && list.length > 1,
                          onPick: widget.onPick,
                        ),
                      )),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: T(
                  'Protected (DRM) videos and live streams cannot be downloaded.',
                  style: TextStyle(fontSize: 11.5, color: cs.outline),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaRow extends StatefulWidget {
  final BrowserTab tab;
  final MediaEntry entry;
  final bool isBest;
  final void Function(MediaEntry) onPick;
  const _MediaRow({
    super.key,
    required this.tab,
    required this.entry,
    required this.isBest,
    required this.onPick,
  });

  @override
  State<_MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<_MediaRow> {
  MediaEntry get e => widget.entry;

  @override
  void initState() {
    super.initState();
    _askSize();
  }

  Future<void> _askSize() async {
    if (e.hls || e.size >= 0 || e.sizeAsked) return;
    e.sizeAsked = true;
    try {
      final h = await BrowserController.instance.pageHeaders(widget.tab, e.url);
      final p = await DownloadManager.instance.inspect(e.url, headers: h);
      if (p.total > 0) e.size = p.total;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  String _detail() {
    final parts = <String>[];
    parts.add(e.hls ? 'HLS' : e.ext.toUpperCase());
    if (e.size > 0) {
      parts.add(formatBytes(e.size));
    } else if (e.hls && e.bandwidth > 0 && e.seconds > 0) {
      parts.add('~${formatBytes(e.bandwidth / 8 * e.seconds)}');
    } else if (e.hls && e.bandwidth > 0) {
      parts.add('${(e.bandwidth / 1000000).toStringAsFixed(1)} Mbps');
    } else if (!e.hls && !e.sizeAsked) {
      parts.add(tr('checking…'));
    }
    if (e.seconds > 0) {
      final s = e.seconds.round();
      parts.add(s >= 3600
          ? '${s ~/ 3600}h ${(s % 3600) ~/ 60}m'
          : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String? note;
    if (e.encrypted) note = 'Protected stream, cannot be downloaded';
    if (e.live) note = 'Live stream, cannot be downloaded';
    if (note == null && e.separateAudio) {
      note = 'Sound is a separate stream: also download it from the Audio tab';
    }
    return ListTile(
      enabled: e.downloadable,
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
            e.audio ? Icons.music_note_rounded : Icons.play_arrow_rounded,
            color: cs.onPrimaryContainer),
      ),
      title: Row(children: [
        Flexible(
          child: Text(_qualityName(e),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        if (widget.isBest) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(tr('Best'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
      subtitle: Text(
        [
          widget.tab.title.isNotEmpty ? widget.tab.title : _urlName(e.url),
          _detail(),
          if (note != null) tr(note),
        ].join('\n'),
        style: TextStyle(
            color: (e.encrypted || e.live) ? cs.error : cs.onSurfaceVariant,
            fontSize: 12.5),
      ),
      isThreeLine: true,
      trailing: e.downloadable
          ? IconButton.filledTonal(
              tooltip: tr('Download'),
              icon: const Icon(Icons.download_rounded),
              onPressed: () => widget.onPick(e),
            )
          : const Icon(Icons.lock_outline_rounded),
      onTap: e.downloadable ? () => widget.onPick(e) : null,
    );
  }
}
