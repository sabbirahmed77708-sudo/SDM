import 'package:flutter/material.dart';

import '../l10n.dart';
import '../update_ui.dart';
import '../updater.dart';

/// About SDM: logo, version and "Check for update".
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  final up = UpdateChecker.instance;

  @override
  void initState() {
    super.initState();
    up.loadVersion();
    // silent: opening the page must not start a download on mobile data
    if (!up.checkedOnce) up.check(silent: true);
  }

  /// "Check for update": says clearly what it found, including "no update".
  Future<void> _manualCheck() async {
    await up.check();
    if (!mounted) return;
    final msg = up.error != null
        ? up.error!
        : (up.available == null
            ? 'No new update right now. You have the latest version.'
            : null);
    if (msg == null) return; // update found: the card above shows it
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(tr(msg)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const T('About')),
      body: ListenableBuilder(
        listenable: Listenable.merge([up, L10n.instance]),
        builder: (context, _) {
          // only the version; the build number stays inside the app
          final ver =
              up.version.isEmpty ? '' : '${tr('Version')} ${up.version}';
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            children: [
              Center(
                // the app logo only, nothing around it
                child: Image.asset('assets/icon/logo.png',
                    width: 150, fit: BoxFit.contain, filterQuality: FilterQuality.high),
              ),
              const SizedBox(height: 18),
              const Center(
                child: Text('SDM',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(ver,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
              ),
              const SizedBox(height: 14),
              Center(
                child: T('Speed download manager with a built-in browser.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
              ),
              const SizedBox(height: 6),
              // small developer credit right under the tagline
              Center(
                child: Text('${tr('Developer')}: SH',
                    style: TextStyle(
                        color: cs.outline,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)),
              ),
              const SizedBox(height: 26),
              _updateCard(cs),
            ],
          );
        },
      ),
    );
  }

  Widget _updateCard(ColorScheme cs) {
    final info = up.available;
    Widget body;

    if (up.checking) {
      body = Row(children: [
        const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 14),
        const Expanded(child: T('Checking for updates…')),
      ]);
    } else if (info != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.system_update_rounded, color: cs.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: T('New version available',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 8),
          // only how big the update is and when it came out; both go away
          // once it is installed (the card then says "up to date")
          Text(
            updateSummary(info),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 14),
          const UpdateActionButton(),
        ],
      );
    } else if (up.error != null) {
      body = Row(children: [
        Icon(Icons.error_outline_rounded, color: cs.error),
        const SizedBox(width: 12),
        Expanded(child: T(up.error!, style: TextStyle(color: cs.error))),
      ]);
    } else {
      body = Row(children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
        const SizedBox(width: 12),
        const Expanded(child: T('You are up to date')),
      ]);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (!up.checking &&
                up.phase != UpdatePhase.downloading &&
                up.phase != UpdatePhase.patching) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _manualCheck,
                icon: const Icon(Icons.refresh_rounded),
                label: const T('Check for update'),
              ),
            ],
            const SizedBox(height: 4),
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: up.autoUpdate,
              onChanged: up.setAutoUpdate,
              title: const T('Auto-update',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const T(
                  'Download new versions by itself on Wi-Fi. You only tap Install.',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
