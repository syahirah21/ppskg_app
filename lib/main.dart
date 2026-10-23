import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  runApp(const PpskgApp());
}

class PpskgApp extends StatelessWidget {
  const PpskgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'PPSKG',
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
