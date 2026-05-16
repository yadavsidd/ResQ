// lib/screens/map_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// MapScreen — offline map powered by flutter_map with OpenStreetMap tiles.
//
// Features:
//   • Displays current GPS position as a pulsing SOS marker
//   • Shows all saved location pins stored in SQLite
//   • Long-press to drop a custom pin; choose type (SOS/Shelter/Hazard)
//   • Tap the SOS button to copy coordinates to clipboard for radio/SMS
//   • Map tiles must be pre-cached — no internet required during use
//
// Note: For full offline tile support, pre-download tiles using a tool such as
// flutter_map_tile_caching and bundle them in assets/maps/, or direct flutter_map
// to use a local MBTiles file via a custom TileProvider.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/saved_location.dart';
import '../services/app_state.dart';
import '../widgets/offline_badge.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  bool _locating = false;
  StreamSubscription<Position>? _posSub;
  
  // Download progress tracking
  double? _downloadProgress;

  // Default fallback center (New Delhi, India)
  static const LatLng _defaultCenter = LatLng(28.6139, 77.2090);

  @override
  void initState() {
    super.initState();
    _fetchLocation();
    
    // Continuous Live GPS marker updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _posSub = context.read<AppState>().location.getPositionStream(distanceFilter: 10).listen((pos) {
        if (mounted) setState(() => _currentPosition = pos);
      });
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    final pos = await context.read<AppState>().location.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = pos;
        _locating = false;
      });
      if (pos != null) {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
      }
    }
  }

  LatLng get _center => _currentPosition != null
      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
      : _defaultCenter;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.map_rounded, color: colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(state.t('map_title'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          const OfflineBadge(),
          const SizedBox(width: 4),
          // Locate me button
          IconButton(
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
            tooltip: state.t('map_my_location'),
            onPressed: _fetchLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13,
              onLongPress: (tapPos, latlng) =>
                  _showAddPinDialog(context, state, latlng),
            ),
            children: [
              // Tile layer with FMTC integration
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.resq.app',
                maxZoom: 19,
                tileProvider: FMTCStore('jaipur').getTileProvider(),
              ),
              // Saved location markers
              MarkerLayer(
                markers: [
                  // Current position
                  if (_currentPosition != null)
                    Marker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      width: 48,
                      height: 48,
                      child: _PulsingDot(color: colorScheme.primary),
                    ),
                  // Saved pins
                  ...state.savedLocations.map((loc) => Marker(
                        point: LatLng(loc.latitude, loc.longitude),
                        width: 40,
                        height: 40,
                        child: _LocationPin(
                          type: loc.type,
                          onTap: () => _showPinDetail(context, state, loc),
                        ),
                      )),
                ],
              ),
            ],
          ),

          // ── Download Map Floating Bar ─────────────────────────────────────
          Positioned(
            top: 16,
            left: 16,
            child: FloatingActionButton.extended(
              onPressed: _downloadRegion,
              backgroundColor: colorScheme.surface,
              icon: _downloadProgress != null
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: _downloadProgress, strokeWidth: 2))
                  : Icon(Icons.download_rounded, color: colorScheme.primary),
              label: Text(
                _downloadProgress != null
                    ? 'Downloading... ${(_downloadProgress! * 100).toStringAsFixed(0)}%'
                    : 'Download Region',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ),
          ),

          // ── SOS Coordinates Panel ─────────────────────────────────────────
          if (_currentPosition != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _SosPanel(
                position: _currentPosition!,
                state: state,
              ),
            ),

          // ── No location warning ──────────────────────────────────────────
          if (_currentPosition == null && !_locating)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.location_off_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GPS unavailable. Enable location to see your position.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── FMTC Download Task ───────────────────────────────────────────────────

  Future<void> _downloadRegion() async {
    final bounds = _mapController.camera.visibleBounds;
    final region = RectangleRegion(bounds);
    
    final store = FMTCStore('jaipur');
    final downloadableRegion = region.toDownloadable(
      minZoom: 10,
      maxZoom: 15,
      options: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.resq.app',
      ),
    );
    final download = store.download.startForeground(
      region: downloadableRegion,
    );

    download.listen((progress) {
      if (mounted && progress.percentageProgress != null) {
        setState(() => _downloadProgress = progress.percentageProgress! / 100);
      }
    }, onDone: () {
      if (mounted) setState(() => _downloadProgress = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline map region downloaded successfully!'))
      );
    }, onError: (e) {
      if (mounted) setState(() => _downloadProgress = null);
    });
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _showAddPinDialog(
      BuildContext ctx, AppState state, LatLng latlng) async {
    String label = '';
    String type = 'custom';

    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (bctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(bctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Map Pin',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                  labelText: 'Label', border: OutlineInputBorder()),
              onChanged: (v) => label = v,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(
                  labelText: 'Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'sos', child: Text('🆘 SOS')),
                DropdownMenuItem(value: 'shelter', child: Text('🏠 Shelter')),
                DropdownMenuItem(value: 'hazard', child: Text('⚠️ Hazard')),
                DropdownMenuItem(value: 'custom', child: Text('📌 Custom')),
              ],
              onChanged: (v) => type = v ?? 'custom',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await state.saveLocation(SavedLocation(
                    label: label.isEmpty
                        ? '${latlng.latitude.toStringAsFixed(4)}, ${latlng.longitude.toStringAsFixed(4)}'
                        : label,
                    latitude: latlng.latitude,
                    longitude: latlng.longitude,
                    type: type,
                    savedAt: DateTime.now(),
                  ));
                  if (bctx.mounted) Navigator.pop(bctx);
                },
                child: const Text('Save Pin'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showPinDetail(BuildContext ctx, AppState state, SavedLocation loc) {
    // Calculate distance if GPS is available
    String distanceStr = '';
    if (_currentPosition != null) {
      final m = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        loc.latitude, loc.longitude,
      );
      if (m > 1000) {
        distanceStr = '${(m / 1000).toStringAsFixed(1)} km away';
      } else {
        distanceStr = '${m.toStringAsFixed(0)} m away';
      }
    }

    showModalBottomSheet(
      context: ctx,
      builder: (bctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.label,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.category_rounded, size: 16, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 6),
                Text(loc.type.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            if (loc.capacity != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.people_alt_rounded, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text('Capacity: ${loc.capacity}', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ],
            if (distanceStr.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.social_distance_rounded, size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(distanceStr, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ],
            const SizedBox(height: 20),
            
            // AI Action
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.smart_toy_rounded),
                label: Text('Ask ResQ AI about ${loc.label.split(" ").first}'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.grey.shade900,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: () {
                  Navigator.pop(bctx);
                  state.switchTab(0);
                  state.sendMessageStreaming('What should I bring to reach ${loc.label} safely?');
                },
              ),
            ),
            const SizedBox(height: 10),
            
            // Delete Action
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_rounded, color: Colors.red),
                label: const Text('Delete Pin', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(0, 48),
                ),
                onPressed: () {
                  state.deleteLocation(loc.id!);
                  Navigator.pop(bctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Internal widgets ──────────────────────────────────────────────────────────

class _SosPanel extends StatelessWidget {
  final Position position;
  final AppState state;

  const _SosPanel({required this.position, required this.state});

  @override
  Widget build(BuildContext context) {
    final coords = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade900,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              const Text('YOUR SOS POSITION',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'LAT: ${position.latitude.toStringAsFixed(4)}  LON: ${position.longitude.toStringAsFixed(4)}',
            style: const TextStyle(color: Colors.yellowAccent, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: coords));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coordinates copied to clipboard!')));
                  },
                  icon: const Icon(Icons.copy_rounded, color: Colors.red, size: 18),
                  label: const Text('COPY', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(0, 48)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    final uri = Uri(scheme: 'sms', queryParameters: {'body': 'SOS! I need help. My exact location is: $coords'});
                    launchUrl(uri);
                  },
                  icon: const Icon(Icons.sms_rounded, color: Colors.white, size: 18),
                  label: const Text('SEND SMS', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(backgroundColor: Colors.black45, minimumSize: const Size(0, 48)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _scale,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                  color: widget.color.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2),
            ],
          ),
        ),
      );
}

class _LocationPin extends StatelessWidget {
  final String type;
  final VoidCallback onTap;

  const _LocationPin({required this.type, required this.onTap});

  Color get _color {
    switch (type) {
      case 'sos': return Colors.red;
      case 'hospital': return Colors.red.shade800;
      case 'shelter': return Colors.blue.shade800;
      case 'water': return Colors.lightBlue;
      case 'police': return Colors.indigo;
      case 'hazard': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData get _icon {
    switch (type) {
      case 'sos': return Icons.sos_rounded;
      case 'hospital': return Icons.local_hospital_rounded;
      case 'shelter': return Icons.house_rounded;
      case 'water': return Icons.water_drop_rounded;
      case 'police': return Icons.local_police_rounded;
      case 'hazard': return Icons.warning_rounded;
      default: return Icons.location_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _color.withOpacity(0.95),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Center(child: Icon(_icon, color: Colors.white, size: 20)),
        ),
      );
}
