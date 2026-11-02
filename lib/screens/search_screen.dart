import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/arcgis_service.dart';
import '../services/auth_service.dart';
import '../services/draft_service.dart';
import '../services/search_cache.dart';
import '../theme.dart';
import '../widgets/theme_toggle.dart';

/// Lists lots that are missing a Status Torehan or a valid Tahun Tanam so
/// officers can fill them in. The edit form only asks for what's missing.
///
/// Work is kept on the device by [DraftService]: officers can save a draft
/// and finish it later, and anything sent without internet waits in a queue
/// and goes out automatically. The last lists are kept too ([SearchCache]),
/// so the screen still works offline.
///
/// While [ArcGisService.editsEnabled] is false, sending only marks the lot
/// in this screen (it stays listed, since the layer still has no status) and
/// nothing is written to the server. Once edits are live, a sent lot drops
/// off the list because it now has data.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _minChars = 3;
  static const _limit = 50;

  final _service = ArcGisService();
  final _controller = TextEditingController();
  final _mukim = TextEditingController();
  final _lot = TextEditingController();

  List<LotRecord>? _results;

  /// Which kind of missing data the list shows.
  IncompleteFilter _filter = IncompleteFilter.semua;

  /// How many lots match the current name search under each filter, for
  /// the chip badges.
  Map<IncompleteFilter, int> _counts = {};

  int? get _total => _counts[_filter];
  String? _error;
  bool _loading = false;

  /// Showing a list kept on this device (drafts or sent lots) instead of
  /// the server list; null for the server list.
  _LocalView? _local;

  /// When the list on screen was saved, if it came from [SearchCache]
  /// because there was no internet.
  DateTime? _cachedAt;

  /// The lot being sent from the edit form, which shows its own message.
  String? _submitting;

  late final StreamSubscription<LotDraft> _sentSub;

  @override
  void initState() {
    super.initState();
    _sentSub = DraftService.sent.listen(_onSent);
    // Show the to-do list straight away, before any name is typed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  /// A queued edit reached the server.
  void _onSent(LotDraft d) {
    if (!mounted) return;
    if (ArcGisService.editsEnabled &&
        (_results?.any((r) => r.globalId == d.lot.globalId) ?? false)) {
      _markDone(d.lot);
    }
    if (d.lot.globalId != _submitting) {
      _toast('Draf telah dihantar: ${d.lot.nama}');
    }
  }

  @override
  void dispose() {
    _sentSub.cancel();
    _controller.dispose();
    _mukim.dispose();
    _lot.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final name = _controller.text.trim();
    final mukim = _mukim.text.trim();
    final lot = _lot.text.trim();
    if (name.isNotEmpty && name.length < _minChars) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan sekurang-kurangnya 3 aksara')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _local = null;
    });
    final cacheKey = '${_filter.name}|$name|$mukim|$lot';
    try {
      // Future.wait (not .wait) passes the first error through unwrapped,
      // so a lost connection can be told apart from other errors.
      final all = await Future.wait<Object>([
        _service.searchIncomplete(
          name,
          filter: _filter,
          mukim: mukim,
          lot: lot,
          limit: _limit,
        ),
        for (final f in IncompleteFilter.values)
          _service.countIncomplete(name, filter: f, mukim: mukim, lot: lot),
      ]);
      final results = all.first as List<LotRecord>;
      final counts = all.skip(1).cast<int>().toList();
      setState(() {
        _results = results;
        _counts = {
          for (final (i, f) in IncompleteFilter.values.indexed) f: counts[i],
        };
        _cachedAt = null;
      });
      DraftService.reportRequest();
      unawaited(SearchCache.put(cacheKey, results, _counts));
    } catch (e) {
      DraftService.reportRequest(error: e);
      // No internet: fall back to the list saved the last time it loaded.
      final cached = DraftService.isNetworkError(e)
          ? await SearchCache.get(cacheKey)
          : null;
      if (!mounted) return;
      setState(() {
        if (cached case (final results, final counts, final savedAt)) {
          _results = results;
          _counts = counts;
          _cachedAt = savedAt;
        } else {
          _error = DraftService.isNetworkError(e)
              ? 'Tiada sambungan internet.\n'
                    'Senarai ini belum pernah dibuka di peranti ini. '
                    'Draf anda masih boleh dibuka di tab Draf.'
              : DraftService.describeError(e);
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Takes a completed lot off the list and out of the chip counts it was
  /// part of ([lot] is the record before the edit).
  void _markDone(LotRecord lot) {
    setState(() {
      _results = [
        for (final r in _results!)
          if (r.globalId != lot.globalId) r,
      ];
      _counts = {
        for (final MapEntry(key: f, value: n) in _counts.entries)
          f: switch (f) {
            IncompleteFilter.semua => n - 1,
            IncompleteFilter.tiadaStatus => lot.needsStatus ? n - 1 : n,
            IncompleteFilter.tiadaTahun => lot.needsTahunTanam ? n - 1 : n,
          },
      };
    });
  }

  void _setFilter(IncompleteFilter filter) {
    if ((filter == _filter && _local == null) || _loading) return;
    setState(() => _filter = filter);
    _search();
  }

  Future<void> _openLot(LotRecord listed) async {
    final sent = DraftService.history.value[listed.globalId];
    // Once sent the layer has values, so correct against the lot as it was
    // before; the form then asks the same questions as the first time.
    final lot = sent?.lot ?? listed;
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditDialog(
        lot: lot,
        draft: DraftService.drafts.value[lot.globalId],
        sent: sent,
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case (action: _EditAction.saveDraft, :final edit?):
        await DraftService.saveDraft(lot, edit);
        _toast('Disimpan sebagai draf di peranti ini');
      case (action: _EditAction.deleteDraft, edit: _):
        await DraftService.deleteDraft(lot.globalId);
        _toast('Draf dipadam');
      case (action: _EditAction.submit, :final edit?):
        _submitting = lot.globalId;
        final outcome = await DraftService.submit(lot, edit);
        _submitting = null;
        if (!mounted) return;
        _toast(switch (outcome) {
          SubmitResult.sent =>
            sent == null ? 'Data berjaya disimpan' : 'Pembetulan disimpan',
          SubmitResult.queued =>
            'Tiada internet. Disimpan di peranti dan akan dihantar '
                'automatik apabila ada sambungan.',
          SubmitResult.failed =>
            'Gagal dihantar: '
                '${DraftService.drafts.value[lot.globalId]?.error}. '
                'Disimpan sebagai draf.',
        });
      case (action: _, edit: null):
        break;
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Redraw whenever drafts change or are sent, including in the background.
    listenable: Listenable.merge([
      DraftService.drafts,
      DraftService.history,
      DraftService.online,
      DraftService.syncing,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final desktop = isDesktop(context);
    final mainSearch = SizedBox(
      height: 46,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (_) => _search(),
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Nama, no. KP atau no. permohonan',
          fillColor: theme.colorScheme.surface,
          contentPadding: EdgeInsets.zero,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward, size: 20),
            onPressed: _search,
          ),
        ),
      ),
    );
    final mukimField = _SmallSearchField(
      controller: _mukim,
      hint: 'Mukim',
      icon: Icons.place_outlined,
      onSubmitted: _search,
      height: desktop ? 46 : 40,
    );
    final lotField = _SmallSearchField(
      controller: _lot,
      hint: 'No. Lot',
      icon: Icons.tag,
      onSubmitted: _search,
      height: desktop ? 46 : 40,
    );
    final serverChips = [
      for (final f in IncompleteFilter.values)
        _FilterChip(
          label: f.label,
          count: _counts[f],
          selected: _local == null && f == _filter,
          onTap: () => _setFilter(f),
        ),
    ];
    // Lists kept on this device, so they work without internet: unsent
    // drafts, and everything sent (to check or correct).
    final localChips = [
      _FilterChip(
        label: 'Draf',
        icon: Icons.edit_note,
        count: DraftService.drafts.value.length,
        selected: _local == _LocalView.drafts,
        onTap: () => setState(() => _local = _LocalView.drafts),
      ),
      _FilterChip(
        label: 'Dikemaskini',
        icon: Icons.history,
        count: DraftService.history.value.length,
        selected: _local == _LocalView.history,
        onTap: () => setState(() => _local = _LocalView.history),
      ),
    ];
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phones get the light/dark button here; desktop has it in the
        // sidebar.
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cari & Kemaskini',
                    style:
                        (desktop
                                ? theme.textTheme.headlineSmall
                                : theme.textTheme.titleLarge)
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                  Text(
                    'Lot yang belum lengkap: status torehan atau tahun tanam',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            if (!desktop) ...[
              const SizedBox(width: 8),
              const ThemeModeButton(),
            ],
          ],
        ),
        SizedBox(height: desktop ? 20 : 12),
        // Desktop puts all three search boxes on one line.
        if (desktop)
          Row(
            children: [
              Expanded(flex: 5, child: mainSearch),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: mukimField),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: lotField),
            ],
          )
        else ...[
          mainSearch,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(flex: 3, child: mukimField),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: lotField),
            ],
          ),
        ],
        SizedBox(height: desktop ? 14 : 10),
        // One row; on phones it scrolls sideways when the chips don't fit.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          // Chips run on to the screen edge, hinting there are more.
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (i, chip) in [...serverChips, ...localChips].indexed)
                Padding(
                  // A wider gap before the lists kept on the device.
                  padding: EdgeInsets.only(
                    left: i == 0
                        ? 0
                        : i == serverChips.length
                        ? (desktop ? 24 : 16)
                        : 8,
                  ),
                  child: chip,
                ),
            ],
          ),
        ),
      ],
    );
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(gradient: headerGradient),
          padding: desktop
              ? const EdgeInsets.fromLTRB(32, 28, 32, 22)
              : EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.paddingOf(context).top + 12,
                  16,
                  14,
                ),
          child: desktop ? desktopContent(header) : header,
        ),
        _SyncBanner(
          cachedAt: _cachedAt,
          desktop: desktop,
          onRetry: () {
            DraftService.sync();
            if (_cachedAt != null || _error != null) _search();
          },
        ),
        Expanded(
          child: switch (_local) {
            _LocalView.drafts => _buildDrafts(theme, desktop),
            _LocalView.history => _buildHistory(theme, desktop),
            null => _buildResults(theme, desktop),
          },
        ),
      ],
    );
  }

  /// What the summary line calls the listed lots, e.g. "tiada tahun tanam".
  String _summaryLabel() => switch (_filter) {
    IncompleteFilter.semua => 'belum lengkap',
    IncompleteFilter.tiadaStatus => 'tiada status torehan',
    IncompleteFilter.tiadaTahun => 'tiada tahun tanam',
  };

  Widget _buildResults(ThemeData theme, bool desktop) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off,
        text: 'Gagal memuatkan senarai:\n$_error',
      );
    }
    final results = _results;
    if (results == null) return const SizedBox();
    final total = _total ?? results.length;
    final summary = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total > results.length
                  ? '${fmtInt(total)} lot ${_summaryLabel()} · '
                        'menunjukkan ${results.length}'
                  : '${fmtInt(total)} lot ${_summaryLabel()}',
              style: theme.textTheme.bodySmall?.copyWith(color: smartMuted),
            ),
          ),
        ],
      ),
    );
    if (results.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: summary,
          ),
          Expanded(
            child: _EmptyState(
              icon: total == 0 ? Icons.task_alt : Icons.refresh,
              text: total == 0
                  ? 'Tiada lot yang belum lengkap untuk carian ini'
                  : 'Semua lot dalam senarai ini telah dikemaskini.\n'
                        'Cari semula untuk memuatkan lagi.',
            ),
          ),
        ],
      );
    }
    if (desktop) {
      // One table-like card: column headings, then a row per lot.
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
        children: [
          desktopContent(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                Card(
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      const _LotTableHeader(),
                      for (final lot in results) ...[
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        _row(lot, wide: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        summary,
        for (final lot in results)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: _row(lot),
          ),
      ],
    );
  }

  Widget _row(LotRecord lot, {bool wide = false}) => _LotRow(
    lot: lot,
    draft: DraftService.drafts.value[lot.globalId],
    sent: DraftService.history.value[lot.globalId],
    onTap: () => _openLot(lot),
    wide: wide,
  );

  /// The drafts and queued edits kept on this device, newest first. Uses
  /// the copy of each lot saved with it, so it works offline.
  Widget _buildDrafts(ThemeData theme, bool desktop) {
    final drafts = DraftService.drafts.value.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final queued = DraftService.queuedCount;
    if (drafts.isEmpty) {
      return const _EmptyState(
        icon: Icons.edit_note,
        text:
            'Tiada draf.\nTekan "Simpan draf" pada mana-mana lot untuk '
            'menyimpan kerja dan sambung kemudian, walaupun tanpa internet.',
      );
    }
    return _buildLocalList(
      theme,
      desktop,
      [for (final d in drafts) d.lot],
      [
        '${drafts.length} draf di peranti ini',
        if (queued > 0) '$queued menunggu untuk dihantar',
      ].join(' · '),
    );
  }

  /// Lots sent from this device, newest first, so a wrong entry can be
  /// found and corrected even after the lot left the incomplete list.
  Widget _buildHistory(ThemeData theme, bool desktop) {
    final sent = DraftService.history.value.values.toList()
      ..sort((a, b) => b.latest.sentAt.compareTo(a.latest.sentAt));
    if (sent.isEmpty) {
      return const _EmptyState(
        icon: Icons.history,
        text:
            'Belum ada lot dikemaskini dari peranti ini.\n'
            'Lot yang dihantar akan disenaraikan di sini dan boleh '
            'dibetulkan jika tersalah isi.',
      );
    }
    final corrected = sent.where((r) => r.corrected).length;
    return _buildLocalList(
      theme,
      desktop,
      [for (final r in sent) r.lot],
      [
        '${sent.length} lot dikemaskini dari peranti ini',
        if (corrected > 0) '$corrected dibetulkan',
        'Tekan lot untuk membetulkan',
      ].join(' · '),
    );
  }

  /// A list of lots kept on this device, in the same style as the results.
  Widget _buildLocalList(
    ThemeData theme,
    bool desktop,
    List<LotRecord> lots,
    String summaryText,
  ) {
    final summary = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        summaryText,
        style: theme.textTheme.bodySmall?.copyWith(color: smartMuted),
      ),
    );
    if (desktop) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
        children: [
          desktopContent(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                Card(
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      const _LotTableHeader(),
                      for (final lot in lots) ...[
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        _row(lot, wide: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        summary,
        for (final lot in lots)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: _row(lot),
          ),
      ],
    );
  }
}

enum _LocalView { drafts, history }

/// "27/10 14:05", for when a draft or list was saved.
String _fmtTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

/// Strip under the header about the connection: offline (work is kept and
/// sent later), edits waiting to be sent, or an old saved list on screen.
/// Hidden when everything is up to date.
class _SyncBanner extends StatelessWidget {
  final DateTime? cachedAt;
  final bool desktop;
  final VoidCallback onRetry;

  const _SyncBanner({
    required this.cachedAt,
    required this.desktop,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = DraftService.online.value;
    final queued = DraftService.queuedCount;
    final cached = cachedAt;
    if (online && queued == 0 && cached == null) return const SizedBox();

    final (IconData icon, Color color, String text, String action) = !online
        ? (
            Icons.cloud_off,
            smartOrange,
            [
              'Tiada internet. Kerja anda disimpan di peranti dan dihantar '
                  'automatik apabila ada sambungan.',
              if (cached != null) 'Senarai disimpan ${_fmtTime(cached)}.',
            ].join(' '),
            'Cuba lagi',
          )
        : queued > 0
        ? (
            Icons.cloud_upload_outlined,
            smartBlue,
            '$queued kemaskini menunggu untuk dihantar.',
            'Hantar sekarang',
          )
        : (
            Icons.history,
            smartGoldDeep,
            'Memaparkan senarai yang disimpan ${_fmtTime(cached!)}.',
            'Muat semula',
          );
    final content = Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (DraftService.syncing.value)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: color,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(action),
          ),
      ],
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.4))),
      ),
      padding: EdgeInsets.symmetric(horizontal: desktop ? 32 : 14, vertical: 4),
      child: desktop ? desktopContent(content) : content,
    );
  }
}

/// Filter pill on the dark header: gold when selected, with the number of
/// matching lots (blank while loading).
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? smartInk : Colors.white;
    return Material(
      color: selected ? smartGold : Colors.white.withValues(alpha: 0.1),
      shape: StadiumBorder(
        side: BorderSide(color: selected ? smartGold : Colors.white24),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? smartInk.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count == null ? '…' : fmtInt(count!),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One compact search result: name, location and what's missing on the
/// left, planted area on the right. [draft] marks work kept on the device;
/// [sent] a lot already sent from it.
class _LotRow extends StatelessWidget {
  final LotRecord lot;
  final LotDraft? draft;
  final SentRecord? sent;
  final VoidCallback onTap;

  /// Desktop table row: one column per field instead of stacked lines.
  final bool wide;

  const _LotRow({
    required this.lot,
    this.draft,
    this.sent,
    required this.onTap,
    this.wide = false,
  });

  Widget _label(ThemeData theme, IconData icon, Color color, String text) =>
      Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );

  /// The draft or queued edit, else what was sent (and when), else what
  /// still needs filling in.
  Widget _status(ThemeData theme) {
    if (draft case final d?) {
      final what = d.edit.summary;
      return switch (d.state) {
        DraftState.menunggu => _label(
          theme,
          Icons.schedule,
          smartBlue,
          'Menunggu internet · $what',
        ),
        DraftState.draf when d.error != null => _label(
          theme,
          Icons.error_outline,
          smartOrange,
          'Gagal dihantar · semak draf',
        ),
        DraftState.draf => _label(
          theme,
          Icons.edit_note,
          smartGoldDeep,
          what.isEmpty ? 'Draf' : 'Draf · $what',
        ),
      };
    }
    if (sent case final r?) {
      final when = _fmtTime(r.latest.sentAt);
      return _label(
        theme,
        Icons.check_circle,
        smartGreen,
        '${r.latest.edit.summary} · '
        '${r.corrected ? 'dibetulkan $when' : when}',
      );
    }
    return Text(
      [
        if (lot.needsStatus) 'Tiada status torehan',
        if (lot.needsTahunTanam)
          lot.tahunTanam == null || lot.tahunTanam == 0
              ? 'Tiada tahun tanam'
              : 'Tahun tanam tidak sah',
      ].join(' · '),
      style: theme.textTheme.labelSmall?.copyWith(
        color: smartOrange,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (wide) {
      Widget cell(int flex, String text, {bool bold = false}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: bold ? null : smartMuted,
              fontWeight: bold ? FontWeight.w600 : null,
            ),
          ),
        ),
      );
      return InkWell(
        onTap: onTap,
        hoverColor: smartGold.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          child: Row(
            children: [
              cell(_LotTableHeader.flexes[0], lot.nama, bold: true),
              cell(_LotTableHeader.flexes[1], lot.noLot),
              cell(_LotTableHeader.flexes[2], lot.mukim),
              cell(_LotTableHeader.flexes[3], lot.daerah),
              Expanded(flex: _LotTableHeader.flexes[4], child: _status(theme)),
              Expanded(
                flex: _LotTableHeader.flexes[5],
                child: Text(
                  '${lot.luas.toStringAsFixed(4)} ha',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18, color: smartMuted),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lot.nama,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lot ${lot.noLot} · ${lot.mukim} · ${lot.daerah}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: smartMuted,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: _status(theme),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${lot.luas.toStringAsFixed(4)} ha',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: smartMuted),
          ],
        ),
      ),
    );
  }
}

/// Column headings above the desktop results table.
class _LotTableHeader extends StatelessWidget {
  const _LotTableHeader();

  /// Relative widths of Nama, Lot, Mukim, Daerah, Belum lengkap, Luas.
  static const flexes = [5, 2, 3, 3, 4, 2];
  static const _labels = [
    'Nama',
    'No. Lot',
    'Mukim',
    'Daerah',
    'Belum lengkap',
    'Luas',
  ];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: smartMuted,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w700,
    );
    return Container(
      color: smartGold.withValues(alpha: 0.10),
      padding: const EdgeInsets.fromLTRB(20, 12, 38, 12),
      child: Row(
        children: [
          for (final (i, label) in _labels.indexed)
            Expanded(
              flex: flexes[i],
              child: Text(
                label.toUpperCase(),
                textAlign: i == _labels.length - 1
                    ? TextAlign.right
                    : TextAlign.left,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

enum _EditAction { saveDraft, deleteDraft, submit }

/// What the edit form was closed with.
typedef _EditResult = ({_EditAction action, LotEdit? edit});

/// Centered pop-up with a lot's details. It asks only for what the lot is
/// missing (Status Torehan and/or Tahun Tanam) plus the officer's name, and
/// pops with an [_EditResult]: keep it as a draft, delete the draft, or send
/// it once the user confirms.
///
/// The form opens with the [draft] kept on the device filled in, else the
/// values already [sent], so work can be continued or corrected. When
/// correcting it shows what was sent before and what is changing.
class _EditDialog extends StatefulWidget {
  final LotRecord lot;
  final LotDraft? draft;
  final SentRecord? sent;

  const _EditDialog({required this.lot, this.draft, this.sent});

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  static const _dialogBg = Color(0xFFFFFDF9);

  /// The values sent last time, when this is a correction.
  LotEdit? get _saved => widget.sent?.latest.edit;

  late final String? _initialStatus =
      widget.draft?.edit.status ?? _saved?.status;
  late final String _initialYear =
      (widget.draft?.edit.tahunTanam ?? _previousYear)?.toString() ?? '';
  late String? _selected = _initialStatus;
  late final _tahun = TextEditingController(text: _initialYear);

  /// The year being corrected: the one saved earlier, else the layer's
  /// (invalid) value. Null when the lot has no year at all.
  int? get _previousYear {
    final y = _saved?.tahunTanam ?? widget.lot.tahunTanam;
    return y == null || y == 0 ? null : y;
  }

  @override
  void dispose() {
    _tahun.dispose();
    super.dispose();
  }

  /// Always the signed-in officer, so every save is credited to them.
  String get _name => AuthService.user.value?.displayName ?? '';
  int? get _year => int.tryParse(_tahun.text.trim());

  /// What still has to be filled in before saving, or null when ready.
  String? get _missing {
    final lot = widget.lot;
    if (lot.needsStatus && _selected == null) return 'Pilih status torehan';
    if (lot.needsTahunTanam && !LotRecord.validTahunTanam(_year)) {
      return 'Masukkan tahun tanam yang sah '
          '(${LotRecord.minTahunTanam}–${LotRecord.maxTahunTanam})';
    }
    if (_name.isEmpty) return 'Sila log masuk semula untuk menyimpan';
    if (_changes.isEmpty) return 'Tukar nilai di atas untuk membetulkan';
    return null;
  }

  /// Each value being changed as (label, before, after), so the form and
  /// the confirmation can show it. Empty when correcting and nothing
  /// differs from what was sent.
  List<(String, String, String)> get _changes {
    final lot = widget.lot;
    final saved = _saved;
    return [
      if (lot.needsStatus && _selected != null && _selected != saved?.status)
        ('Status torehan', saved?.status ?? 'Tiada', _selected!),
      if (lot.needsTahunTanam &&
          _year != null &&
          (saved == null || _year != saved.tahunTanam))
        ('Tahun tanam', _previousYear?.toString() ?? 'Tiada', '$_year'),
    ];
  }

  /// What's been entered so far, complete or not.
  LotEdit get _edit => LotEdit(
    status: widget.lot.needsStatus ? _selected : null,
    tahunTanam: widget.lot.needsTahunTanam ? _year : null,
    pengawai: _name,
  );

  /// A draft needs at least one value and a signed-in officer.
  bool get _canSaveDraft =>
      _name.isNotEmpty && (_selected != null || _tahun.text.trim().isNotEmpty);

  Future<void> _confirm() async {
    final lot = widget.lot;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_saved == null ? 'Sahkan perubahan' : 'Sahkan pembetulan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${lot.nama} (Lot ${lot.noLot})'),
            const SizedBox(height: 12),
            for (final (label, before, after) in _changes)
              _ChangeLine(label: label, before: before, after: after),
            const SizedBox(height: 8),
            Text('Pegawai: $_name'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hantar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, (action: _EditAction.submit, edit: _edit));
    }
  }

  // Cream background, so always use the light theme (see [lightTheme]).
  @override
  Widget build(BuildContext context) => Theme(
    data: lightTheme,
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final lot = widget.lot;
    final missing = _missing;
    // Only nag once the officer has started filling in the form.
    final started = _selected != _initialStatus || _tahun.text != _initialYear;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return Dialog(
      // Near-white so the form reads lighter than the cream page behind it.
      backgroundColor: _dialogBg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.sent == null
                              ? 'KEMASKINI MAKLUMAT'
                              : 'BETULKAN MAKLUMAT',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: smartMuted,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lot.nama,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Tutup',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (widget.draft case final draft?) ...[
                const SizedBox(height: 12),
                _DraftNotice(
                  draft: draft,
                  onDelete: () => Navigator.pop(context, (
                    action: _EditAction.deleteDraft,
                    edit: null,
                  )),
                ),
              ] else if (widget.sent case final sent?) ...[
                const SizedBox(height: 12),
                _SentHistory(record: sent),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: smartCream,
                  border: Border.all(color: smartBorder.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _InfoRow(label: 'No. KP', value: lot.formattedNokp),
                    _InfoRow(label: 'No. Lot', value: lot.noLot),
                    _InfoRow(
                      label: 'No. permohonan',
                      value: lot.noPermohonan ?? '-',
                    ),
                    _InfoRow(label: 'Jenis geran', value: lot.jenisGeran),
                    _InfoRow(label: 'Mukim', value: lot.mukim),
                    _InfoRow(
                      label: 'Lokasi',
                      value: '${lot.daerah}, ${lot.negeri}',
                    ),
                    _InfoRow(
                      label: 'Luas',
                      value: '${lot.luas.toStringAsFixed(4)} hektar',
                    ),
                    if (lot.needsTahunTanam)
                      _YearInputRow(
                        controller: _tahun,
                        onChanged: () => setState(() {}),
                      )
                    else
                      _InfoRow(
                        label: 'Tahun tanam',
                        value: '${lot.tahunTanam}',
                      ),
                    if (lot.namaPengawai != null)
                      _InfoRow(label: 'Dikemaskini', value: lot.namaPengawai!),
                  ],
                ),
              ),
              if (lot.needsStatus) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Status torehan', style: labelStyle)),
                    Text(
                      'Sumber: ${lot.statusTorehanSource ?? 'Tiada'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: smartMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final (i, s)
                    in ArcGisService.statusTorehanOptions.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _StatusOption(
                    status: s,
                    selected: _selected == s,
                    onTap: () => setState(() => _selected = s),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Text('Nama pegawai', style: labelStyle),
              const SizedBox(height: 8),
              // Fixed to the signed-in officer; not editable.
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: smartBeige,
                  border: Border.all(color: smartBorder.withValues(alpha: 0.8)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _name.isEmpty ? '-' : _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.lock_outline, size: 16, color: smartMuted),
                  ],
                ),
              ),
              if (_saved != null && _changes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  decoration: BoxDecoration(
                    color: smartBlue.withValues(alpha: 0.06),
                    border: Border.all(color: smartBlue.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PERUBAHAN',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: smartBlue,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final (label, before, after) in _changes)
                        _ChangeLine(label: label, before: before, after: after),
                    ],
                  ),
                ),
              ],
              // Space is always reserved so the buttons don't jump when the
              // hint appears or disappears. Corrections show it straight
              // away so a greyed-out Hantar is explained.
              Visibility(
                visible: (started || _saved != null) && missing != null,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    missing ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: smartOrange,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // Keeps the work on this device to finish later, even
                  // when it's incomplete or there's no internet.
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _canSaveDraft
                          ? () => Navigator.pop(context, (
                              action: _EditAction.saveDraft,
                              edit: _edit,
                            ))
                          : null,
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text('Simpan draf'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: smartInk,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: missing == null ? _confirm : null,
                      icon: const Icon(Icons.send_outlined, size: 18),
                      // Shrinks rather than wrapping on narrow phones.
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          ArcGisService.editsEnabled
                              ? 'Hantar'
                              : 'Hantar (pratonton)',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Status torehan: ~~Bertoreh~~ → Tidak Bertoreh": the old value struck
/// through and the new one in bold.
class _ChangeLine extends StatelessWidget {
  final String label;
  final String before;
  final String after;

  const _ChangeLine({
    required this.label,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: smartMuted),
            ),
            TextSpan(
              text: before,
              style: const TextStyle(
                color: smartMuted,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const TextSpan(text: '  →  '),
            TextSpan(
              text: after,
              style: const TextStyle(
                color: smartGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green box at the top of the form for a lot already sent from this
/// device: the original value, then each version sent, newest last.
class _SentHistory extends StatelessWidget {
  final SentRecord record;

  const _SentHistory({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lot = record.lot;
    final small = theme.textTheme.bodySmall;
    final original = [
      if (lot.needsStatus) lot.statusTorehan ?? 'Tiada status',
      if (lot.needsTahunTanam)
        lot.tahunTanam == null || lot.tahunTanam == 0
            ? 'Tiada tahun'
            : 'Tahun ${lot.tahunTanam} (tidak sah)',
    ].join(' · ');
    Widget line(String when, String what, {String? who, bool last = false}) =>
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: Text(when, style: small?.copyWith(color: smartMuted)),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: what,
                        style: TextStyle(
                          color: last ? smartGreen : smartInk,
                          fontWeight: last ? FontWeight.w800 : FontWeight.w500,
                          decoration: last ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      if (who != null)
                        TextSpan(
                          text: '  $who',
                          style: const TextStyle(color: smartMuted),
                        ),
                    ],
                  ),
                  style: small,
                ),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: smartGreen.withValues(alpha: 0.08),
        border: Border.all(color: smartGreen.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 18, color: smartGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record.corrected
                      ? 'Telah dihantar dan dibetulkan '
                            '${record.versions.length - 1}x'
                      : 'Telah dihantar',
                  style: small?.copyWith(
                    color: smartGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          line('Asal', original),
          for (final (i, v) in record.versions.indexed)
            line(
              _fmtTime(v.sentAt),
              v.edit.summary,
              who: v.edit.pengawai,
              last: i == record.versions.length - 1,
            ),
          const SizedBox(height: 6),
          Text(
            'Tersalah isi? Pilih nilai yang betul di bawah dan tekan Hantar.',
            style: small?.copyWith(color: smartMuted),
          ),
        ],
      ),
    );
  }
}

/// Box at the top of the edit form for a lot with work kept on the device:
/// a draft, an edit waiting for internet, or one the server refused.
class _DraftNotice extends StatelessWidget {
  final LotDraft draft;
  final VoidCallback onDelete;

  const _DraftNotice({required this.draft, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = _fmtTime(draft.updatedAt);
    final (IconData icon, Color color, String text) = switch (draft) {
      LotDraft(state: DraftState.menunggu) => (
        Icons.schedule,
        smartBlue,
        'Menunggu internet untuk dihantar (disimpan $when). '
            'Ia akan dihantar automatik.',
      ),
      LotDraft(:final error?) => (
        Icons.error_outline,
        smartOrange,
        'Gagal dihantar: $error. Semak dan hantar semula.',
      ),
      _ => (
        Icons.edit_note,
        smartGoldDeep,
        'Draf disimpan $when. Lengkapkan dan tekan Hantar.',
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onDelete,
            style: TextButton.styleFrom(
              foregroundColor: smartMuted,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Padam draf'),
          ),
        ],
      ),
    );
  }
}

/// Compact search box for the mukim and lot filters in the header.
class _SmallSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final VoidCallback onSubmitted;
  final double height;

  const _SmallSearchField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.onSubmitted,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (_) => onSubmitted(),
          style: theme.textTheme.bodySmall,
          decoration: InputDecoration(
            hintText: hint,
            fillColor: theme.colorScheme.surface,
            contentPadding: EdgeInsets.zero,
            prefixIcon: Icon(icon, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      controller.clear();
                      onSubmitted();
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: smartMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Tahun tanam row of the details box as an editable box, shown when
/// the year is missing or invalid. It flags the value until it's 1960–2026.
class _YearInputRow extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _YearInputRow({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = int.tryParse(controller.text.trim());
    final valid = LotRecord.validTahunTanam(year);
    final color = valid ? smartGreen : smartOrange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              'Tahun tanam',
              style: theme.textTheme.bodySmall?.copyWith(color: smartMuted),
            ),
          ),
          SizedBox(
            width: 84,
            height: 34,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              onChanged: (_) => onChanged(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'cth: 2015',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: color),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: color, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            valid ? Icons.check_circle : Icons.edit_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              valid
                  ? 'Sah'
                  : controller.text.isEmpty
                  ? 'Tiada — sila isi'
                  : 'Tidak sah — betulkan',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  final String status;
  final bool selected;
  final VoidCallback onTap;

  const _StatusOption({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  /// A short meaning under each status, so officers pick the right one.
  static String _meaning(String status) => switch (status) {
    'Bertoreh' => 'Pokok matang dan sedang ditoreh',
    'Tidak Bertoreh' => 'Pokok matang tetapi tidak ditoreh',
    'Getah Muda' => 'Pokok belum matang untuk ditoreh',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusTorehanColor(status);
    final outline = theme.colorScheme.outlineVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? color.withValues(alpha: 0.08) : null,
            border: Border.all(
              color: selected ? color : outline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(statusTorehanIcon(status), color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _meaning(status),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: smartMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Radio mark: an empty ring, filled with a tick when chosen.
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? color : null,
                  border: Border.all(
                    color: selected ? color : smartMuted.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: smartMuted),
            ),
          ],
        ),
      ),
    );
  }
}
