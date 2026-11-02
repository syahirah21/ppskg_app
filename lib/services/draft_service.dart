import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'arcgis_service.dart';

/// What an officer entered for one lot: a status and/or a planting year
/// (only the ones that were missing), plus their name.
class LotEdit {
  final String? status;
  final int? tahunTanam;
  final String pengawai;

  const LotEdit({this.status, this.tahunTanam, required this.pengawai});

  /// E.g. "Bertoreh · Tahun 2015".
  String get summary =>
      [?status, if (tahunTanam != null) 'Tahun $tahunTanam'].join(' · ');

  /// Whether this fills in everything [lot] is missing, so it can be sent.
  bool completes(LotRecord lot) =>
      (!lot.needsStatus || status != null) &&
      (!lot.needsTahunTanam || LotRecord.validTahunTanam(tahunTanam));

  Map<String, dynamic> toJson() => {
    'status': status,
    'tahunTanam': tahunTanam,
    'pengawai': pengawai,
  };

  factory LotEdit.fromJson(Map<String, dynamic> j) => LotEdit(
    status: j['status'] as String?,
    tahunTanam: (j['tahunTanam'] as num?)?.toInt(),
    pengawai: j['pengawai'] as String? ?? '',
  );
}

enum DraftState {
  /// Saved on the device by the officer; not sent until they press Hantar.
  draf,

  /// Hantar was pressed but there was no internet; sent automatically once
  /// the connection is back.
  menunggu,
}

/// An edit kept on this device, with a copy of the lot so it can be listed
/// and reopened without internet.
class LotDraft {
  final LotRecord lot;
  final LotEdit edit;
  final DraftState state;
  final DateTime updatedAt;

  /// Why the server refused the last send, if it did. The draft goes back
  /// to [DraftState.draf] so the officer can check it.
  final String? error;

  const LotDraft({
    required this.lot,
    required this.edit,
    required this.state,
    required this.updatedAt,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'lot': lot.toAttributes(),
    'edit': edit.toJson(),
    'state': state.name,
    'updatedAt': updatedAt.toIso8601String(),
    'error': error,
  };

  factory LotDraft.fromJson(Map<String, dynamic> j) => LotDraft(
    lot: LotRecord.fromAttributes(j['lot'] as Map<String, dynamic>),
    edit: LotEdit.fromJson(j['edit'] as Map<String, dynamic>),
    state: DraftState.values.byName(j['state'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    error: j['error'] as String?,
  );
}

/// One version of a lot's edit that reached the server.
class SentVersion {
  final LotEdit edit;
  final DateTime sentAt;

  const SentVersion(this.edit, this.sentAt);

  Map<String, dynamic> toJson() => {
    ...edit.toJson(),
    'sentAt': sentAt.toIso8601String(),
  };

  factory SentVersion.fromJson(Map<String, dynamic> j) =>
      SentVersion(LotEdit.fromJson(j), DateTime.parse(j['sentAt'] as String));
}

/// Everything sent from this device for one lot, oldest first, so officers
/// can see what changed and correct a mistake later, even after the lot has
/// left the incomplete list.
class SentRecord {
  /// The lot as it was before the first edit (so the form asks the same
  /// questions when correcting).
  final LotRecord lot;
  final List<SentVersion> versions;

  const SentRecord(this.lot, this.versions);

  SentVersion get latest => versions.last;

  /// Whether a value was sent more than once (a correction).
  bool get corrected => versions.length > 1;

  Map<String, dynamic> toJson() => {
    'lot': lot.toAttributes(),
    'versions': [for (final v in versions) v.toJson()],
  };

  factory SentRecord.fromJson(Map<String, dynamic> j) =>
      SentRecord(LotRecord.fromAttributes(j['lot'] as Map<String, dynamic>), [
        for (final v in j['versions'] as List)
          SentVersion.fromJson(v as Map<String, dynamic>),
      ]);
}

/// What happened when the officer pressed Hantar.
enum SubmitResult { sent, queued, failed }

/// Keeps the officers' Cari & Kemaskini work on the device (phone storage in
/// the app, browser storage on the website) so nothing is lost without
/// internet, and sends queued edits once the connection is back.
///
/// Sending is retried every [retryEvery] while anything is queued, when the
/// app is reopened, and after every successful search.
class DraftService {
  DraftService._();

  static const _draftsKey = 'drafts_v1';
  static const _historyKey = 'sent_history_v1';

  /// Lots kept in [history]; the oldest are dropped beyond this.
  static const maxHistory = 500;
  static const retryEvery = Duration(seconds: 30);

  /// Drafts and queued edits by lot GlobalID.
  static final drafts = ValueNotifier<Map<String, LotDraft>>({});

  /// Lots sent from this device by GlobalID, oldest first, with every
  /// version sent (see [SentRecord]).
  static final history = ValueNotifier<Map<String, SentRecord>>({});

  /// False after a request failed for lack of internet; true again after
  /// one succeeds.
  static final online = ValueNotifier<bool>(true);

  static final syncing = ValueNotifier<bool>(false);

  // Sync, so listeners hear about a send before submit() returns.
  static final _sent = StreamController<LotDraft>.broadcast(sync: true);

  /// Each edit as it reaches the server, so screens can update their lists.
  static Stream<LotDraft> get sent => _sent.stream;

  /// Sends one edit. Replaced in tests.
  @visibleForTesting
  static Future<void> Function(LotDraft) send = _send;

  static final _service = ArcGisService();
  static SharedPreferences? _prefs;
  static Timer? _timer;

  static int get queuedCount =>
      drafts.value.values.where((d) => d.state == DraftState.menunggu).length;

  /// Loads what was kept on the device. Call once before the app starts.
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      // Storage blocked (e.g. some private browser windows): drafts then
      // only last until the page is closed.
      debugPrint('Draft storage unavailable: $e');
      return;
    }
    drafts.value = {
      for (final d in _readList(_draftsKey).map(LotDraft.fromJson))
        d.lot.globalId: d,
    };
    history.value = {
      for (final r in _readList(_historyKey).map(SentRecord.fromJson))
        r.lot.globalId: r,
    };
    _timer ??= Timer.periodic(retryEvery, (_) {
      if (queuedCount > 0) sync();
    });
    if (queuedCount > 0) unawaited(sync());
  }

  static List<Map<String, dynamic>> _readList(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Ignoring unreadable $key: $e');
      return [];
    }
  }

  static Future<void> _store() async {
    await _prefs?.setString(
      _draftsKey,
      jsonEncode([for (final d in drafts.value.values) d.toJson()]),
    );
    await _prefs?.setString(
      _historyKey,
      jsonEncode([for (final r in history.value.values) r.toJson()]),
    );
  }

  static Future<void> _put(LotDraft d) {
    drafts.value = {...drafts.value, d.lot.globalId: d};
    return _store();
  }

  /// Keeps [edit] on the device without sending it (Simpan draf).
  static Future<void> saveDraft(LotRecord lot, LotEdit edit) => _put(
    LotDraft(
      lot: lot,
      edit: edit,
      state: DraftState.draf,
      updatedAt: DateTime.now(),
    ),
  );

  static Future<void> deleteDraft(String globalId) {
    drafts.value = {...drafts.value}..remove(globalId);
    return _store();
  }

  /// Hantar: queues [edit] and tries to send it straight away. Without
  /// internet it stays queued and goes out automatically later.
  static Future<SubmitResult> submit(LotRecord lot, LotEdit edit) async {
    await _put(
      LotDraft(
        lot: lot,
        edit: edit,
        state: DraftState.menunggu,
        updatedAt: DateTime.now(),
      ),
    );
    await sync();
    final left = drafts.value[lot.globalId];
    if (left == null) return SubmitResult.sent;
    return left.state == DraftState.menunggu
        ? SubmitResult.queued
        : SubmitResult.failed;
  }

  /// Sends every queued edit, oldest first. Stops at the first network
  /// failure (still offline); a refusal from the server turns that one back
  /// into a draft with the reason. Returns how many were sent.
  static Future<int> sync() async {
    if (syncing.value) return 0;
    syncing.value = true;
    var count = 0;
    try {
      final queue =
          drafts.value.values
              .where((d) => d.state == DraftState.menunggu)
              .toList()
            ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final d in queue) {
        try {
          await send(d);
        } catch (e) {
          if (isNetworkError(e)) {
            online.value = false;
            break;
          }
          await _put(
            LotDraft(
              lot: d.lot,
              edit: d.edit,
              state: DraftState.draf,
              updatedAt: d.updatedAt,
              error: '$e',
            ),
          );
          continue;
        }
        online.value = true;
        count++;
        drafts.value = {...drafts.value}..remove(d.lot.globalId);
        _addToHistory(d);
        await _store();
        _sent.add(d);
      }
    } finally {
      syncing.value = false;
    }
    return count;
  }

  /// Records a sent edit, moving the lot to the end (newest).
  static void _addToHistory(LotDraft d) {
    final id = d.lot.globalId;
    final before = history.value[id];
    final all = {...history.value}..remove(id);
    all[id] = SentRecord(before?.lot ?? d.lot, [
      ...?before?.versions,
      SentVersion(d.edit, DateTime.now()),
    ]);
    while (all.length > maxHistory) {
      all.remove(all.keys.first);
    }
    history.value = all;
  }

  static Future<void> _send(LotDraft d) async {
    if (ArcGisService.editsEnabled) {
      await _service.updateLot(
        d.lot.globalId,
        status: d.edit.status,
        tahunTanam: d.edit.tahunTanam,
        namaPengawai: d.edit.pengawai,
      );
    } else {
      // Preview: nothing is written; only check the server is reachable so
      // the offline → online flow can be tried out.
      await _service.ping();
    }
  }

  /// No connection, or the server didn't answer in time (as opposed to the
  /// server answering with an error).
  static bool isNetworkError(Object e) =>
      e is http.ClientException || e is TimeoutException;

  /// A short message for officers instead of the raw error (which holds the
  /// whole request URL).
  static String describeError(Object e) {
    // Several requests at once (`.wait`) wrap their errors, so look inside.
    final wrappedNetwork =
        e is ParallelWaitError &&
        RegExp('ClientException|TimeoutException').hasMatch('$e');
    if (isNetworkError(e) || wrappedNetwork) {
      return 'Tiada sambungan internet, atau pelayan RISDA tidak dapat '
          'dihubungi. Semak sambungan anda dan cuba lagi.';
    }
    final text = '$e'.replaceFirst('Exception: ', '');
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  /// Updates [online] from the outcome of any other request.
  static void reportRequest({Object? error}) {
    if (error == null) {
      online.value = true;
      if (queuedCount > 0) unawaited(sync());
    } else if (isNetworkError(error)) {
      online.value = false;
    }
  }
}
