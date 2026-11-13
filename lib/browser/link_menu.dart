import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import 'browser_controller.dart';
import 'download_prompt.dart';

/// What a long-press on a link or an image offers (like Chrome's menu).
Future<void> showLinkMenu(
  BuildContext context, {
  required BrowserController browser,
  required String url,
  required bool isImage,
  required String referer,
  required void Function(DownloadRequest) onDownload,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final cs = Theme.of(context).colorScheme;

  Widget tile(IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: cs.onSurfaceVariant),
        title: Text(tr(label)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
            const Divider(height: 1),
            tile(Icons.open_in_new_rounded,
                isImage ? 'Open image in new tab' : 'Open in new tab',
                () => browser.newTab(url: url)),
            tile(Icons.tab_unselected_rounded, 'Open in background',
                () => browser.newTab(url: url, activate: false)),
            tile(Icons.download_rounded,
                isImage ? 'Download image' : 'Download link', () {
              onDownload(DownloadRequest(url: url, referer: referer));
            }),
            tile(Icons.link_rounded, isImage ? 'Copy image address' : 'Copy link',
                () async {
              await Clipboard.setData(ClipboardData(text: url));
              messenger?.showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
                content: Text(tr('Link copied')),
              ));
            }),
            tile(Icons.share_outlined, 'Share link', () => Share.share(url)),
          ],
        ),
      ),
    ),
  );
}
