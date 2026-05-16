// lib/services/location_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// LocationService — provides GPS coordinate retrieval via geolocator.
//
// Offline-first design:
//   • GPS works without internet — it uses satellite signals.
//   • Coordinates displayed to users are formatted for radio/SMS SOS use.
//   • Permissions are requested at runtime on both Android and iOS.

import 'package:geolocator/geolocator.dart';

class LocationService {
  Position? _lastKnownPosition;
  Position? get lastKnownPosition => _lastKnownPosition;

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Checks and requests location permission.
  /// Returns true if permission was granted.
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // ── Position ───────────────────────────────────────────────────────────────

  /// Returns the current GPS position.  Caches the result in [_lastKnownPosition].
  ///
  /// [accuracy] defaults to high for emergency use cases.
  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    try {
      final hasPermission = await requestPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy),
      );
      _lastKnownPosition = position;
      return position;
    } catch (e) {
      // Return cached position if a fresh fix fails (e.g. indoors).
      return _lastKnownPosition;
    }
  }

  /// Returns a stream of periodic location updates.
  /// Useful for live tracking on the Map screen.
  Stream<Position> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10, // metres
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    );
  }

  // ── Formatting ─────────────────────────────────────────────────────────────

  /// Formats a [Position] as a plain coordinate string for SOS radio/SMS use.
  /// Example output: "19.075983, 72.877655"
  static String formatPosition(Position pos) =>
      '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';

  /// Computes straight-line distance (metres) between two positions.
  static double distanceBetween(Position a, Position b) =>
      Geolocator.distanceBetween(
          a.latitude, a.longitude, b.latitude, b.longitude);
}
