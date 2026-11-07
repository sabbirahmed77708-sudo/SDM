import '../pull_refresh.dart';
import 'package:flutter/material.dart';

import '../browser/browser_controller.dart';
import '../browser/sheets.dart';
import '../download_manager.dart';
import '../l10n.dart';
import '../folder_picker.dart';
import 'about_screen.dart';
import 'download_settings_screen.dart';
import 'notification_settings_screen.dart';

/// App-level settings (downloads, appearance, language).
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dm = DownloadManager.instance;
    final browser = BrowserController.instance;
    return Scaffold(
      appBar: AppBar(title: const T('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([dm, browser, L10n.instance]),
        builder: (context, _) => PullRefresh(child: ListView(physics: kPullPhysics, 
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.wifi_rounded),
              title: const T('Wi-Fi only'),
              subtitle: const T('Download only when connected to Wi-Fi'),
              value: dm.wifiOnly,
              onChanged: dm.setWifiOnly,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const T('Theme'),
              trailing: DropdownButton<ThemeMode>(
                value: browser.themeMode,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(
                      value: ThemeMode.system, child: Text(tr('System'))),
                  DropdownMenuItem(
                      value: ThemeMode.light, child: Text(tr('Light'))),
                  DropdownMenuItem(
                      value: ThemeMode.dark, child: Text(tr('Dark'))),
                ],
                onChanged: (m) {
                  if (m != null) browser.setThemeMode(m);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: const T('Language'),
              subtitle: Text(L10n.instance.isBn ? 'বাংলা' : 'English'),
              onTap: () => showLanguageDialog(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const T('Download folder'),
              subtitle: Text(prettyPath(dm.preferredDirSync)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final cur = await dm.preferredDir();
                if (!context.mounted) return;
                final p = await pickFolder(context, start: cur);
                if (p != null) await dm.setPreferredDir(p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const T('Download speed & queue'),
              subtitle: const T('Auto resume, queue, speed limit'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DownloadSettingsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const T('Notification settings'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const T('Browser settings'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BrowserSettingsScreen(browser: browser)),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const T('About'),
              onTap: () => showAboutDrom(context),
            ),
          ],
        )),
      ),
    );
  }
}

/// Language picker. Changing the language rebuilds the whole app.
Future<void> showLanguageDialog(BuildContext context) async {
  final l = L10n.instance;
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const T('Choose language'),
      children: [
        for (final e in const [('en', 'English'), ('bn', 'বাংলা')])
          ListTile(
            leading: Icon(l.code == e.$1
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded),
            title: Text(e.$2),
            onTap: () => Navigator.pop(ctx, e.$1),
          ),
      ],
    ),
  );
  if (picked != null) await l.setLanguage(picked);
}

void showAboutDrom(BuildContext context) {
  Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const AboutScreen()),
  );
}
