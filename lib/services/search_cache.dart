import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'arcgis_service.dart';

/// The last few Cari & Kemaskini lists, kept on the device so the screen
/// still shows lots when there's no internet.
class SearchCache {
  SearchCache._();

  static const _key = 'search_cache_v1';

  /// How many different searches to keep (the newest win).
  static const _maxEntries = 10;

  static Future<Map<String, dynamic>> _all() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> put(
    String key,
    List<LotRecord> results,
    Map<IncompleteFilter, int> counts,
  ) async {
    final all = await _all()
      ..remove(key);
    all[key] = {
      'savedAt': DateTime.now().toIso8601String(),
      'results': [for (final r in results) r.toAttributes()],
      'counts': {for (final e in counts.entries) e.key.name: e.value},
    };
    while (all.length > _maxEntries) {
      all.remove(all.keys.first);
    }
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(all),
      );
    } catch (_) {
      // Storage full or blocked: the list just won't be available offline.
    }
  }

  /// The saved list for [key] with its counts and when it was saved.
  static Future<(List<LotRecord>, Map<IncompleteFilter, int>, DateTime)?> get(
    String key,
  ) async {
    final e = (await _all())[key] as Map<String, dynamic>?;
    if (e == null) return null;
    final counts = e['counts'] as Map<String, dynamic>;
    return (
      [
        for (final a in e['results'] as List)
          LotRecord.fromAttributes(a as Map<String, dynamic>),
      ],
      {
        for (final f in IncompleteFilter.values)
          if (counts[f.name] case final num n) f: n.toInt(),
      },
      DateTime.parse(e['savedAt'] as String),
    );
  }
}
