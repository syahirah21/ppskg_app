import 'package:flutter/material.dart';

import '../services/arcgis_service.dart';

/// State shared between tabs, so choosing a state on the Dashboard also
/// moves the Map and vice versa.
class AppState {
  AppState._();

  /// The selected state (NEGERI value), or null for all of Malaysia.
  static final negeri = ValueNotifier<String?>(null);

  /// Every state with its national lot count, for the state picker.
  /// Includes 'Tiada data' so the all-Malaysia total matches.
  static final negeriOptions = ValueNotifier<List<GroupStat>>([]);

  /// Light or dark mode, chosen with the switch in the sidebar, the
  /// profile panel or the sun/moon button.
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
}
