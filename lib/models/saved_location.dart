// lib/models/saved_location.dart
// ─────────────────────────────────────────────────────────────────────────────
// Data model for a GPS location saved by the user on the offline map screen.
// Survivors and first-responders can mark shelters, hazards, or their current
// SOS position.  All locations are stored in SQLite — no cloud sync required.

class SavedLocation {
  final int? id;
  final String label;       // User-provided name for this pin
  final double latitude;
  final double longitude;
  final String type;        // 'sos' | 'hospital' | 'shelter' | 'water' | 'police' | 'hazard' | 'custom'
  final int? capacity;      // Capacity for shelters/hospitals
  final DateTime savedAt;

  const SavedLocation({
    this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.type = 'custom',
    this.capacity,
    required this.savedAt,
  });

  SavedLocation copyWith({
    int? id,
    String? label,
    double? latitude,
    double? longitude,
    String? type,
    int? capacity,
    DateTime? savedAt,
  }) {
    return SavedLocation(
      id: id ?? this.id,
      label: label ?? this.label,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      capacity: capacity ?? this.capacity,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  // ── SQLite serialisation ────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'type': type,
        'capacity': capacity,
        'saved_at': savedAt.toIso8601String(),
      };

  factory SavedLocation.fromMap(Map<String, dynamic> map) => SavedLocation(
        id: map['id'] as int?,
        label: map['label'] as String,
        latitude: map['latitude'] as double,
        longitude: map['longitude'] as double,
        type: map['type'] as String,
        capacity: map['capacity'] as int?,
        savedAt: DateTime.parse(map['saved_at'] as String),
      );

  /// Returns a formatted coordinate string for radio / SMS SOS communication.
  String get coordinateString =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}
