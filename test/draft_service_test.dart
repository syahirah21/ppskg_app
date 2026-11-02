import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ppskg_app/services/arcgis_service.dart';
import 'package:ppskg_app/services/draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

LotRecord _lot(String id) => LotRecord(
  globalId: id,
  lotId: 'KEKAL_1',
  nama: 'PEKEBUN $id',
  nokp: '800101015523',
  noLot: '1',
  mukim: 'M',
  daerah: 'D',
  negeri: 'N',
  luas: 1.25,
  statusTorehan: null,
  statusTorehanSource: null,
  namaPengawai: null,
  tahunTanam: 20019,
  noPermohonan: 'GM1/2022',
);

const _edit = LotEdit(status: 'Bertoreh', tahunTanam: 2015, pengawai: 'ALI');

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DraftService.drafts.value = {};
    DraftService.history.value = {};
    DraftService.online.value = true;
    await DraftService.init();
  });

  test('a lot survives being kept on the device', () {
    final lot = _lot('{A}');
    final back = LotRecord.fromAttributes(lot.toAttributes());
    expect(back.globalId, '{A}');
    expect(back.nama, 'PEKEBUN {A}');
    expect(back.luas, 1.25);
    expect(back.statusTorehan, isNull);
    expect(back.tahunTanam, 20019);
    expect(back.noPermohonan, 'GM1/2022');
  });

  test('a draft only completes the lot once everything is filled in', () {
    final lot = _lot('{A}');
    expect(
      const LotEdit(status: 'Bertoreh', pengawai: 'ALI').completes(lot),
      isFalse,
    );
    expect(_edit.completes(lot), isTrue);
  });

  test('drafts are saved and read back after a restart', () async {
    await DraftService.saveDraft(
      _lot('{A}'),
      const LotEdit(status: 'Bertoreh', pengawai: 'ALI'),
    );
    DraftService.drafts.value = {};
    await DraftService.init();
    final d = DraftService.drafts.value['{A}']!;
    expect(d.state, DraftState.draf);
    expect(d.edit.status, 'Bertoreh');
    expect(d.lot.nama, 'PEKEBUN {A}');
  });

  test('without internet an edit waits, then goes when back online', () async {
    var offline = true;
    final sent = <String>[];
    DraftService.send = (d) async {
      if (offline) throw http.ClientException('No internet');
      sent.add(d.lot.globalId);
    };

    expect(await DraftService.submit(_lot('{A}'), _edit), SubmitResult.queued);
    expect(DraftService.online.value, isFalse);
    expect(DraftService.queuedCount, 1);

    offline = false;
    expect(await DraftService.sync(), 1);
    expect(sent, ['{A}']);
    expect(DraftService.drafts.value, isEmpty);
    expect(DraftService.online.value, isTrue);
    // Kept in the history so it can be checked or corrected later.
    final r = DraftService.history.value['{A}']!;
    expect(r.latest.edit.summary, 'Bertoreh · Tahun 2015');
    expect(r.corrected, isFalse);
  });

  test('a refused edit goes back to being a draft with the reason', () async {
    DraftService.send = (d) async => throw Exception('Lot dikunci');
    expect(await DraftService.submit(_lot('{A}'), _edit), SubmitResult.failed);
    final d = DraftService.drafts.value['{A}']!;
    expect(d.state, DraftState.draf);
    expect(d.error, contains('Lot dikunci'));
  });

  test('a correction keeps every version and the original lot', () async {
    DraftService.send = (d) async {};
    final lot = _lot('{A}');
    await DraftService.submit(lot, _edit);
    await DraftService.submit(
      lot,
      const LotEdit(
        status: 'Tidak Bertoreh',
        tahunTanam: 2015,
        pengawai: 'ABU',
      ),
    );
    final r = DraftService.history.value['{A}']!;
    expect(r.corrected, isTrue);
    expect(
      [for (final v in r.versions) v.edit.status],
      ['Bertoreh', 'Tidak Bertoreh'],
    );
    expect(r.lot.statusTorehan, isNull);

    // ...and survives a restart.
    DraftService.history.value = {};
    await DraftService.init();
    expect(DraftService.history.value['{A}']!.versions, hasLength(2));
  });
}
