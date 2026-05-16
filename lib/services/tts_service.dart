// lib/services/tts_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// TtsService — wraps flutter_tts to provide offline text-to-speech.
//
// Accessibility rationale:
//   • Survivors with visual impairments or in dark/smoke-filled environments
//     cannot always read the screen.  TTS reads AI responses aloud.
//   • Works entirely on-device — no network required.
//
// Language support:
//   • English ('en-US') and Hindi ('hi-IN') are pre-installed on most
//     Android and iOS devices.  We switch language based on the active locale.

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> init() async {
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.5);  // Slightly slower for clarity in noisy environments
    await _tts.setPitch(1.0);
    await setLanguage('en');

    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setCancelHandler(() => _isSpeaking = false);
    _tts.setErrorHandler((_) => _isSpeaking = false);
  }

  /// Sets the TTS language.  Accepts 'en' or 'hi'.
  Future<void> setLanguage(String langCode) async {
    final locale = langCode == 'hi' ? 'hi-IN' : 'en-US';
    await _tts.setLanguage(locale);
  }

  // ── Control ────────────────────────────────────────────────────────────────

  /// Speaks [text] aloud.  Stops any currently playing speech first.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await stop();
    await _tts.speak(text);
  }

  /// Stops ongoing speech immediately.
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  /// Toggles speech: starts speaking if silent, stops if already speaking.
  Future<void> toggle(String text) async {
    if (_isSpeaking) {
      await stop();
    } else {
      await speak(text);
    }
  }

  void dispose() {
    _tts.stop();
  }
}
