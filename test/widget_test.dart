import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppskg_app/services/arcgis_service.dart';

LotRecord _lot(String nokp, {String? status = 'Bertoreh', int? tahun = 2010}) =>
    LotRecord(
      globalId: '{ABC}',
      lotId: 'KEKAL_1',
      nama: 'A',
      nokp: nokp,
      noLot: '1',
      mukim: 'MUKIM M',
      daerah: 'D',
      negeri: 'N',
      luas: 1,
      statusTorehan: status,
      statusTorehanSource: 'BPKG',
      namaPengawai: null,
      tahunTanam: tahun,
      noPermohonan: null,
    );

void main() {
  test('whereFor builds a state filter and escapes quotes', () {
    expect(ArcGisService.whereFor(null), '1=1');
    expect(ArcGisService.whereFor('KEDAH'), "NEGERI = 'KEDAH'");
    expect(ArcGisService.whereFor("O'X"), "NEGERI = 'O''X'");
  });

  test('map district filter uses the land state and district', () {
    expect(ArcGisService.whereForArea(null, null), '1=1');
    expect(ArcGisService.whereForArea('KEDAH', null), "NEGERI = 'KEDAH'");
    expect(
      ArcGisService.whereForArea('TERENGGANU', 'BESUT'),
      "NEGERI_TANAH = 'TERENGGANU' AND DAERAH_TANAH = 'BESUT'",
    );
  });

  test('formattedNokp shows the full IC with dashes', () {
    expect(_lot('800101-01-5523').formattedNokp, '800101-01-5523');
    expect(_lot('800101015523').formattedNokp, '800101-01-5523');
    expect(_lot('A1234567').formattedNokp, 'A1234567');
  });

  test('updateLot refuses to write while edits are disabled', () {
    expect(ArcGisService.editsEnabled, isFalse);
    expect(
      ArcGisService().updateLot(
        '{ABC}',
        status: 'Bertoreh',
        namaPengawai: 'ALI',
      ),
      throwsStateError,
    );
  });

  test('search lists lots missing a status or a valid planting year', () {
    const incomplete =
        "(STATUS_TOREHAN IS NULL OR STATUS_TOREHAN = '' "
        'OR TAHUN_TANAMAN IS NULL OR TAHUN_TANAMAN < 1960 '
        'OR TAHUN_TANAMAN > 2026)';
    expect(ArcGisService.incompleteWhereFor(''), incomplete);
    expect(
      ArcGisService.incompleteWhereFor(" ahmad's "),
      "$incomplete AND (UPPER(NAMA) LIKE '%AHMAD''S%' "
      "OR UPPER(no_permohonan_esrm) LIKE '%AHMAD''S%')",
    );
  });

  test('search also matches No. KP, ignoring dashes', () {
    final where = ArcGisService.incompleteWhereFor('670428-03-5558');
    expect(where, contains("NOKP LIKE '%670428035558%'"));
    expect(where, contains("UPPER(NAMA) LIKE '%670428-03-5558%'"));
  });

  test('search matches no. permohonan but not No. KP for non-digits', () {
    final where = ArcGisService.incompleteWhereFor('gm003358/2022');
    expect(where, contains("UPPER(no_permohonan_esrm) LIKE '%GM003358/2022%'"));
    expect(where, isNot(contains('NOKP')));
  });

  test('filters narrow to missing status or missing planting year', () {
    expect(
      ArcGisService.incompleteWhereFor('', IncompleteFilter.tiadaStatus),
      "(STATUS_TOREHAN IS NULL OR STATUS_TOREHAN = '')",
    );
    expect(
      ArcGisService.incompleteWhereFor('', IncompleteFilter.tiadaTahun),
      '(TAHUN_TANAMAN IS NULL OR TAHUN_TANAMAN < 1960 '
      'OR TAHUN_TANAMAN > 2026)',
    );
  });

  test('search can narrow by land mukim and exact lot number', () {
    final where = ArcGisService.incompleteWhereFor(
      '',
      IncompleteFilter.semua,
      'buloh kasap',
      'lot10318',
    );
    expect(where, contains("UPPER(MUKIM_TANAH) LIKE '%BULOH KASAP%'"));
    expect(
      where,
      contains(
        "(UPPER(NO_LOT) = '10318' OR UPPER(NO_LOT) = 'LOT10318' "
        "OR TANAH_LOT = '10318')",
      ),
    );
    expect(where, isNot(contains('UPPER(NAMA)')));
  });

  test('map area narrows from state to district to mukim', () {
    expect(ArcGisService.whereForArea('JOHOR', null), "NEGERI = 'JOHOR'");
    expect(
      ArcGisService.whereForArea('JOHOR', 'SEGAMAT', 'MUKIM BULOH KASAP'),
      "NEGERI_TANAH = 'JOHOR' AND DAERAH_TANAH = 'SEGAMAT' "
      "AND MUKIM_TANAH = 'MUKIM BULOH KASAP'",
    );
    expect(
      ArcGisService.lotNumberWhere('lot 2942'),
      "(UPPER(NO_LOT) = '2942' OR UPPER(NO_LOT) = 'LOT2942' "
      "OR TANAH_LOT = '2942')",
    );
  });

  test('jenis geran is the LOT_ID prefix', () {
    expect(_lot('1').jenisGeran, 'KEKAL');
  });

  test('planting year is needed when missing or outside 1960-2026', () {
    expect(_lot('1').needsTahunTanam, isFalse);
    expect(_lot('1', tahun: null).needsTahunTanam, isTrue);
    expect(_lot('1', tahun: 0).needsTahunTanam, isTrue);
    expect(_lot('1', tahun: 20019).needsTahunTanam, isTrue);
    expect(_lot('1', tahun: 1959).needsTahunTanam, isTrue);
    expect(_lot('1', tahun: 1960).needsTahunTanam, isFalse);
    expect(_lot('1', status: null).needsStatus, isTrue);
  });

  test('map tiles are filtered to the chosen state and coloured by status', () {
    final uri = Uri.parse(
      ArcGisService.exportUrl(
        xmin: 1,
        ymin: 2,
        xmax: 3,
        ymax: 4,
        size: 256,
        negeri: 'KEDAH',
      ),
    );
    expect(uri.path, endsWith('/MapServer/export'));
    expect(uri.queryParameters['bbox'], '1.0,2.0,3.0,4.0');
    expect(uri.queryParameters['bboxSR'], '3857');
    final layer =
        (jsonDecode(uri.queryParameters['dynamicLayers']!) as List).single;
    expect(layer['definitionExpression'], "NEGERI = 'KEDAH'");
    expect(layer['drawingInfo']['renderer']['field1'], 'STATUS_TOREHAN');
  });

  test('officers can only choose Bertoreh or Tidak Bertoreh', () {
    expect(ArcGisService.statusTorehanOptions, ['Bertoreh', 'Tidak Bertoreh']);
  });

  test('update matches by GlobalID and records source and officer', () {
    final body = ArcGisService.buildLotUpdate(
      '{ABC}',
      status: 'Tidak Bertoreh',
      tahunTanam: 2015,
      namaPengawai: 'ALI BIN ABU',
    );
    expect(body['useGlobalIds'], 'true');
    final attrs = (jsonDecode(body['updates']!) as List).single['attributes'];
    expect(attrs, {
      'GlobalID': '{ABC}',
      'STATUS_TOREHAN': 'Tidak Bertoreh',
      'SRC_STATUS_TOREHAN': ArcGisService.editSource,
      'TAHUN_TANAMAN': 2015,
      'SRC_TAHUN_TANAMAN': ArcGisService.editSource,
      'NAMA_PENGAWAI': 'ALI BIN ABU',
    });
  });

  test('update only sends the fields that were filled in', () {
    final body = ArcGisService.buildLotUpdate(
      '{ABC}',
      tahunTanam: 2001,
      namaPengawai: 'ALI',
    );
    final attrs = (jsonDecode(body['updates']!) as List).single['attributes'];
    expect(attrs, {
      'GlobalID': '{ABC}',
      'TAHUN_TANAMAN': 2001,
      'SRC_TAHUN_TANAMAN': ArcGisService.editSource,
      'NAMA_PENGAWAI': 'ALI',
    });
  });
}
