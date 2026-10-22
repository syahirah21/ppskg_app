import 'package:flutter/material.dart';

import '../services/arcgis_service.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Opens the searchable state picker and stores the choice in
/// [AppState.negeri]. Loads the state list first if no tab has yet.
Future<void> pickNegeri(BuildContext context) async {
  if (AppState.negeriOptions.value.isEmpty) {
    try {
      AppState.negeriOptions.value = await ArcGisService().groupBy('NEGERI');
    } catch (_) {
      // The sheet still opens; it just shows "Seluruh Malaysia" only.
    }
  }
  if (!context.mounted) return;
  final picked = await showModalBottomSheet<_Pick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PlacePicker(
      title: 'Pilih negeri',
      searchHint: 'Cari negeri…',
      allLabel: 'Seluruh Malaysia',
      allIcon: Icons.public,
      emptyText: 'Tiada negeri sepadan',
      options: AppState.negeriOptions.value,
      selected: AppState.negeri.value,
    ),
  );
  if (picked != null) AppState.negeri.value = picked.value;
}

/// Opens the searchable district picker for [negeri] with the given
/// [options] (from ArcGisService.allDaerah). Returns the choice as a record,
/// where a null daerah means the whole state, or null if dismissed.
Future<({String? daerah})?> pickDaerah(
  BuildContext context, {
  required String negeri,
  required List<GroupStat> options,
  required String? selected,
}) async {
  final picked = await showModalBottomSheet<_Pick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PlacePicker(
      title: 'Pilih daerah',
      searchHint: 'Cari daerah…',
      allLabel: 'Semua daerah ($negeri)',
      allIcon: Icons.map_outlined,
      emptyText: 'Tiada daerah sepadan',
      options: options,
      selected: selected,
    ),
  );
  return picked == null ? null : (daerah: picked.value);
}

/// Opens the searchable mukim picker for [daerah] with the given [options]
/// (from ArcGisService.mukimOf). A null mukim means the whole district;
/// returns null if dismissed.
Future<({String? mukim})?> pickMukim(
  BuildContext context, {
  required String daerah,
  required List<GroupStat> options,
  required String? selected,
}) async {
  final picked = await showModalBottomSheet<_Pick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PlacePicker(
      title: 'Pilih mukim',
      searchHint: 'Cari mukim…',
      allLabel: 'Semua mukim ($daerah)',
      allIcon: Icons.holiday_village_outlined,
      emptyText: 'Tiada mukim sepadan',
      options: options,
      selected: selected,
    ),
  );
  return picked == null ? null : (mukim: picked.value);
}

/// Pill button showing the chosen state; opens the picker when tapped.
/// Follows [AppState.negeri] so it updates when another tab changes it.
class LocationPill extends StatelessWidget {
  /// Solid brown background, for use on top of the map.
  final bool solid;

  const LocationPill({super.key, this.solid = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppState.negeri,
      builder: (context, negeri, _) => Material(
        color: solid ? smartBrown : Colors.white.withValues(alpha: 0.12),
        elevation: solid ? 3 : 0,
        shape: const StadiumBorder(side: BorderSide(color: Colors.white24)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => pickNegeri(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place, size: 16, color: smartGold),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    negeri ?? 'Seluruh Malaysia',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the picker returns (null value = the "all" row).
class _Pick {
  final String? value;
  const _Pick(this.value);
}

/// Searchable list of places (states or districts) with lot counts, led by
/// an "all" row.
class _PlacePicker extends StatefulWidget {
  final String title;
  final String searchHint;
  final String allLabel;
  final IconData allIcon;
  final String emptyText;
  final List<GroupStat> options;
  final String? selected;

  const _PlacePicker({
    required this.title,
    required this.searchHint,
    required this.allLabel,
    required this.allIcon,
    required this.emptyText,
    required this.options,
    required this.selected,
  });

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toUpperCase();
    final matches = widget.options
        .where((g) => g.label != 'Tiada data')
        .where((g) => g.label.toUpperCase().contains(q))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                if (q.isEmpty || widget.allLabel.toUpperCase().contains(q))
                  _PickerTile(
                    icon: widget.allIcon,
                    label: widget.allLabel,
                    count: widget.options.fold(0, (s, g) => s + g.count),
                    selected: widget.selected == null,
                    onTap: () => Navigator.pop(context, const _Pick(null)),
                  ),
                for (final g in matches)
                  _PickerTile(
                    icon: Icons.place_outlined,
                    label: g.label,
                    count: g.count,
                    selected: widget.selected == g.label,
                    onTap: () => Navigator.pop(context, _Pick(g.label)),
                  ),
                if (matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.emptyText,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: selected ? smartGold.withValues(alpha: 0.18) : null,
      leading: CircleAvatar(
        backgroundColor: smartGold.withValues(alpha: 0.18),
        child: Icon(icon, color: smartGoldDeep, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${fmtInt(count)} lot'),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
