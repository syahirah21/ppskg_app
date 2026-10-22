import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/arcgis_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

/// Lists lots that are missing a Status Torehan or a valid Tahun Tanam so
/// officers can fill them in. The edit form only asks for what's missing.
///
/// While [ArcGisService.editsEnabled] is false, saving only marks the lot in
/// this screen (it stays listed, since the layer still has no status) and
/// nothing is sent to the server. Once edits are live, a saved lot drops off
/// the list because it now has data.
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

  /// What was saved in preview mode for each lot, by GlobalID.
  final Map<String, _LotEdit> _previewEdits = {};

  @override
  void initState() {
    super.initState();
    // Show the to-do list straight away, before any name is typed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
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
    });
    try {
      final (results, counts) = await (
        _service.searchIncomplete(
          name,
          filter: _filter,
          mukim: mukim,
          lot: lot,
          limit: _limit,
        ),
        [
          for (final f in IncompleteFilter.values)
            _service.countIncomplete(name, filter: f, mukim: mukim, lot: lot),
        ].wait,
      ).wait;
      setState(() {
        _results = results;
        _counts = {
          for (final (i, f) in IncompleteFilter.values.indexed) f: counts[i],
        };
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
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
    if (filter == _filter || _loading) return;
    setState(() => _filter = filter);
    _search();
  }

  Future<void> _openLot(LotRecord lot) async {
    final edit = await showDialog<_LotEdit>(
      context: context,
      builder: (_) => _EditDialog(lot: lot, saved: _previewEdits[lot.globalId]),
    );
    if (edit == null || !mounted) return;
    if (ArcGisService.editsEnabled) {
      try {
        await _service.updateLot(
          lot.globalId,
          status: edit.status,
          tahunTanam: edit.tahunTanam,
          namaPengawai: edit.pengawai,
        );
        _markDone(lot);
        _toast('Data berjaya disimpan');
      } catch (e) {
        _toast('Gagal menyimpan: $e');
      }
    } else {
      // Preview only: the layer is unchanged, so the lot stays listed.
      setState(() => _previewEdits[lot.globalId] = edit);
      _toast('Data berjaya disimpan');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(gradient: headerGradient),
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + 12,
            16,
            14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cari & Kemaskini',
                style: theme.textTheme.titleLarge?.copyWith(
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
              const SizedBox(height: 12),
              SizedBox(
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
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _SmallSearchField(
                      controller: _mukim,
                      hint: 'Mukim',
                      icon: Icons.place_outlined,
                      onSubmitted: _search,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _SmallSearchField(
                      controller: _lot,
                      hint: 'No. Lot',
                      icon: Icons.tag,
                      onSubmitted: _search,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Shrinks on narrow phones so all three chips stay visible.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    for (final (i, f) in IncompleteFilter.values.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _FilterChip(
                        filter: f,
                        count: _counts[f],
                        selected: f == _filter,
                        onTap: () => _setFilter(f),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildResults(theme)),
      ],
    );
  }

  /// What the summary line calls the listed lots, e.g. "tiada tahun tanam".
  String _summaryLabel() => switch (_filter) {
    IncompleteFilter.semua => 'belum lengkap',
    IncompleteFilter.tiadaStatus => 'tiada status torehan',
    IncompleteFilter.tiadaTahun => 'tiada tahun tanam',
  };

  Widget _buildResults(ThemeData theme) {
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
            child: _LotRow(
              lot: lot,
              saved: _previewEdits[lot.globalId],
              onTap: () => _openLot(lot),
            ),
          ),
      ],
    );
  }
}

/// Filter pill on the dark header: gold when selected, with the number of
/// matching lots (blank while loading).
class _FilterChip extends StatelessWidget {
  final IncompleteFilter filter;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.filter,
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
              Text(
                filter.label,
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
/// left, planted area on the right. [saved] marks a lot already saved in
/// preview mode.
class _LotRow extends StatelessWidget {
  final LotRecord lot;
  final _LotEdit? saved;
  final VoidCallback onTap;

  const _LotRow({required this.lot, this.saved, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    child: saved != null
                        ? Text(
                            '✓ ${saved!.summary}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: smartGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : Text(
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
                          ),
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

/// What an officer entered for one lot: a status and/or a planting year
/// (only the ones that were missing), plus their name.
class _LotEdit {
  final String? status;
  final int? tahunTanam;
  final String pengawai;

  const _LotEdit({this.status, this.tahunTanam, required this.pengawai});

  /// E.g. "Bertoreh · Tahun 2015".
  String get summary =>
      [?status, if (tahunTanam != null) 'Tahun $tahunTanam'].join(' · ');
}

/// Centered pop-up with a lot's details. It asks only for what the lot is
/// missing (Status Torehan and/or Tahun Tanam) plus the officer's name, and
/// pops with a [_LotEdit] once the user confirms.
///
/// When the lot was already saved ([saved]), the form opens with those
/// values filled in so a wrong entry can be corrected.
class _EditDialog extends StatefulWidget {
  final LotRecord lot;
  final _LotEdit? saved;

  const _EditDialog({required this.lot, this.saved});

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  static const _dialogBg = Color(0xFFFFFDF9);

  late String? _selected = widget.saved?.status;
  late final _tahun = TextEditingController(
    text: _previousYear?.toString() ?? '',
  );

  /// The year being corrected: the one saved earlier, else the layer's
  /// (invalid) value. Null when the lot has no year at all.
  int? get _previousYear {
    final y = widget.saved?.tahunTanam ?? widget.lot.tahunTanam;
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
    return null;
  }

  /// "2015 → 2016" when correcting a saved value, otherwise just the value.
  String _change(Object? before, Object? after) =>
      before == null || before == after ? '$after' : '$before → $after';

  Future<void> _confirm() async {
    final lot = widget.lot;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sahkan perubahan'),
        content: Text(
          '${lot.nama} (Lot ${lot.noLot})\n\n'
          '${lot.needsStatus ? 'Status torehan: ${_change(widget.saved?.status, _selected)}\n' : ''}'
          '${lot.needsTahunTanam ? 'Tahun tanam: ${_change(_previousYear, _year)}\n' : ''}'
          'Pegawai: $_name',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(
        context,
        _LotEdit(
          status: lot.needsStatus ? _selected : null,
          tahunTanam: lot.needsTahunTanam ? _year : null,
          pengawai: _name,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lot = widget.lot;
    final missing = _missing;
    // Only nag once the officer has started filling in the form.
    final started =
        _selected != widget.saved?.status ||
        _tahun.text != (_previousYear?.toString() ?? '');
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
                          widget.saved == null
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
              if (widget.saved case final saved?) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: smartGreen.withValues(alpha: 0.08),
                    border: Border.all(
                      color: smartGreen.withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: smartGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Telah disimpan: ${saved.summary} '
                          '(oleh ${saved.pengawai}). '
                          'Betulkan di bawah jika salah.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: smartGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                Row(
                  children: [
                    for (final (i, s)
                        in ArcGisService.statusTorehanOptions.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _StatusOption(
                          status: s,
                          selected: _selected == s,
                          onTap: () => setState(() => _selected = s),
                        ),
                      ),
                    ],
                  ],
                ),
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
              // Space is always reserved so the buttons don't jump when the
              // hint appears or disappears.
              Visibility(
                visible: started && missing != null,
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
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: smartInk,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: missing == null ? _confirm : null,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(
                        ArcGisService.editsEnabled
                            ? 'Simpan'
                            : 'Simpan (pratonton)',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

/// Compact search box for the mukim and lot filters in the header.
class _SmallSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final VoidCallback onSubmitted;

  const _SmallSearchField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
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

  @override
  Widget build(BuildContext context) {
    final color = statusTorehanColor(status);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? color.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: selected
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_circle : statusTorehanIcon(status),
              color: color,
              size: 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
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
