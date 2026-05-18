// lib/services/gemma_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// GemmaService — on-device Gemma inference via Google MediaPipe LLM Inference.
//
// Architecture
// ────────────
//   • Flutter calls native Kotlin via MethodChannel "resq/gemma".
//     The Kotlin side uses com.google.mediapipe:tasks-genai to load and
//     run the downloaded gemma-4-e2b.tflite model on the GPU/CPU.
//   • streamResponse() opens EventChannel "resq/gemma_stream", passing
//     the full formatted prompt as the argument. The Kotlin side calls
//     generateResponseAsync() and emits each token back across the channel.
//   • If the model file is absent, AiMode.offlineCache is used and all
//     inference is delegated to OfflineDbService.
//
// Gemma chat template
// ────────────────────
//   <start_of_turn>system\n<system_prompt>\n<end_of_turn>\n
//   <start_of_turn>user\n<message>\n<end_of_turn>\n
//   <start_of_turn>model\n

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'offline_db_service.dart';

// ── AI mode ───────────────────────────────────────────────────────────────────

/// Tracks whether Gemma is running on-device or falling back to cached Q&A.
enum AiMode {
  loading,        // Still initialising
  gemmaOnDevice,  // Gemma loaded via MediaPipe, all inference on-device
  offlineCache,   // Model unavailable — using SQLite Q&A fallback
}

// ── Service ───────────────────────────────────────────────────────────────────

class GemmaService {
  // ── Constants ──────────────────────────────────────────────────────────────

  static const _modelFileName = 'gemma-4-e2b.tflite';

  // Native platform channels
  static const _methodChannel = MethodChannel('resq/gemma');
  static const _eventChannel  = EventChannel('resq/gemma_stream');

  /// System prompt that grounds the model in emergency response behaviour.
  static const String systemPrompt =
      'You are ResQ, an emergency response AI. The user may be in a '
      'life-threatening disaster situation. Respond with calm, clear, '
      'numbered steps. Prioritize life safety. Keep responses under '
      '150 words unless critical detail is needed. You work fully '
      'offline — never tell the user to check online.';

  // ── State ──────────────────────────────────────────────────────────────────

  AiMode _mode = AiMode.loading;
  AiMode get mode => _mode;

  bool isEnabled = true;

  bool get isReady   => _mode == AiMode.gemmaOnDevice && isEnabled;
  bool get isLoading => _mode == AiMode.loading;

  // isInterpreterRunning is true only when MediaPipe native engine is active and enabled.
  bool _nativeReady = false;
  bool get isInterpreterRunning => _nativeReady && isEnabled;

  // Performance telemetry (populated during generation)
  double timeToFirstTokenMs = 0.0;
  double tokensPerSecond    = 0.0;
  double ramAllocationMB    = 1340.0;

  OfflineDbService? _offlineDb;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Initialises the MediaPipe engine from the downloaded documents directory.
  /// Falls back to [offlineDb] if the model file is missing or load fails.
  Future<bool> init(OfflineDbService offlineDb) async {
    _offlineDb  = offlineDb;
    _nativeReady = false;
    _mode = AiMode.loading;

    try {
      final modelPath = await _getModelPath();

      _log('Initialising MediaPipe LLM engine from: $modelPath');

      final success = await _methodChannel.invokeMethod<bool>(
        'initialize',
        {'modelPath': modelPath},
      ) ?? false;

      if (success) {
        _nativeReady = true;
        _mode = AiMode.gemmaOnDevice;
        _log('Gemma engine ready — on-device inference active');
        return true;
      } else {
        throw Exception('Native initialize() returned false');
      }
    } on PlatformException catch (e) {
      _log('MediaPipe init failed [${e.code}]: ${e.message}');
      _mode = AiMode.offlineCache;
      return false;
    } catch (e) {
      _log('Model init error: $e');
      _mode = AiMode.offlineCache;
      return false;
    }
  }

  /// Locates the .tflite model in internal or external storage directories.
  Future<String> _getModelPath() async {
    // 1. Try secure internal storage
    final internalDir = await getApplicationDocumentsDirectory();
    final internalPath = p.join(internalDir.path, _modelFileName);
    final internalFile = File(internalPath);
    if (internalFile.existsSync() && await internalFile.length() > 1000000000) {
      return internalPath;
    }

    // 2. Try app-specific external storage documents directory
    try {
      final externalDirs = await getExternalStorageDirectories(type: StorageDirectory.documents);
      if (externalDirs != null) {
        for (final dir in externalDirs) {
          final path = p.join(dir.path, _modelFileName);
          final file = File(path);
          if (file.existsSync() && await file.length() > 1000000000) {
            return path;
          }
        }
      }
    } catch (_) {}

    // 3. Try app-specific external files directory
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final path = p.join(externalDir.path, _modelFileName);
        final file = File(path);
        if (file.existsSync() && await file.length() > 1000000000) {
          return path;
        }
      }
    } catch (_) {}

    throw Exception('Model file missing or corrupt. Sideload via USB or download via Onboarding.');
  }

  // ── Inference — Streaming ──────────────────────────────────────────────────

  /// Streams the AI response token-by-token.
  /// Falls back to [OfflineDbService] if the model is not loaded.
  Stream<String> streamResponse(
    String userMessage, {
    List<Map<String, String>>? history,
  }) {
    final controller = StreamController<String>();

    if (!_nativeReady || !isEnabled) {
      _streamFromFallback(userMessage, controller);
    } else {
      _streamFromGemma(userMessage, history, controller);
    }

    return controller.stream;
  }

  /// Streams tokens from the real MediaPipe native engine.
  void _streamFromGemma(
    String userMessage,
    List<Map<String, String>>? history,
    StreamController<String> ctrl,
  ) {
    final prompt = _buildPrompt(userMessage, history);
    final stopwatch = Stopwatch()..start();
    bool firstToken = true;
    int tokenCount  = 0;

    // Listen to the EventChannel — Kotlin streams one event per token.
    _eventChannel.receiveBroadcastStream(prompt).listen(
      (dynamic token) {
        final text = token as String;
        if (firstToken) {
          timeToFirstTokenMs = stopwatch.elapsedMilliseconds.toDouble();
          firstToken = false;
        }
        tokenCount++;
        ctrl.add(text);
      },
      onDone: () {
        final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
        if (elapsed > 0 && tokenCount > 0) {
          tokensPerSecond = tokenCount / elapsed;
        }
        ctrl.close();
      },
      onError: (Object err) {
        _log('Native stream error: $err — falling back to offline DB');
        _streamFromFallback(userMessage, ctrl);
      },
      cancelOnError: false,
    );
  }

  /// Streams from the offline SQLite knowledge base with a word-delay effect.
  void _streamFromFallback(
    String userMessage,
    StreamController<String> ctrl,
  ) async {
    try {
      String answer;
      if (_offlineDb != null) {
        final pair = await _offlineDb!.fuzzySearch(userMessage);
        if (pair != null) {
          final isHindi = RegExp(r'[\u0900-\u097F]').hasMatch(userMessage);
          answer = isHindi ? pair.answerHi : pair.answerEn;
        } else {
          answer = _hardcodedFallback(userMessage);
        }
      } else {
        answer = _hardcodedFallback(userMessage);
      }

      final words = answer.split(' ');
      for (int i = 0; i < words.length; i++) {
        ctrl.add(i == words.length - 1 ? words[i] : '${words[i]} ');
        await Future.delayed(const Duration(milliseconds: 30));
      }
    } catch (e) {
      ctrl.add('Unable to generate a response. Please consult the First Aid guide.');
    } finally {
      ctrl.close();
    }
  }

  // ── Inference — Non-streaming ──────────────────────────────────────────────

  /// Convenience wrapper: collects the full stream into a single string.
  Future<String> generateText({
    required String prompt,
    List<Map<String, String>>? history,
  }) async {
    final buf = StringBuffer();
    await for (final chunk in streamResponse(prompt, history: history)) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  /// Fallback inference via OfflineDbService fuzzy search.
  Future<String> generateTextFallback(String query) async {
    if (_offlineDb != null) {
      final pair = await _offlineDb!.fuzzySearch(query);
      if (pair != null) {
        final isHindi = RegExp(r'[\u0900-\u097F]').hasMatch(query);
        return isHindi ? pair.answerHi : pair.answerEn;
      }
    }
    return _hardcodedFallback(query);
  }

  // ── Prompt builder ─────────────────────────────────────────────────────────

  String _buildPrompt(String userMessage, List<Map<String, String>>? history) {
    final buf = StringBuffer();

    buf.write('<start_of_turn>system\n');
    buf.write(systemPrompt);
    buf.write('\n<end_of_turn>\n');

    for (final turn in history ?? []) {
      final role = turn['role'] == 'assistant' ? 'model' : 'user';
      buf.write('<start_of_turn>$role\n');
      buf.write(turn['text'] ?? '');
      buf.write('\n<end_of_turn>\n');
    }

    buf.write('<start_of_turn>user\n');
    buf.write(userMessage);
    buf.write('\n<end_of_turn>\n');
    buf.write('<start_of_turn>model\n');

    return buf.toString();
  }

  // ── Hard-coded last-resort fallback ───────────────────────────────────────

  String _hardcodedFallback(String query) {
    final q = query.toLowerCase();
    if (q.contains('bleed') || q.contains('blood') || q.contains('wound')) {
      return '1. Apply firm direct pressure with a clean cloth.\n'
          '2. Do not remove cloth if soaked — add more on top.\n'
          '3. Elevate injured limb above heart level.\n'
          '4. For severe limb bleeding apply tourniquet 2–3 inches above wound.';
    }
    if (q.contains('cpr') || q.contains('heart') || q.contains('chest')) {
      return '1. Push hard on centre of chest — 100–120 compressions/min.\n'
          '2. After 30 compressions, give 2 rescue breaths.\n'
          '3. Continue until help arrives.';
    }
    if (q.contains('water') || q.contains('drink') || q.contains('dehydrat')) {
      return '1. Boil water for 1 minute before drinking.\n'
          '2. If no fuel: add 2 drops bleach per litre, wait 30 min.\n'
          '3. Sip small amounts frequently.';
    }
    if (q.contains('fire') || q.contains('burn')) {
      return '1. Cool burn under cool (not cold) running water for 20 min.\n'
          '2. Do not use ice, butter, or toothpaste.\n'
          '3. Cover loosely with a clean bandage.';
    }
    return 'Stay calm. Assess your immediate surroundings for hazards. '
        'Call for help if possible. Consult the First Aid guide for specific instructions.';
  }

  /// Releases any native resources held by the engine.
  Future<void> dispose() async {
    // Native GemmaEngine.close() is called in MainActivity.onDestroy().
    // No additional cleanup needed from the Dart side.
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[GemmaService] $msg');
  }
}
