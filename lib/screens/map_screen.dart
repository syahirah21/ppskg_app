import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/arcgis_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/negeri_picker.dart';

/// Approximate bounds of each state, used to frame the map. The layer's own
/// extents can't be used: a few lots with the wrong NEGERI or misplaced
/// shapes stretch them across the country (e.g. "PERLIS" spans 99.7–103.3°E).
final Map<String?, LatLngBounds> _stateBounds = {
  null: LatLngBounds(const LatLng(0.85, 99.6), const LatLng(7.4, 119.3)),
  'PERLIS': LatLngBounds(
    const LatLng(6.27, 100.12),
    const LatLng(6.73, 100.40),
  ),
  'KEDAH': LatLngBounds(const LatLng(5.08, 99.6), const LatLng(6.45, 101.12)),
  'PULAU PINANG': LatLngBounds(
    const LatLng(5.1, 100.17),
    const LatLng(5.6, 100.56),
  ),
  'PERAK': LatLngBounds(const LatLng(3.65, 100.35), const LatLng(5.92, 101.75)),
  'SELANGOR': LatLngBounds(
    const LatLng(2.58, 100.8),
    const LatLng(3.88, 101.98),
  ),
  'KUALA LUMPUR': LatLngBounds(
    const LatLng(3.04, 101.61),
    const LatLng(3.25, 101.76),
  ),
  'PUTRAJAYA': LatLngBounds(
    const LatLng(2.88, 101.66),
    const LatLng(2.98, 101.73),
  ),
  'NEGERI SEMBILAN': LatLngBounds(
    const LatLng(2.4, 101.7),
    const LatLng(3.25, 102.68),
  ),
  'MELAKA': LatLngBounds(
    const LatLng(2.05, 102.05),
    const LatLng(2.53, 102.55),
  ),
  'JOHOR': LatLngBounds(const LatLng(1.25, 102.5), const LatLng(2.85, 104.4)),
  'PAHANG': LatLngBounds(const LatLng(2.47, 101.33), const LatLng(4.78, 103.7)),
  'TERENGGANU': LatLngBounds(
    const LatLng(3.88, 102.37),
    const LatLng(5.85, 103.55),
  ),
  'KELANTAN': LatLngBounds(
    const LatLng(4.55, 101.3),
    const LatLng(6.25, 102.67),
  ),
  'SABAH': LatLngBounds(const LatLng(4.0, 115.3), const LatLng(7.4, 119.3)),
  'SARAWAK': LatLngBounds(const LatLng(0.85, 109.6), const LatLng(5.05, 115.7)),
  'LABUAN': LatLngBounds(const LatLng(5.2, 115.15), const LatLng(5.38, 115.35)),
};

LatLngBounds _boundsFor(String? negeri) =>
    _stateBounds[negeri] ?? _stateBounds[null]!;

/// Lots are drawn by the RISDA server, which gets slow for very large areas,
/// so lot shapes only appear from these zoom levels.
const _minLotZoomState = 7.0;
const _minLotZoomAll = 9.0;

/// Rubber lots are small; below this zoom they are only specks.
const _clearLotZoom = 12.0;

class MapScreen extends StatefulWidget {
  /// Whether the Map tab is on screen. Lot images are only requested while
  /// it is, so the hidden map doesn't slow the server for the other tabs.
  final bool active;

  const MapScreen({super.key, required this.active});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final _service = ArcGisService();
  final _map = MapController();

  /// Drives the smooth camera moves of the zoom and state buttons.
  late final _camAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  VoidCallback? _camListener;

  bool _ready = false;
  bool _satellite = false;
  double _zoom = 6;

  LotRecord? _lot;
  bool _identifying = false;

  /// Land district picked within the state, and its lots' bounding box.
  String? _daerah;
  LatLngBounds? _daerahBounds;
  bool _loadingDaerah = false;

  /// Every state's land districts (one query, started when the map opens),
  /// and each district's area once looked up, keyed "NEGERI|DAERAH".
  Future<Map<String, List<GroupStat>>>? _allDaerah;
  final _extentCache = <String, LatLngBounds>{};

  /// Land mukim picked within the district, and its lots' bounding box.
  String? _mukim;
  LatLngBounds? _mukimBounds;
  bool _loadingMukim = false;

  /// Each district's mukim list once loaded, keyed "NEGERI|DAERAH".
  final _mukimCache = <String, List<GroupStat>>{};

  /// Where the lot found by "Cari lot" is, to pin it on the map.
  LatLng? _foundLot;
  bool _findingLot = false;

  String? get _negeri => AppState.negeri.value;
  double get _minLotZoom => _negeri == null ? _minLotZoomAll : _minLotZoomState;

  @override
  void initState() {
    super.initState();
    AppState.negeri.addListener(_onNegeriChanged);
    _loadAllDaerah();
  }

  @override
  void dispose() {
    AppState.negeri.removeListener(_onNegeriChanged);
    _camAnim.dispose();
    super.dispose();
  }

  /// Glides the camera to [center] and [zoom] instead of jumping.
  void _animateTo(LatLng center, double zoom) {
    final from = _map.camera;
    final lat = Tween(begin: from.center.latitude, end: center.latitude);
    final lng = Tween(begin: from.center.longitude, end: center.longitude);
    final z = Tween(begin: from.zoom, end: zoom);
    final curve = CurvedAnimation(parent: _camAnim, curve: Curves.easeInOut);
    if (_camListener != null) _camAnim.removeListener(_camListener!);
    _camListener = () => _map.move(
      LatLng(lat.evaluate(curve), lng.evaluate(curve)),
      z.evaluate(curve),
    );
    _camAnim
      ..addListener(_camListener!)
      ..forward(from: 0);
  }

  void _onNegeriChanged() {
    setState(() {
      _lot = null;
      _daerah = null;
      _daerahBounds = null;
      _clearMukim();
    });
    if (_ready) _fitState();
  }

  /// Forgets the picked mukim and any found lot (call inside setState).
  void _clearMukim() {
    _mukim = null;
    _mukimBounds = null;
    _foundLot = null;
  }

  /// Frames the picked mukim, else district, else the state (or all of
  /// Malaysia).
  void _fitState() {
    final target = CameraFit.bounds(
      bounds: _mukimBounds ?? _daerahBounds ?? _boundsFor(_negeri),
      padding: EdgeInsets.fromLTRB(24, _negeri == null ? 90 : 140, 24, 120),
      // A district with very few lots shouldn't zoom in to street level.
      maxZoom: 15,
    ).fit(_map.camera);
    _animateTo(target.center, target.zoom);
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    // Step from where a running animation is heading, so quick repeated
    // taps add up instead of restarting from a half-way zoom.
    final base = _camAnim.isAnimating
        ? camera.zoom.roundToDouble()
        : camera.zoom;
    _animateTo(camera.center, (base + delta).clamp(5, 19).toDouble());
  }

  /// Fetches every state's district list in one small query, once. A
  /// failed load is forgotten so the next tap tries again.
  Future<Map<String, List<GroupStat>>> _loadAllDaerah() =>
      _allDaerah ??= _service.allDaerah()
        ..catchError((Object _) {
          _allDaerah = null;
          return <String, List<GroupStat>>{};
        });

  Future<void> _pickDaerah() async {
    final negeri = _negeri;
    if (negeri == null || _loadingDaerah) return;
    List<GroupStat> options;
    setState(() => _loadingDaerah = true);
    try {
      // Usually already loaded in the background when the map opened.
      options = (await _loadAllDaerah())[negeri] ?? [];
    } catch (_) {
      _toast('Tiada sambungan. Gagal memuatkan senarai daerah.');
      return;
    } finally {
      if (mounted) setState(() => _loadingDaerah = false);
    }
    if (!mounted || _negeri != negeri) return;
    final picked = await pickDaerah(
      context,
      negeri: negeri,
      options: options,
      selected: _daerah,
    );
    if (!mounted || picked == null || picked.daerah == _daerah) return;
    final daerah = picked.daerah;

    // Filter the lots straight away; the camera follows once the
    // district's area is known.
    setState(() {
      _daerah = daerah;
      _daerahBounds = daerah == null ? null : _extentCache['$negeri|$daerah'];
      _lot = null;
      _clearMukim();
    });
    if (daerah == null || _daerahBounds != null) {
      _fitState();
      return;
    }
    setState(() => _loadingDaerah = true);
    try {
      final e = await _service.extentOf(
        ArcGisService.whereForArea(negeri, daerah),
      );
      if (e == null) return;
      final bounds = LatLngBounds(LatLng(e.$1, e.$2), LatLng(e.$3, e.$4));
      _extentCache['$negeri|$daerah'] = bounds;
      // Only move if the user hasn't picked something else meanwhile.
      if (mounted && _negeri == negeri && _daerah == daerah) {
        setState(() => _daerahBounds = bounds);
        _fitState();
      }
    } catch (_) {
      _toast('Gagal mencari kawasan daerah. Lot tetap ditapis.');
    } finally {
      if (mounted) setState(() => _loadingDaerah = false);
    }
  }

  Future<void> _pickMukim() async {
    final negeri = _negeri;
    final daerah = _daerah;
    if (negeri == null || daerah == null || _loadingMukim) return;
    final key = '$negeri|$daerah';
    var options = _mukimCache[key];
    if (options == null) {
      setState(() => _loadingMukim = true);
      try {
        options = _mukimCache[key] = await _service.mukimOf(negeri, daerah);
      } catch (_) {
        _toast('Tiada sambungan. Gagal memuatkan senarai mukim.');
        return;
      } finally {
        if (mounted) setState(() => _loadingMukim = false);
      }
    }
    if (!mounted || _negeri != negeri || _daerah != daerah) return;
    final picked = await pickMukim(
      context,
      daerah: daerah,
      options: options,
      selected: _mukim,
    );
    if (!mounted || picked == null || picked.mukim == _mukim) return;
    final mukim = picked.mukim;

    setState(() {
      _lot = null;
      _clearMukim();
      _mukim = mukim;
      _mukimBounds = mukim == null ? null : _extentCache['$key|$mukim'];
    });
    if (mukim == null || _mukimBounds != null) {
      _fitState();
      return;
    }
    setState(() => _loadingMukim = true);
    try {
      final e = await _service.extentOf(
        ArcGisService.whereForArea(negeri, daerah, mukim),
      );
      if (e == null) return;
      final bounds = LatLngBounds(LatLng(e.$1, e.$2), LatLng(e.$3, e.$4));
      _extentCache['$key|$mukim'] = bounds;
      if (mounted && _daerah == daerah && _mukim == mukim) {
        setState(() => _mukimBounds = bounds);
        _fitState();
      }
    } catch (_) {
      _toast('Gagal mencari kawasan mukim. Lot tetap ditapis.');
    } finally {
      if (mounted) setState(() => _loadingMukim = false);
    }
  }

  /// Asks for a lot number, then zooms to that lot in the picked district
  /// (and mukim) and shows its details.
  Future<void> _findLot() async {
    final negeri = _negeri;
    final daerah = _daerah;
    final mukim = _mukim;
    if (negeri == null || daerah == null || _findingLot) return;
    final lot = await showDialog<String>(
      context: context,
      builder: (_) => _LotNumberDialog(area: mukim ?? daerah),
    );
    if (lot == null || lot.trim().isEmpty || !mounted) return;
    setState(() => _findingLot = true);
    try {
      final (lots, e) = await _service.findLot(
        lot,
        negeri: negeri,
        daerah: daerah,
        mukim: mukim,
      );
      if (!mounted) return;
      if (lots.isEmpty || e == null) {
        _toast('Lot $lot tidak dijumpai di ${mukim ?? daerah}');
        return;
      }
      final bounds = LatLngBounds(LatLng(e.$1, e.$2), LatLng(e.$3, e.$4));
      setState(() {
        _lot = lots.first;
        _foundLot = lots.length == 1 ? bounds.center : null;
      });
      final target = CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(40, 180, 40, 260),
        maxZoom: 17,
      ).fit(_map.camera);
      _animateTo(target.center, target.zoom);
      if (lots.length > 1) {
        _toast(
          '${lots.length} lot bernombor $lot di $daerah. '
          'Pilih mukim untuk hasil tepat.',
        );
      }
    } catch (_) {
      _toast('Gagal mencari lot. Cuba lagi.');
    } finally {
      if (mounted) setState(() => _findingLot = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _identify(LatLng p) async {
    if (_zoom < _minLotZoom) return;
    setState(() {
      _identifying = true;
      _lot = null;
    });
    try {
      final lot = await _service.lotAt(
        p.latitude,
        p.longitude,
        negeri: _negeri,
        daerah: _daerah,
        mukim: _mukim,
      );
      if (mounted) setState(() => _lot = lot);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mendapatkan maklumat lot')),
        );
      }
    } finally {
      if (mounted) setState(() => _identifying = false);
    }
  }

  String? get _hint {
    if (_identifying) return 'Mencari lot…';
    if (_zoom >= _clearLotZoom) return null;
    if (_zoom >= _minLotZoom) {
      return 'Zum masuk lagi untuk melihat lot dengan jelas';
    }
    return _negeri == null
        ? 'Zum masuk atau pilih negeri untuk melihat lot'
        : 'Zum masuk untuk melihat lot';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final hint = _hint;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: _boundsFor(_negeri),
              padding: const EdgeInsets.fromLTRB(24, 90, 24, 120),
            ),
            minZoom: 5,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () => _ready = true,
            onPositionChanged: (camera, hasGesture) {
              // The user's finger always wins over a button animation.
              if (hasGesture && _camAnim.isAnimating) _camAnim.stop();
              // Rebuild only when the zoom crosses a level that changes
              // the lot layer or the hint, not on every frame.
              bool crossedAt(double level) =>
                  (camera.zoom >= level) != (_zoom >= level);
              final crossed =
                  crossedAt(_minLotZoom) || crossedAt(_clearLotZoom);
              _zoom = camera.zoom;
              if (crossed) setState(() {});
            },
            onTap: (_, p) => _identify(p),
          ),
          children: [
            TileLayer(
              key: ValueKey(_satellite),
              urlTemplate: _satellite
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/'
                        'World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.ppskg_app',
              maxNativeZoom: 19,
            ),
            // The real lot shapes, drawn by the RISDA server. Rebuilt when
            // the state or district changes so tiles reload with the filter.
            if (widget.active)
              TileLayer(
                key: ValueKey('lots-$_negeri-$_daerah-$_mukim'),
                tileProvider: _LotTileProvider(_negeri, _daerah, _mukim),
                tileDimension: _lotTileDimension,
                minZoom: _minLotZoom,
                maxNativeZoom: 19,
                // Load one ring of tiles past the screen edge and keep
                // recent ones, so panning and zooming back show lots at once.
                panBuffer: 1,
                keepBuffer: 4,
                tileDisplay: const TileDisplay.fadeIn(
                  duration: Duration(milliseconds: 250),
                ),
              ),
            if (_foundLot case final pin?)
              MarkerLayer(
                markers: [
                  Marker(
                    point: pin,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      size: 40,
                      color: smartGold,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ],
              ),
            SimpleAttributionWidget(
              source: Text(_satellite ? 'Esri, RISDA' : 'OpenStreetMap, RISDA'),
              backgroundColor: Colors.white70,
            ),
          ],
        ),
        Positioned(
          top: top + 10,
          left: 12,
          right: 12,
          child: Row(
            children: [
              const LocationPill(solid: true),
              const Spacer(),
              _RoundButton(
                icon: _satellite ? Icons.map_outlined : Icons.satellite_alt,
                tooltip: _satellite ? 'Peta jalan' : 'Satelit',
                onTap: () => setState(() => _satellite = !_satellite),
              ),
              const SizedBox(width: 8),
              _RoundButton(
                icon: Icons.center_focus_strong,
                tooltip: _mukim != null
                    ? 'Paparan mukim'
                    : _daerah == null
                    ? 'Paparan negeri'
                    : 'Paparan daerah',
                onTap: _fitState,
              ),
            ],
          ),
        ),
        // Narrower filters: district once a state is chosen, then mukim
        // and a lot search once a district is chosen.
        if (_negeri != null)
          Positioned(
            top: top + 62,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _AreaPill(
                    icon: Icons.map_outlined,
                    label: _daerah,
                    placeholder: 'Semua daerah',
                    loading: _loadingDaerah,
                    onTap: _pickDaerah,
                  ),
                  if (_daerah != null) ...[
                    const SizedBox(width: 8),
                    _AreaPill(
                      icon: Icons.holiday_village_outlined,
                      label: _mukim,
                      placeholder: 'Semua mukim',
                      loading: _loadingMukim,
                      onTap: _pickMukim,
                    ),
                    const SizedBox(width: 8),
                    _AreaPill(
                      icon: Icons.search,
                      label: null,
                      placeholder: 'Cari lot',
                      loading: _findingLot,
                      showArrow: false,
                      onTap: _findLot,
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (hint != null)
          Positioned(
            top: top + (_negeri == null ? 64 : 114),
            left: 0,
            right: 0,
            child: Center(child: _Hint(hint)),
          ),
        Positioned(
          right: 12,
          bottom: 40,
          child: Column(
            children: [
              _RoundButton(
                icon: Icons.add,
                tooltip: 'Zum masuk',
                onTap: () => _zoomBy(1),
              ),
              const SizedBox(height: 8),
              _RoundButton(
                icon: Icons.remove,
                tooltip: 'Zum keluar',
                onTap: () => _zoomBy(-1),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _lot == null
              ? const Align(alignment: Alignment.bottomLeft, child: _Legend())
              : _LotCard(
                  lot: _lot!,
                  onClose: () => setState(() => _lot = null),
                ),
        ),
      ],
    );
  }
}

/// Colour key for the lot shapes.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: smartBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status torehan',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final s in ['Bertoreh', 'Tidak Bertoreh', 'Getah Muda', null])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusTorehanColor(s),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(s ?? 'Tiada data', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// On-screen size of one lot tile. The RISDA server draws every tile from
/// scratch and a big tile costs about the same as a small one, so large
/// tiles mean far fewer, faster-arriving requests.
const _lotTileDimension = 512;

/// Builds each tile as a MapServer export of that tile's Web Mercator box,
/// drawn at twice its on-screen size so lots stay sharp on phone screens.
class _LotTileProvider extends NetworkTileProvider {
  final String? negeri;
  final String? daerah;
  final String? mukim;

  _LotTileProvider(this.negeri, this.daerah, this.mukim);

  static const _origin = 20037508.342789244;

  @override
  String getTileUrl(TileCoordinates c, TileLayer options) {
    // At zoom z the world is 256 * 2^z pixels wide, split into tiles of
    // options.tileDimension pixels.
    final tilesPerSide = math.pow(2, c.z) * 256 / options.tileDimension;
    final span = 2 * _origin / tilesPerSide;
    final xmin = -_origin + c.x * span;
    final ymax = _origin - c.y * span;
    return ArcGisService.exportUrl(
      xmin: xmin,
      ymin: ymax - span,
      xmax: xmin + span,
      ymax: ymax,
      size: options.tileDimension * 2,
      dpi: 192,
      negeri: negeri,
      daerah: daerah,
      mukim: mukim,
    );
  }
}

/// Brown pill in the row under the state pill: the picked district or
/// mukim (or [placeholder] when none), or the "Cari lot" action.
class _AreaPill extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String placeholder;
  final bool loading;
  final bool showArrow;
  final VoidCallback onTap;

  const _AreaPill({
    required this.icon,
    required this.label,
    required this.placeholder,
    required this.loading,
    required this.onTap,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: smartBrown,
      elevation: 3,
      shape: StadiumBorder(
        side: BorderSide(color: label == null ? Colors.white24 : smartGold),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 8, showArrow ? 6 : 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: smartGold),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  label ?? placeholder,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loading) ...[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ] else if (showArrow) ...[
                const SizedBox(width: 2),
                const Icon(Icons.expand_more, size: 18, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the lot number to find within [area]; pops with the text.
class _LotNumberDialog extends StatefulWidget {
  final String area;

  const _LotNumberDialog({required this.area});

  @override
  State<_LotNumberDialog> createState() => _LotNumberDialogState();
}

class _LotNumberDialogState extends State<_LotNumberDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final lot = _controller.text.trim();
    if (lot.isNotEmpty) Navigator.pop(context, lot);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFFFFDF9),
      surfaceTintColor: Colors.transparent,
      title: const Text('Cari lot'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Di ${widget.area}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: smartMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: 'No. Lot, cth: 2942',
              prefixIcon: Icon(Icons.tag, size: 20),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Cari')),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: smartBrown,
      shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onTap,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;

  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: smartBrown.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: Colors.white),
      ),
    );
  }
}

/// Details of the tapped lot.
class _LotCard extends StatelessWidget {
  final LotRecord lot;
  final VoidCallback onClose;

  const _LotCard({required this.lot, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusTorehanColor(lot.statusTorehan);
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
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

    return Material(
      color: const Color(0xFFFFFDF9),
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    lot.nama,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(
                lot.statusTorehan ?? 'Tiada data',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            row('No. KP', lot.formattedNokp),
            row('No. Lot', lot.noLot),
            row('Jenis geran', lot.jenisGeran),
            row('Mukim', lot.mukim),
            row('Lokasi', '${lot.daerah}, ${lot.negeri}'),
            row('Luas', '${lot.luas.toStringAsFixed(4)} hektar'),
            if (lot.namaPengawai != null) row('Pegawai', lot.namaPengawai!),
          ],
        ),
      ),
    );
  }
}
