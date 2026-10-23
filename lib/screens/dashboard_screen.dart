import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/arcgis_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/negeri_picker.dart';
import '../widgets/profile_drawer.dart';

/// All the figures shown on the dashboard for the current filter.
class DashboardData {
  final List<GroupStat> byNegeri;
  final List<GroupStat> byDaerah;
  final List<GroupStat> byStatusTorehan;
  final List<GroupStat> byStatusGetah;
  final List<GroupStat> byJantina;

  const DashboardData({
    required this.byNegeri,
    required this.byDaerah,
    required this.byStatusTorehan,
    required this.byStatusGetah,
    required this.byJantina,
  });

  int get totalLots => byStatusTorehan.fold(0, (s, g) => s + g.count);
  double get totalArea => byStatusTorehan.fold(0.0, (s, g) => s + g.area);

  GroupStat statOf(List<GroupStat> stats, String label) => stats.firstWhere(
    (g) => g.label == label,
    orElse: () => GroupStat(label, 0, 0),
  );
}

double _pct(int n, int total) => total == 0 ? 0 : n / total * 100;

String _fmtHa(double ha) => '${fmtInt(ha.round())} ha';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _service = ArcGisService();

  late Future<DashboardData> _future;

  /// The selected state, shared with the Map tab.
  String? get _negeri => AppState.negeri.value;

  @override
  void initState() {
    super.initState();
    _future = _load();
    AppState.negeri.addListener(_onNegeriChanged);
  }

  @override
  void dispose() {
    AppState.negeri.removeListener(_onNegeriChanged);
    super.dispose();
  }

  void _onNegeriChanged() {
    final future = _load();
    setState(() {
      _future = future;
    });
  }

  Future<DashboardData> _load() async {
    final where = ArcGisService.whereFor(_negeri);
    final results = await Future.wait([
      _service.groupBy('NEGERI', where: where),
      _service.groupBy('DAERAH', where: where),
      _service.groupBy('STATUS_TOREHAN', where: where),
      _service.groupBy('STATUS_GETAH', where: where),
      _service.groupBy('JANTINA', where: where),
    ]);
    if (_negeri == null) AppState.negeriOptions.value = results[0];
    return DashboardData(
      byNegeri: results[0],
      byDaerah: results[1],
      byStatusTorehan: results[2],
      byStatusGetah: results[3],
      byJantina: results[4],
    );
  }

  void _setNegeri(String? negeri) => AppState.negeri.value = negeri;

  Widget _buildBody(BuildContext context, DashboardData data, bool desktop) =>
      SliverPadding(
        padding: desktop
            ? const EdgeInsets.fromLTRB(32, 16, 32, 32)
            : const EdgeInsets.fromLTRB(16, 8, 16, 24),
        sliver: SliverToBoxAdapter(
          child: _buildBodyCards(
            context: context,
            data: data,
            negeri: _negeri,
            onPickNegeri: _setNegeri,
            desktop: desktop,
          ),
        ),
      );

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final data = loading || snap.hasError ? null : snap.data;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _HeaderWithCards(
                  data: data,
                  negeri: _negeri,
                  desktop: desktop,
                ),
              ),
              if (loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snap.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorView(
                    message: '${snap.error}',
                    onRetry: _refresh,
                  ),
                )
              else
                _buildBody(context, data!, desktop),
            ],
          ),
        );
      },
    );
  }
}

/// Builds the cards under the header; on desktop the overview and ranking
/// sit beside the distribution chart.
Widget _buildBodyCards({
  required BuildContext context,
  required DashboardData data,
  required String? negeri,
  required ValueChanged<String> onPickNegeri,
  required bool desktop,
}) {
  final overview = _OverviewCard(data: data);
  final distribution = _DistributionCard(data: data);
  final ranking = _RankingCard(
    title: negeri == null ? 'Negeri teratas' : 'Daerah teratas',
    subtitle: negeri ?? 'Ketik negeri untuk butiran',
    stats: (negeri == null ? data.byNegeri : data.byDaerah)
        .where((g) => g.label != 'Tiada data')
        .toList(),
    total: data.totalLots,
    onTap: negeri == null ? onPickNegeri : null,
  );
  final source = Text(
    'Sumber: RISDA GIS Server · Lot_Getah_Satu_Malaysia',
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodySmall,
  );
  if (!desktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        overview,
        const SizedBox(height: 16),
        distribution,
        const SizedBox(height: 16),
        ranking,
        const SizedBox(height: 12),
        source,
      ],
    );
  }
  return desktopContent(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [overview, const SizedBox(height: 20), ranking],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: distribution),
          ],
        ),
        const SizedBox(height: 16),
        source,
      ],
    ),
  );
}

/// Brown header with the headline figures, plus a row of status cards that
/// overlaps its bottom edge and scrolls sideways.
class _HeaderWithCards extends StatelessWidget {
  final bool desktop;
  final DashboardData? data;
  final String? negeri;

  static const _cardsHeight = 132.0;
  static const _overlap = 64.0;

  const _HeaderWithCards({
    required this.data,
    required this.negeri,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = this.data;
    // The header is padded at the bottom so the card row (pinned to the
    // Stack's bottom) covers its last [_overlap] pixels and hangs below.
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: _cardsHeight - _overlap),
          decoration: const BoxDecoration(gradient: headerGradient),
          padding: desktop
              ? const EdgeInsets.fromLTRB(32, 28, 32, _overlap + 28)
              : EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.paddingOf(context).top + 12,
                  20,
                  _overlap + 20,
                ),
          child: desktop
              ? desktopContent(_buildDesktopTop(theme, data))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset('assets/images/risda_logo.png', height: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RISDA',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                'Lot Getah Malaysia',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Opens the profile panel (HomeShell's end drawer).
                        ProfileAvatarButton(
                          onTap: () => Scaffold.of(context).openEndDrawer(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    // Location filter sits beside the totals it changes.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            data == null ? '—' : fmtInt(data.totalLots),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: smartGold,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const LocationPill(),
                      ],
                    ),
                    Text(
                      data == null
                          ? 'Memuatkan data…'
                          : 'lot getah berdaftar · ${_fmtHa(data.totalArea)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _cardsHeight,
          child: data == null
              ? const SizedBox()
              : desktop
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: desktopContent(
                    Row(
                      children: [
                        for (final status in _statuses)
                          Expanded(
                            child: _StatusCard(
                              stat: data.statOf(data.byStatusTorehan, status),
                              total: data.totalLots,
                              wide: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final status in _statuses)
                      _StatusCard(
                        stat: data.statOf(data.byStatusTorehan, status),
                        total: data.totalLots,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  static const _statuses = [
    'Bertoreh',
    'Tidak Bertoreh',
    'Getah Muda',
    'Tiada data',
  ];

  /// Desktop header: page title, then the total beside the state filter.
  /// The RISDA logo and profile live in the sidebar instead.
  Widget _buildDesktopTop(ThemeData theme, DashboardData? data) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Dashboard',
        style: theme.textTheme.headlineSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(
        'Ringkasan lot getah berdaftar RISDA',
        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60),
      ),
      const SizedBox(height: 24),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            data == null ? '—' : fmtInt(data.totalLots),
            style: theme.textTheme.displayMedium?.copyWith(
              color: smartGold,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                data == null
                    ? 'Memuatkan data…'
                    : 'lot getah berdaftar · ${_fmtHa(data.totalArea)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ),
          ),
          const LocationPill(),
        ],
      ),
    ],
  );
}

/// One tapping-status figure in the overlapping card row.
class _StatusCard extends StatelessWidget {
  final GroupStat stat;
  final int total;

  /// Fills its share of a desktop row instead of a fixed phone width.
  final bool wide;

  const _StatusCard({
    required this.stat,
    required this.total,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusTorehanColor(stat.label);
    return Container(
      width: wide ? null : 168,
      margin: wide
          ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
          : const EdgeInsets.only(right: 12, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: smartBrown.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  statusTorehanIcon(stat.label),
                  size: 14,
                  color: color,
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            child: Text(
              fmtInt(stat.count),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${_pct(stat.count, total).toStringAsFixed(1)}% ',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '· ${_fmtHa(stat.area)}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Planted area by tapping status, with a stacked progress bar.
class _OverviewCard extends StatelessWidget {
  final DashboardData data;

  const _OverviewCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalArea = data.totalArea;
    final parts = [
      for (final s in [
        'Bertoreh',
        'Tidak Bertoreh',
        'Getah Muda',
        'Tiada data',
      ])
        data.statOf(data.byStatusTorehan, s),
    ];
    final rate = totalArea == 0 ? 0.0 : parts[0].area / totalArea * 100;
    final good = rate >= 50;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Keluasan torehan', style: theme.textTheme.titleMedium),
            Text(
              'Keluasan tanaman (hektar) mengikut status',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final g in parts.take(3))
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.label, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 2),
                        Text(
                          fmtInt(g.area.round()),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: statusTorehanColor(g.label),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final g in parts)
                      if (g.area >= 1)
                        Expanded(
                          flex: g.area.round(),
                          child: Container(color: statusTorehanColor(g.label)),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  good ? Icons.check_circle : Icons.info,
                  size: 16,
                  color: good ? smartGreen : smartOrange,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${rate.toStringAsFixed(1)}% keluasan sedang ditoreh',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: good ? smartGreen : smartOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Breakdown {
  torehan('Torehan'),
  getah('Status getah'),
  jantina('Jantina');

  final String label;
  const _Breakdown(this.label);
}

/// Donut chart with a segmented toggle and a category list underneath.
class _DistributionCard extends StatefulWidget {
  final DashboardData data;

  const _DistributionCard({required this.data});

  @override
  State<_DistributionCard> createState() => _DistributionCardState();
}

class _DistributionCardState extends State<_DistributionCard> {
  _Breakdown _mode = _Breakdown.torehan;
  int _touched = -1;

  static const _palette = [
    smartGreen,
    smartOrange,
    smartGoldDeep,
    smartBrownLight,
    Color(0xFFA89C8A),
  ];

  List<GroupStat> get _stats => switch (_mode) {
    _Breakdown.torehan => widget.data.byStatusTorehan,
    _Breakdown.getah => widget.data.byStatusGetah,
    _Breakdown.jantina => widget.data.byJantina,
  };

  Color _colorFor(GroupStat g, int i) {
    if (g.label == 'Tiada data') return const Color(0xFFA89C8A);
    return switch (_mode) {
      _Breakdown.torehan => statusTorehanColor(g.label),
      _Breakdown.jantina =>
        g.label == 'LELAKI'
            ? smartBrownLight
            : g.label == 'PEREMPUAN'
            ? smartGold
            : _palette[4],
      _Breakdown.getah => _palette[i % _palette.length],
    };
  }

  /// "PEREMPUAN" -> "Perempuan" so all modes read the same way.
  String _title(String s) => s == s.toUpperCase()
      ? s
            .toLowerCase()
            .split(' ')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' ')
      : s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _stats;
    final total = stats.fold(0, (s, g) => s + g.count);
    final focus = _touched >= 0 && _touched < stats.length
        ? stats[_touched]
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Taburan lot', style: theme.textTheme.titleMedium),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Breakdown>(
                segments: [
                  for (final m in _Breakdown.values)
                    ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  _touched = -1;
                }),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: smartGold,
                  selectedForegroundColor: smartInk,
                  textStyle: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 4,
                      centerSpaceRadius: 64,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          if (!event.isInterestedForInteractions) return;
                          final i =
                              response?.touchedSection?.touchedSectionIndex;
                          if (i != null && i >= 0) {
                            setState(() => _touched = i);
                          }
                        },
                      ),
                      sections: [
                        for (var i = 0; i < stats.length; i++)
                          PieChartSectionData(
                            value: stats[i].count.toDouble(),
                            color: _colorFor(stats[i], i),
                            radius: i == _touched ? 48 : 40,
                            title: _pct(stats[i].count, total) >= 4
                                ? '${_pct(stats[i].count, total).round()}%'
                                : '',
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    duration: const Duration(milliseconds: 300),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fmtInt(focus?.count ?? total),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(
                          focus == null ? 'lot' : _title(focus.label),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Semua kategori', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            for (var i = 0; i < stats.length; i++)
              _CategoryRow(
                label: _title(stats[i].label),
                pct: _pct(stats[i].count, total),
                detail:
                    '${fmtInt(stats[i].count)} lot · ${_fmtHa(stats[i].area)}',
                color: _colorFor(stats[i], i),
                selected: i == _touched,
                onTap: () => setState(() => _touched = i),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String label;
  final double pct;
  final String detail;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryRow({
    required this.label,
    required this.pct,
    required this.detail,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? color.withValues(alpha: 0.10) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${pct.toStringAsFixed(0)}%  ',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct / 100),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Ranked states or districts, shown like a transaction list.
class _RankingCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<GroupStat> stats;
  final int total;
  final ValueChanged<String>? onTap;

  const _RankingCard({
    required this.title,
    required this.subtitle,
    required this.stats,
    required this.total,
    this.onTap,
  });

  @override
  State<_RankingCard> createState() => _RankingCardState();
}

class _RankingCardState extends State<_RankingCard> {
  static const _collapsed = 5;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = widget.stats;
    final shown = _showAll ? stats : stats.take(_collapsed).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: theme.textTheme.titleMedium),
                      Text(widget.subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (stats.length > _collapsed)
                  TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll ? 'Tutup' : 'Lihat semua'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
              InkWell(
                onTap: widget.onTap == null
                    ? null
                    : () => widget.onTap!(shown[i].label),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: i < 3
                            ? smartGold.withValues(alpha: 0.25)
                            : theme.colorScheme.surfaceContainerHighest,
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: i < 3 ? smartGoldDeep : smartMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shown[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _fmtHa(shown[i].area),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            fmtInt(shown[i].count),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${_pct(shown[i].count, widget.total).toStringAsFixed(1)}%',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      if (widget.onTap != null)
                        const Icon(Icons.chevron_right, size: 20)
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text('Gagal memuatkan data:\n$message', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Cuba lagi')),
        ],
      ),
    );
  }
}
