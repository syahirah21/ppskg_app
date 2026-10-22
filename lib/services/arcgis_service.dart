import 'dart:convert';

import 'package:http/http.dart' as http;

/// One row of a grouped statistics query: a category label with its lot
/// count and total planted area (hectares).
class GroupStat {
  final String label;
  final int count;
  final double area;

  const GroupStat(this.label, this.count, this.area);
}

/// Which incomplete lots the Cari & Kemaskini list shows.
enum IncompleteFilter {
  /// Missing a status torehan or a valid tahun tanam.
  semua(
    'Semua',
    "(STATUS_TOREHAN IS NULL OR STATUS_TOREHAN = '' "
        'OR TAHUN_TANAMAN IS NULL '
        'OR TAHUN_TANAMAN < ${LotRecord.minTahunTanam} '
        'OR TAHUN_TANAMAN > ${LotRecord.maxTahunTanam})',
  ),

  /// No status torehan, whatever the tahun tanam.
  tiadaStatus(
    'Tiada status',
    "(STATUS_TOREHAN IS NULL OR STATUS_TOREHAN = '')",
  ),

  /// Tahun tanam missing or outside 1960–2026, whatever the status.
  tiadaTahun(
    'Tiada tahun',
    '(TAHUN_TANAMAN IS NULL '
        'OR TAHUN_TANAMAN < ${LotRecord.minTahunTanam} '
        'OR TAHUN_TANAMAN > ${LotRecord.maxTahunTanam})',
  );

  final String label;
  final String where;

  const IncompleteFilter(this.label, this.where);
}

/// One rubber lot returned by a name search. Only the fields the app shows
/// are requested; phone numbers and full addresses are never downloaded.
class LotRecord {
  /// Permanent record ID; edits are matched on this, not OBJECTID, because
  /// OBJECTIDs can change when the layer is reloaded or republished.
  final String globalId;
  final String lotId;
  final String nama;
  final String nokp;
  final String noLot;

  /// Mukim where the land is (MUKIM_TANAH), not the owner's address mukim.
  final String mukim;
  final String daerah;
  final String negeri;
  final double luas;
  final String? statusTorehan;

  /// Where the current STATUS_TOREHAN came from, e.g. BPKG or e-SRM.
  final String? statusTorehanSource;

  /// Officer who last updated the lot (NAMA_PENGAWAI), if any.
  final String? namaPengawai;

  /// Planting year (TAHUN_TANAMAN) as stored, which may be missing or
  /// invalid (e.g. 1 or 20019); see [needsTahunTanam].
  final int? tahunTanam;

  /// e-SRM application number, e.g. "GM003358/2022", if the lot has one.
  final String? noPermohonan;

  const LotRecord({
    required this.globalId,
    required this.lotId,
    required this.nama,
    required this.nokp,
    required this.noLot,
    required this.mukim,
    required this.daerah,
    required this.negeri,
    required this.luas,
    required this.statusTorehan,
    required this.statusTorehanSource,
    required this.namaPengawai,
    required this.tahunTanam,
    required this.noPermohonan,
  });

  /// Earliest and latest planting years accepted, matching the data team's
  /// STATUS_TAHUN_TANAMAN rule ("BAIK (1960 - 2026)").
  static const minTahunTanam = 1960;
  static const maxTahunTanam = 2026;

  static bool validTahunTanam(int? year) =>
      year != null && year >= minTahunTanam && year <= maxTahunTanam;

  /// Whether officers still need to fill in STATUS_TOREHAN.
  bool get needsStatus => statusTorehan == null;

  /// Whether officers still need to fill in a valid TAHUN_TANAMAN.
  bool get needsTahunTanam => !validTahunTanam(tahunTanam);

  static const fields =
      'GlobalID,LOT_ID,NAMA,NOKP,NO_LOT,MUKIM_TANAH,DAERAH,NEGERI,'
      'LUAS_TANAMAN,'
      'STATUS_TOREHAN,SRC_STATUS_TOREHAN,NAMA_PENGAWAI,TAHUN_TANAMAN,'
      'no_permohonan_esrm';

  factory LotRecord.fromAttributes(Map<String, dynamic> a) {
    String s(String k) => (a[k] as String?)?.trim() ?? '-';
    String? opt(String k) {
      final v = (a[k] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    return LotRecord(
      globalId: a['GlobalID'] as String,
      lotId: s('LOT_ID'),
      nama: s('NAMA'),
      nokp: s('NOKP'),
      noLot: s('NO_LOT'),
      mukim: s('MUKIM_TANAH'),
      daerah: s('DAERAH'),
      negeri: s('NEGERI'),
      luas: (a['LUAS_TANAMAN'] as num?)?.toDouble() ?? 0,
      statusTorehan: opt('STATUS_TOREHAN'),
      statusTorehanSource: opt('SRC_STATUS_TOREHAN'),
      namaPengawai: opt('NAMA_PENGAWAI'),
      tahunTanam: (a['TAHUN_TANAMAN'] as num?)?.toInt(),
      noPermohonan: opt('no_permohonan_esrm'),
    );
  }

  /// Grant type from the start of LOT_ID, e.g. "KEKAL_1101070002148" ->
  /// "KEKAL" (the data has KEKAL and SAH).
  String get jenisGeran {
    final i = lotId.indexOf('_');
    return i > 0 ? lotId.substring(0, i) : lotId;
  }

  /// Full IC number in the usual format, e.g. 800101-01-5523. Values that
  /// aren't 12 digits (old or foreign IDs) are shown as stored.
  String get formattedNokp {
    final digits = nokp.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 12) return nokp;
    return '${digits.substring(0, 6)}-${digits.substring(6, 8)}-'
        '${digits.substring(8)}';
  }

  LotRecord copyWith({
    String? statusTorehan,
    String? statusTorehanSource,
    String? namaPengawai,
    int? tahunTanam,
  }) => LotRecord(
    globalId: globalId,
    lotId: lotId,
    nama: nama,
    nokp: nokp,
    noLot: noLot,
    mukim: mukim,
    daerah: daerah,
    negeri: negeri,
    luas: luas,
    statusTorehan: statusTorehan ?? this.statusTorehan,
    statusTorehanSource: statusTorehanSource ?? this.statusTorehanSource,
    namaPengawai: namaPengawai ?? this.namaPengawai,
    tahunTanam: tahunTanam ?? this.tahunTanam,
    noPermohonan: noPermohonan,
  );
}

/// Reads statistics and lot records from the RISDA rubber-lot FeatureServer
/// layer.
class ArcGisService {
  static const String layerUrl =
      'https://gisserver.risda.gov.my/arcgis/rest/services/'
      'Lot_Getah_Satu_Malaysia/FeatureServer/0';

  /// Values field officers can set for STATUS_TOREHAN (as stored in the
  /// layer). 'Getah Muda' still exists in the data but isn't offered.
  static const statusTorehanOptions = ['Bertoreh', 'Tidak Bertoreh'];

  /// While false, saving an edit only previews it and never writes to the
  /// live layer. Turn on only once edits are approved and login is in place.
  static const bool editsEnabled = false;

  /// Written to SRC_STATUS_TOREHAN / SRC_TAHUN_TANAMAN with every change so
  /// the layer records that the value came from this app (alongside BPKG, e-SRM and
  /// e-SPeK). Confirm the exact label with the data team before going live.
  static const String editSource = 'PPSKG Mobile';

  final http.Client _client;

  ArcGisService([http.Client? client]) : _client = client ?? http.Client();

  /// Builds a SQL where clause, optionally limited to one state.
  static String whereFor(String? negeri) =>
      negeri == null ? '1=1' : "NEGERI = '${_sql(negeri)}'";

  static String _sql(String v) => v.replaceAll("'", "''");

  /// Where clause for the map: the state as [whereFor], or, once a
  /// [daerah] is picked, the lots whose land lies in that district
  /// (NEGERI_TANAH / DAERAH_TANAH, not the owner's address), narrowed to
  /// one land [mukim] (MUKIM_TANAH) when given.
  static String whereForArea(String? negeri, String? daerah, [String? mukim]) {
    if (negeri == null || daerah == null) return whereFor(negeri);
    final area =
        "NEGERI_TANAH = '${_sql(negeri)}' AND DAERAH_TANAH = '${_sql(daerah)}'";
    return mukim == null ? area : "$area AND MUKIM_TANAH = '${_sql(mukim)}'";
  }

  /// Matches one lot number exactly. NO_LOT is stored both as "10318" and
  /// "LOT10318" (and TANAH_LOT holds the bare number), so "10318",
  /// "lot10318" and "LOT 10318" all match either form.
  static String lotNumberWhere(String lot) {
    final l = lot
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll("'", "''");
    final bare = l.startsWith('LOT') ? l.substring(3) : l;
    return "(UPPER(NO_LOT) = '$bare' OR UPPER(NO_LOT) = 'LOT$bare' "
        "OR TANAH_LOT = '$bare')";
  }

  /// Land mukims of one district with their lot counts, largest first.
  /// Lots with no mukim are left out.
  Future<List<GroupStat>> mukimOf(String negeri, String daerah) async {
    final stats = await groupBy(
      'MUKIM_TANAH',
      where: whereForArea(negeri, daerah),
    );
    return stats.where((g) => g.label != 'Tiada data').toList();
  }

  /// Lots numbered [lot] within the picked area (up to 10, since the same
  /// number can repeat when no mukim is picked), with the box around them.
  Future<(List<LotRecord>, (double, double, double, double)?)> findLot(
    String lot, {
    required String negeri,
    required String daerah,
    String? mukim,
  }) async {
    final where =
        '${whereForArea(negeri, daerah, mukim)} '
        'AND ${lotNumberWhere(lot)}';
    final (body, extent) = await (
      _query({
        'where': where,
        'outFields': LotRecord.fields,
        'returnGeometry': 'false',
        'resultRecordCount': '10',
      }),
      extentOf(where),
    ).wait;
    final lots = (body['features'] as List)
        .map((f) => LotRecord.fromAttributes(f['attributes']))
        .toList();
    return (lots, extent);
  }

  /// Land districts of every state with their lot counts, keyed by
  /// NEGERI_TANAH, largest first. One small query (~13 KB) so the map can
  /// fetch it up front and open the district picker instantly.
  /// Placeholder values (blank, "TIADA DAERAH") are left out.
  Future<Map<String, List<GroupStat>>> allDaerah() async {
    final body = await _query({
      'where': '1=1',
      'groupByFieldsForStatistics': 'NEGERI_TANAH,DAERAH_TANAH',
      'outStatistics': jsonEncode([
        {
          'statisticType': 'count',
          'onStatisticField': 'OBJECTID',
          'outStatisticFieldName': 'n',
        },
      ]),
    }, timeout: const Duration(seconds: 20));
    final byNegeri = <String, List<GroupStat>>{};
    for (final f in body['features'] as List) {
      final a = f['attributes'] as Map<String, dynamic>;
      final negeri = (a['NEGERI_TANAH'] as String?)?.trim() ?? '';
      final daerah = (a['DAERAH_TANAH'] as String?)?.trim() ?? '';
      if (negeri.isEmpty || daerah.isEmpty || daerah == 'TIADA DAERAH') {
        continue;
      }
      byNegeri
          .putIfAbsent(negeri, () => [])
          .add(GroupStat(daerah, (a['n'] as num?)?.toInt() ?? 0, 0));
    }
    for (final list in byNegeri.values) {
      list.sort((a, b) => b.count.compareTo(a.count));
    }
    return byNegeri;
  }

  /// Bounding box (WGS84) of the lots matching [where] as
  /// (south, west, north, east), or null when nothing matches.
  Future<(double, double, double, double)?> extentOf(String where) async {
    final body = await _query({
      'where': where,
      'returnExtentOnly': 'true',
      'outSR': '4326',
    }, timeout: const Duration(seconds: 15));
    final e = body['extent'] as Map<String, dynamic>?;
    final xmin = (e?['xmin'] as num?)?.toDouble();
    if (e == null || xmin == null || xmin.isNaN) return null;
    return (
      (e['ymin'] as num).toDouble(),
      xmin,
      (e['ymax'] as num).toDouble(),
      (e['xmax'] as num).toDouble(),
    );
  }

  Future<Map<String, dynamic>> _query(
    Map<String, String> params, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final uri = Uri.parse('$layerUrl/query')
        .replace(queryParameters: {...params, 'f': 'json'});
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode != 200) {
      throw Exception('Server returned HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['error'] != null) {
      throw Exception(body['error']['message'] ?? 'ArcGIS query failed');
    }
    return body;
  }

  /// Lot count and planted area grouped by [field], largest count first.
  Future<List<GroupStat>> groupBy(String field, {String where = '1=1'}) async {
    final body = await _query({
      'where': where,
      'groupByFieldsForStatistics': field,
      'outStatistics': jsonEncode([
        {
          'statisticType': 'count',
          'onStatisticField': 'OBJECTID',
          'outStatisticFieldName': 'n',
        },
        {
          'statisticType': 'sum',
          'onStatisticField': 'LUAS_TANAMAN',
          'outStatisticFieldName': 'luas',
        },
      ]),
    });
    final stats = (body['features'] as List).map((f) {
      final a = f['attributes'] as Map<String, dynamic>;
      final label = (a[field] as String?)?.trim();
      return GroupStat(
        (label == null || label.isEmpty) ? 'Tiada data' : label,
        (a['n'] as num?)?.toInt() ?? 0,
        (a['luas'] as num?)?.toDouble() ?? 0,
      );
    }).toList()..sort((a, b) => b.count.compareTo(a.count));
    return stats;
  }

  /// The lot at a map point (WGS84), optionally limited to one state,
  /// district or mukim (see [whereForArea]).
  Future<LotRecord?> lotAt(
    double lat,
    double lng, {
    String? negeri,
    String? daerah,
    String? mukim,
  }) async {
    final body = await _query({
      'where': whereForArea(negeri, daerah, mukim),
      'geometry': '$lng,$lat',
      'geometryType': 'esriGeometryPoint',
      'inSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': LotRecord.fields,
      'returnGeometry': 'false',
      'resultRecordCount': '1',
    });
    final features = body['features'] as List;
    return features.isEmpty
        ? null
        : LotRecord.fromAttributes(features.first['attributes']);
  }

  /// MapServer for the same layer; it draws lots server-side as images.
  static const String mapServerUrl =
      'https://gisserver.risda.gov.my/arcgis/rest/services/'
      'Lot_Getah_Satu_Malaysia/MapServer';

  /// URL for a transparent PNG of the lots inside a Web Mercator (EPSG:3857)
  /// box, coloured by STATUS_TOREHAN with the app's status colours and
  /// limited to [negeri] (and [daerah], [mukim]) when given; see
  /// [whereForArea].
  static String exportUrl({
    required double xmin,
    required double ymin,
    required double xmax,
    required double ymax,
    required int size,
    String? negeri,
    String? daerah,
    String? mukim,

    /// Drawing resolution. Raise it with [size] (e.g. 192 for a 2x image) so
    /// outlines keep their on-screen thickness on high-density screens.
    int dpi = 96,
  }) {
    Map<String, Object> fill(List<int> rgb) => {
      'type': 'esriSFS',
      'style': 'esriSFSSolid',
      'color': [...rgb, 200],
      'outline': {
        'type': 'esriSLS',
        'style': 'esriSLSSolid',
        'color': [255, 255, 255, 220],
        'width': 0.5,
      },
    };
    final layer = {
      'id': 0,
      'source': {'type': 'mapLayer', 'mapLayerId': 0},
      'definitionExpression': whereForArea(negeri, daerah, mukim),
      'drawingInfo': {
        'renderer': {
          'type': 'uniqueValue',
          'field1': 'STATUS_TOREHAN',
          'defaultSymbol': fill([168, 156, 138]),
          'uniqueValueInfos': [
            {
              'value': 'Bertoreh',
              'symbol': fill([63, 143, 70]),
            },
            {
              'value': 'Tidak Bertoreh',
              'symbol': fill([230, 126, 26]),
            },
            {
              'value': 'Getah Muda',
              'symbol': fill([184, 134, 43]),
            },
          ],
        },
      },
    };
    return Uri.parse('$mapServerUrl/export')
        .replace(
          queryParameters: {
            'bbox': '$xmin,$ymin,$xmax,$ymax',
            'bboxSR': '3857',
            'imageSR': '3857',
            'size': '$size,$size',
            'dpi': '$dpi',
            'format': 'png32',
            'transparent': 'true',
            'dynamicLayers': jsonEncode([layer]),
            'f': 'image',
          },
        )
        .toString();
  }

  /// Where clause for incomplete lots of the given [filter] whose owner
  /// name, No. KP or no. permohonan contains [query] (case-insensitive).
  /// An empty [query] matches every such lot.
  ///
  /// No. KP is stored as 12 bare digits, so dashes and spaces typed in the
  /// query (e.g. "670428-03-5558") are ignored for that field.
  ///
  /// [mukim] narrows to lots whose land mukim (MUKIM_TANAH) contains it.
  /// [lot] must match the lot number exactly; NO_LOT is stored both as
  /// "10318" and "LOT10318", so a bare number matches either form.
  static String incompleteWhereFor(
    String query, [
    IncompleteFilter filter = IncompleteFilter.semua,
    String mukim = '',
    String lot = '',
  ]) {
    String clean(String v) => v.trim().toUpperCase().replaceAll("'", "''");
    final term = clean(query);
    final parts = [filter.where];
    if (term.isNotEmpty) {
      final digits = term.replaceAll(RegExp(r'[\s-]'), '');
      final matches = [
        "UPPER(NAMA) LIKE '%$term%'",
        "UPPER(no_permohonan_esrm) LIKE '%$term%'",
        if (RegExp(r'^\d+$').hasMatch(digits)) "NOKP LIKE '%$digits%'",
      ];
      parts.add('(${matches.join(' OR ')})');
    }
    final m = clean(mukim);
    if (m.isNotEmpty) parts.add("UPPER(MUKIM_TANAH) LIKE '%$m%'");
    if (lot.trim().isNotEmpty) parts.add(lotNumberWhere(lot));
    return parts.join(' AND ');
  }

  /// Incomplete lots matching [name] and [filter], sorted by name, up to
  /// [limit].
  Future<List<LotRecord>> searchIncomplete(
    String name, {
    IncompleteFilter filter = IncompleteFilter.semua,
    String mukim = '',
    String lot = '',
    int limit = 50,
  }) async {
    final body = await _query({
      'where': incompleteWhereFor(name, filter, mukim, lot),
      'outFields': LotRecord.fields,
      'orderByFields': 'NAMA',
      'resultRecordCount': '$limit',
      'returnGeometry': 'false',
    });
    return (body['features'] as List)
        .map((f) => LotRecord.fromAttributes(f['attributes']))
        .toList();
  }

  /// How many incomplete lots match [name] and [filter].
  Future<int> countIncomplete(
    String name, {
    IncompleteFilter filter = IncompleteFilter.semua,
    String mukim = '',
    String lot = '',
  }) async {
    final body = await _query({
      'where': incompleteWhereFor(name, filter, mukim, lot),
      'returnCountOnly': 'true',
    });
    return (body['count'] as num).toInt();
  }

  /// Writes the officer's entries for one lot, matched by GlobalID: a new
  /// STATUS_TOREHAN and/or TAHUN_TANAMAN (each with its source), plus the
  /// officer's name.
  ///
  /// Throws while [editsEnabled] is false so nothing can reach the server.
  Future<void> updateLot(
    String globalId, {
    String? status,
    int? tahunTanam,
    required String namaPengawai,
  }) async {
    if (!editsEnabled) {
      throw StateError('Edits are disabled (preview mode)');
    }
    final res = await _client
        .post(
          Uri.parse('$layerUrl/applyEdits'),
          body: buildLotUpdate(
            globalId,
            status: status,
            tahunTanam: tahunTanam,
            namaPengawai: namaPengawai,
          ),
        )
        .timeout(const Duration(seconds: 60));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final result = (body['updateResults'] as List?)?.firstOrNull;
    if (result == null || result['success'] != true) {
      throw Exception(
        body['error']?['message'] ??
            result?['error']?['description'] ??
            'Update failed',
      );
    }
  }

  /// The applyEdits form body for one lot. Only the fields given are sent.
  static Map<String, String> buildLotUpdate(
    String globalId, {
    String? status,
    int? tahunTanam,
    required String namaPengawai,
  }) => {
    'f': 'json',
    'useGlobalIds': 'true',
    'updates': jsonEncode([
      {
        'attributes': {
          'GlobalID': globalId,
          if (status != null) ...{
            'STATUS_TOREHAN': status,
            'SRC_STATUS_TOREHAN': editSource,
          },
          if (tahunTanam != null) ...{
            'TAHUN_TANAMAN': tahunTanam,
            'SRC_TAHUN_TANAMAN': editSource,
          },
          'NAMA_PENGAWAI': namaPengawai,
        },
      },
    ]),
  };
}
