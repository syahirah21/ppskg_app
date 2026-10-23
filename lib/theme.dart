import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Colours matched to the RISDA SmartMap web app: dark brown sidebar,
// mustard-gold highlights, cream page and beige cards.
const Color smartBrown = Color(0xFF2B2219);
const Color smartBrownLight = Color(0xFF4A3A26);
const Color smartGold = Color(0xFFE5B547);
const Color smartGoldDeep = Color(0xFFB8862B);
const Color smartCream = Color(0xFFFAF7F0);
const Color smartBeige = Color(0xFFF3EDE2);
const Color smartBorder = Color(0xFFE8DFCF);
const Color smartInk = Color(0xFF2A2118);
const Color smartMuted = Color(0xFF8A7C68);
const Color smartGreen = Color(0xFF3F8F46);
const Color smartOrange = Color(0xFFE67E1A);

/// Windows at least this wide (laptops, desktops) get the desktop layout:
/// a sidebar instead of the bottom bar, and multi-column pages.
const double desktopBreakpoint = 900;

bool isDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= desktopBreakpoint;

/// Desktop text is drawn at this fraction of its phone size.
const double desktopTextScale = 0.88;

/// Widest the desktop page content grows before it is centred.
const double desktopContentWidth = 1200;

/// Centres [child] and caps its width at [desktopContentWidth].
Widget desktopContent(Widget child) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: desktopContentWidth),
    child: child,
  ),
);

/// Header gradient shared by every screen, like the SmartMap sidebar.
const LinearGradient headerGradient = LinearGradient(
  colors: [smartBrown, smartBrownLight],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: smartGold,
    brightness: brightness,
    primary: light ? smartGoldDeep : smartGold,
    onPrimary: light ? Colors.white : smartInk,
    tertiaryContainer: light ? const Color(0xFFFBEFD0) : smartBrownLight,
    onTertiaryContainer: light ? const Color(0xFF7A5A12) : smartGold,
    surface: light ? smartCream : const Color(0xFF1E1812),
    onSurface: light ? smartInk : const Color(0xFFF3EDE2),
    surfaceContainerLow: light ? smartBeige : const Color(0xFF2B2219),
    surfaceContainerHighest: light
        ? const Color(0xFFECE3D3)
        : const Color(0xFF3A2E20),
    outlineVariant: light ? smartBorder : const Color(0xFF4A3A26),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    // Gold buttons with dark text, like "Cari" and "Urus Peranan".
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: smartGold,
        foregroundColor: smartInk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: light ? smartBeige : smartBrown,
      indicatorColor: smartGold,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// Always-light theme for cream cards and dialogs, so their text stays
/// dark and readable when the device is in dark mode.
final ThemeData lightTheme = buildTheme(Brightness.light);

/// Fixed colour per STATUS_TOREHAN value so charts and chips always match.
Color statusTorehanColor(String? status) => switch (status) {
  'Bertoreh' => smartGreen,
  'Tidak Bertoreh' => smartOrange,
  'Getah Muda' => smartGoldDeep,
  _ => const Color(0xFFA89C8A),
};

IconData statusTorehanIcon(String? status) => switch (status) {
  'Bertoreh' => Icons.water_drop,
  'Tidak Bertoreh' => Icons.block,
  'Getah Muda' => Icons.eco,
  _ => Icons.help_outline,
};

/// Formats an integer with thousands separators, e.g. 209795 -> 209,795.
String fmtInt(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
