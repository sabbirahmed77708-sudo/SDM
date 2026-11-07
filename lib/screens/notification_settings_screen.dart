import '../pull_refresh.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n.dart';
import '../notifier.dart';
import '../notify_settings.dart';

/// Notification settings: permission, what the progress notification shows,
/// finished/failed alerts, sound / vibration / pop-up, lock screen.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  final s = NotifySettings.instance;
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final v = await DownloadNotifier.instance.permissionGranted();
    if (mounted) setState(() => _allowed = v);
  }

  Future<void> _allow() async {
    final st = await Permission.notification.request();
    if (!st.isGranted) {
      await DownloadNotifier.instance.openSystemSettings();
    }
    await _check();
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(
          tr(t),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  Widget _sw(IconData icon, String title, String sub, bool v,
          ValueChanged<bool> on, {bool enabled = true}) =>
      SwitchListTile(
        secondary: Icon(icon),
        title: T(title),
        subtitle: T(sub),
        value: v,
        onChanged: enabled ? on : null,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const T('Notification settings'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') {
                s.reset();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(tr('Notification settings reset')),
                ));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'reset', child: T('Reset to default')),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, L10n.instance]),
        builder: (context, _) => PullRefresh(onRefresh: _check, child: ListView(physics: kPullPhysics, 
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (_allowed == false)
              Card(
                color: cs.errorContainer,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ListTile(
                  leading: Icon(Icons.notifications_off_rounded,
                      color: cs.onErrorContainer),
                  title: T('Notifications are blocked',
                      style: TextStyle(color: cs.onErrorContainer)),
                  subtitle: T(
                      'Allow them to see download progress and finished alerts.',
                      style: TextStyle(color: cs.onErrorContainer)),
                  trailing: FilledButton(
                      onPressed: _allow, child: const T('Allow')),
                ),
              )
            else if (_allowed == true)
              ListTile(
                leading: const Icon(Icons.notifications_active_rounded,
                    color: Colors.green),
                title: const T('Notifications are allowed'),
              ),
            _head('While downloading'),
            _sw(
              Icons.speed_rounded,
              'Show progress details',
              'Percent and size in the notification',
              s.progressDetails,
              s.setProgressDetails,
            ),
            _sw(
              Icons.view_agenda_outlined,
              'Separate notification for each download',
              'Off: one combined notification',
              s.perDownload,
              s.setPerDownload,
            ),
            _sw(
              Icons.bolt_rounded,
              'Show speed',
              'Current download speed',
              s.showSpeed,
              s.setShowSpeed,
              enabled: s.progressDetails,
            ),
            _sw(
              Icons.timer_outlined,
              'Show time left',
              'Estimated time remaining',
              s.showEta,
              s.setShowEta,
              enabled: s.progressDetails,
            ),
            _sw(
              Icons.pause_circle_outline_rounded,
              'Pause / Resume buttons',
              'Control downloads from the notification',
              s.showButtons,
              s.setShowButtons,
            ),
            _head('When a download ends'),
            _sw(
              Icons.check_circle_outline_rounded,
              'Download complete',
              'Notify when a file is saved',
              s.notifyComplete,
              s.setNotifyComplete,
            ),
            _sw(
              Icons.error_outline_rounded,
              'Download failed',
              'Notify when a download fails',
              s.notifyFailed,
              s.setNotifyFailed,
            ),
            _sw(
              Icons.volume_up_outlined,
              'Sound',
              'Play a sound',
              s.sound,
              s.setSound,
            ),
            _sw(
              Icons.vibration_rounded,
              'Vibrate',
              'Vibrate the phone',
              s.vibrate,
              s.setVibrate,
            ),
            _sw(
              Icons.web_asset_rounded,
              'Pop-up on screen',
              'Show a banner at the top of the screen',
              s.popup,
              s.setPopup,
            ),
            _head('Privacy'),
            _sw(
              Icons.lock_outline_rounded,
              'Show on lock screen',
              'Off: hides the file names while the phone is locked',
              s.lockScreen,
              s.setLockScreen,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.send_rounded),
              title: const T('Send test notification'),
              subtitle: const T('See how a finished download alert looks'),
              onTap: () async {
                await DownloadNotifier.instance.sendTest();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(tr('Test notification sent')),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_applications_outlined),
              title: const T('System notification settings'),
              subtitle: const T('Channels, importance and more in Android'),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: DownloadNotifier.instance.openSystemSettings,
            ),
          ],
        )),
      ),
    );
  }
}
