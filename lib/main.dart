import 'package:flutter/material.dart';

import 'browser/browser_controller.dart';
import 'download_manager.dart';
import 'l10n.dart';
import 'link_intake.dart';
import 'notifier.dart';
import 'notify_settings.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'updater.dart';

/// One damaged saved setting must not keep the whole app from opening.
Future<void> _safely(Future<void> Function() step) async {
  try {
    await step();
  } catch (e) {
    debugPrint('start-up step failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _safely(DownloadManager.instance.init);
  await _safely(L10n.instance.init);
  await _safely(BrowserController.instance.init);
  await _safely(NotifySettings.instance.init);
  await _safely(() async => DownloadNotifier.instance.start());
  runApp(const SdmApp());
  LinkIntake.instance.start();
  // quiet check; a new version shows up in the menu and in About
  UpdateChecker.instance.check(silent: true);
}

class SdmApp extends StatelessWidget {
  const SdmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([BrowserController.instance, L10n.instance]),
      builder: (context, _) => MaterialApp(
        navigatorKey: rootNavigatorKey,
        // Rebuild every screen when the language changes.
        builder: (context, child) => KeyedSubtree(
          key: ValueKey(L10n.instance.code),
          child: child ?? const SizedBox.shrink(),
        ),
        title: 'SDM',
        debugShowCheckedModeBanner: false,
        themeMode: BrowserController.instance.themeMode,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}
