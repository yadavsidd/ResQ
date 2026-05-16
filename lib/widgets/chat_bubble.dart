// lib/widgets/chat_bubble.dart
// ─────────────────────────────────────────────────────────────────────────────
// ChatBubble — renders a single chat message with different styling for user
// vs. AI assistant messages.  Includes a TTS speak button on AI bubbles so
// users with accessibility needs can hear responses read aloud.

import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/tts_service.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final TtsService tts;

  const ChatBubble({super.key, required this.message, required this.tts});

  bool get _isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 8,
          bottom: 8,
          left: _isUser ? 48 : 8,
          right: _isUser ? 8 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isUser ? Colors.orange.shade800 : Colors.grey.shade900,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: _isUser ? const Radius.circular(12) : Radius.zero,
            bottomRight: _isUser ? Radius.zero : const Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Message text (Minimum 16sp)
            Text(
              message.text.isEmpty && !_isUser ? '...' : message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            
            // Layout bottom row for Timestamp & TTS
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                if (!_isUser) ...[
                  const SizedBox(width: 8),
                  // Minimum 48x48 tap target for TTS
                  ClipOval(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => tts.toggle(message.text),
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.volume_up_rounded,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
