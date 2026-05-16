// lib/models/checklist_item.dart
// ─────────────────────────────────────────────────────────────────────────────
// Data model for a single item in the AI-generated emergency checklist.
// Gemma 4 personalises checklist content based on the user's described
// situation (e.g. "earthquake, family of 4, urban area").  Items are
// persisted in SQLite so progress survives power loss or app restarts.

class ChecklistItem {
  final int? id;          // SQLite row id
  final String text;      // Checklist item description
  bool isChecked;         // Whether the user has ticked it off
  final int sessionId;    // Groups items belonging to the same generation session
  final DateTime createdAt;

  ChecklistItem({
    this.id,
    required this.text,
    this.isChecked = false,
    required this.sessionId,
    required this.createdAt,
  });

  // ── SQLite serialisation ────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'is_checked': isChecked ? 1 : 0,
        'session_id': sessionId,
        'created_at': createdAt.toIso8601String(),
      };

  factory ChecklistItem.fromMap(Map<String, dynamic> map) => ChecklistItem(
        id: map['id'] as int?,
        text: map['text'] as String,
        isChecked: (map['is_checked'] as int) == 1,
        sessionId: map['session_id'] as int,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  ChecklistItem copyWith({bool? isChecked}) => ChecklistItem(
        id: id,
        text: text,
        isChecked: isChecked ?? this.isChecked,
        sessionId: sessionId,
        createdAt: createdAt,
      );
}
