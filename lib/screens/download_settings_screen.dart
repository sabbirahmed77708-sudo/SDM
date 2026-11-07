import '../pull_refresh.dart';
import 'package:flutter/material.dart';

import '../download_manager.dart';
import '../l10n.dart';
import '../models.dart';

/// Automatic resume, how many downloads run together (the rest wait in a
/// queue) and speed limits.
class DownloadSettingsScreen extends StatelessWidget {
  const DownloadSettingsScreen({super.key});

  static String limitText(int bps, {String off = 'Unlimited'}) {
    if (bps <= 0) return tr(off);
    return '${formatBytes(bps)}/s';
  }

  Future<void> _pickLimit(
    BuildContext context, {
    required String title,
    required int current,
    required String offLabel,
    required List<int> presets,
    required Future<void> Function(int) onSet,
  }) async {
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final custom = TextEditingController();
        return AlertDialog(
          title: Text(tr(title)),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                RadioGroup<int>(
                  groupValue: current,
                  onChanged: (v) {
                    if (v != null) Navigator.pop(ctx, v);
                  },
                  child: Column(children: [
                    RadioListTile<int>(
                      value: 0,
                      title: Text(tr(offLabel)),
                    ),
                    for (final p in presets)
                      RadioListTile<int>(
                        value: p,
                        title: Text('${formatBytes(p)}/s'),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: custom,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('Custom (KB/s)'),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final v = int.tryParse(custom.text.trim());
                        if (v != null && v > 0) Navigator.pop(ctx, v * 1024);
                      },
                      child: const T('Set'),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const T('Cancel')),
          ],
        );
      },
    );
    if (res != null) await onSet(res);
  }

  Widget _head(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(
          tr(t),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dm = DownloadManager.instance;
    const kb = 1024;
    return Scaffold(
      appBar: AppBar(title: const T('Download speed & queue')),
      body: ListenableBuilder(
        listenable: Listenable.merge([dm, L10n.instance]),
        builder: (context, _) => PullRefresh(child: ListView(physics: kPullPhysics, 
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _head(context, 'Connection'),
            SwitchListTile(
              secondary: const Icon(Icons.wifi_find_rounded),
              title: const T('Resume automatically'),
              subtitle: const T(
                  'When the internet is lost or a download fails because of the network, SDM waits and continues by itself when the internet is back'),
              value: dm.autoRetry,
              onChanged: dm.setAutoRetry,
            ),
            _head(context, 'Folders'),
            SwitchListTile(
              secondary: const Icon(Icons.folder_copy_outlined),
              title: const T('Sort files into folders by type'),
              subtitle: const T(
                  'Video, Music, Images, Apps, Archives and Documents each go to their own folder inside the download folder. A folder you pick by hand is always used as it is.'),
              value: dm.sortByType,
              onChanged: dm.setSortByType,
            ),
            _head(context, 'Queue'),
            ListTile(
              leading: const Icon(Icons.format_list_numbered_rounded),
              title: const T('Downloads at the same time'),
              subtitle: const T(
                  'The others wait in the queue and start by themselves'),
              trailing: DropdownButton<int>(
                value: dm.maxActive.clamp(1, 6),
                underline: const SizedBox.shrink(),
                items: [
                  for (var i = 1; i <= 6; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: (v) {
                  if (v != null) dm.setMaxActive(v);
                },
              ),
            ),
            _head(context, 'Speed limit'),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: const T('Speed limit for downloads'),
              subtitle: Text(
                  '${limitText(dm.speedLimit)} · ${tr('shared equally between running downloads')}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickLimit(
                context,
                title: 'Speed limit for downloads',
                current: dm.speedLimit,
                offLabel: 'Unlimited',
                presets: const [
                  128 * kb,
                  256 * kb,
                  512 * kb,
                  1024 * kb,
                  2048 * kb,
                  5120 * kb,
                  10240 * kb,
                ],
                onSet: dm.setSpeedLimit,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const T('Limit while the browser is open'),
              subtitle: Text(
                  '${limitText(dm.browserLimit, off: 'Off')} · ${tr('keeps internet free for browsing and watching videos')}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickLimit(
                context,
                title: 'Limit while the browser is open',
                current: dm.browserLimit,
                offLabel: 'Off',
                presets: const [
                  128 * kb,
                  256 * kb,
                  512 * kb,
                  1024 * kb,
                  2048 * kb,
                ],
                onSet: dm.setBrowserLimit,
              ),
            ),
            if (dm.browserOpen && dm.browserLimit > 0)
              ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(tr('Browser is open: the lower limit applies now')),
              ),
          ],
        )),
      ),
    );
  }
}
