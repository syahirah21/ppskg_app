import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'theme.dart';

void main() {
  runApp(const PpskgApp());
}

class PpskgApp extends StatelessWidget {
  const PpskgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PPSKG',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) => _PhoneFrame(child: child!),
      home: ValueListenableBuilder<AuthUser?>(
        valueListenable: AuthService.user,
        builder: (context, user, _) =>
            user == null ? const LoginScreen() : const HomeShell(),
      ),
    );
  }
}

/// Keeps the mobile layout on wide screens (e.g. the web version opened on a
/// laptop) by centring the app in a phone-width column. Phones and narrow
/// windows get the full width as before.
class _PhoneFrame extends StatelessWidget {
  final Widget child;

  const _PhoneFrame({required this.child});

  static const double maxWidth = 480;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth) return child;
    return ColoredBox(
      color: smartBrown,
      child: Center(
        child: Container(
          width: maxWidth,
          decoration: const BoxDecoration(
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 24)],
          ),
          child: ClipRect(
            child: MediaQuery(
              data: media.copyWith(size: Size(maxWidth, media.size.height)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
