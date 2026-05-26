import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'bridge/hotkey_service.dart';
import 'ui/screens/app_shell.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const opts = WindowOptions(
    size: Size(1240, 780),
    minimumSize: Size(880, 560),
    center: true,
    title: 'mutter',
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(opts, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: NewmumbleApp()));
}

class NewmumbleApp extends ConsumerWidget {
  const NewmumbleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure the hotkey service is initialised once the app mounts.
    ref.watch(hotkeyServiceProvider);
    return MaterialApp(
      title: 'mutter',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AppShell(),
    );
  }
}
