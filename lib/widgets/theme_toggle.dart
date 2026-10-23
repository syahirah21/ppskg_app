import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// Switches the whole app between light and dark mode.
void toggleThemeMode() =>
    AppState.themeMode.value = AppState.themeMode.value == ThemeMode.dark
    ? ThemeMode.light
    : ThemeMode.dark;

/// Round sun/moon button for the brown headers (phone dashboard, login).
/// Shows the current mode: a sun in light mode, a moon in dark mode.
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeMode,
      builder: (context, mode, _) {
        final dark = mode == ThemeMode.dark;
        return Tooltip(
          message: dark ? 'Mod cerah' : 'Mod gelap',
          child: Material(
            color: Colors.white.withValues(alpha: 0.12),
            shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: toggleThemeMode,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  dark ? Icons.dark_mode : Icons.light_mode,
                  size: 20,
                  color: smartGold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
