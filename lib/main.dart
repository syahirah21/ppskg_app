import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/draft_service.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Brings back drafts and queued edits saved on this device.
  await DraftService.init();
  // Send anything queued as soon as the officer comes back to the app.
  AppLifecycleListener(
    onResume: () {
      if (DraftService.queuedCount > 0) DraftService.sync();
    },
  );
  runApp(const PpskgApp());
}

class PpskgApp extends StatelessWidget {
  const PpskgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'SmartMap',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        // Text reads large on laptop screens, so shrink it a little there.
        builder: (context, child) => isDesktop(context)
            ? MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(desktopTextScale),
                ),
                child: child!,
              )
            : child!,
        home: ValueListenableBuilder<AuthUser?>(
          valueListenable: AuthService.user,
          builder: (context, user, _) =>
              user == null ? const LoginScreen() : const HomeShell(),
        ),
      ),
    );
  }
}
