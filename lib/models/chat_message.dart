// lib/models/chat_message.dart
// ─────────────────────────────────────────────────────────────────────────────
// Data model for a single chat message exchanged between the user and the
// on-device Gemma 4 AI assistant.  Stored in SQLite so conversations persist
// across app restarts — essential for offline disaster scenarios.

/// Roles that a message can belong to.
enum MessageRole { user, assistant }

/// Represents one turn in the AI chat conversation.
class ChatMessage {
  final int? id;            // SQLite row id (null for unsaved messages)
  final String text;        // The message content
  final MessageRole role;   // Who sent it: user or the AI assistant
  final DateTime timestamp; // When it was created (local device time)

  const ChatMessage({
    this.id,
    required this.text,
    required this.role,
    required this.timestamp,
  });

  // ── SQLite serialisation ────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'role': role.name,           // e.g. 'user' or 'assistant'
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] as int?,
        text: map['text'] as String,
        role: MessageRole.values.firstWhere((r) => r.name == map['role']),
        timestamp: DateTime.parse(map['timestamp'] as String),
      );

  ChatMessage copyWith({int? id, String? text, MessageRole? role, DateTime? timestamp}) =>
      ChatMessage(
        id: id ?? this.id,
        text: text ?? this.text,
        role: role ?? this.role,
        timestamp: timestamp ?? this.timestamp,
      );
}
