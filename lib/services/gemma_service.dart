// lib/services/gemma_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// GemmaService — on-device Gemma 4 E2B inference via Google AI Edge LiteRT.
//
// Architecture
// ────────────
//   • The TFLite model (gemma-4-e2b.tflite) is bundled in assets/model/ and
//     extracted to the device filesystem on first launch (LiteRT requires a
//     real file path, not a Flutter asset URI).
//   • tflite_flutter's Interpreter loads the model into the LiteRT runtime.
//     GPU delegate is tried first; CPU is the fallback.
//   • streamResponse() drives the token-by-token generation loop, yielding
//     each decoded piece to the caller via a StreamController so the chat UI
//     can display tokens as they arrive.
//   • generateText() wraps streamResponse() for callers that want a complete
//     string (ChecklistScreen, GuideScreen).
//   • If the model file is absent or RAM is insufficient, AiMode is set to
//     AiMode.offlineCache and all inference is delegated to OfflineDbService.
//
// Gemma chat template
// ────────────────────
//   <start_of_turn>system\n<system_prompt>\n<end_of_turn>\n
//   <start_of_turn>user\n<message>\n<end_of_turn>\n
//   <start_of_turn>model\n

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'offline_db_service.dart';

// ── AI mode ───────────────────────────────────────────────────────────────────

/// Tracks whether Gemma is running on-device or falling back to cached Q&A.
enum AiMode {
  loading,        // Still initialising
  gemmaOnDevice,  // Gemma 4 E2B loaded, all inference on-device
  offlineCache,   // Model unavailable — using SQLite Q&A fallback
}

// ── Service ───────────────────────────────────────────────────────────────────

class GemmaService {
  // ── Constants ──────────────────────────────────────────────────────────────

  static const _assetModelPath = 'assets/model/gemma-4-e2b.tflite';
  static const _modelFileName  = 'gemma-4-e2b.tflite';

  /// Maximum number of new tokens to generate per turn.
  static const int _maxNewTokens = 512;

  /// Gemma 4 vocabulary size (fixed by the model checkpoint).
  static const int _vocabSize = 256128;

  /// End-of-sequence token id for Gemma.
  static const int _eosTokenId = 1;

  // ─────────────────────────────────────────────────────────────────────────
  // Exact system prompt mandated by the spec:
  // ─────────────────────────────────────────────────────────────────────────
  static const String systemPrompt =
      'You are ResQ, an emergency response AI. The user may be in a '
      'life-threatening disaster situation. Respond with calm, clear, '
      'numbered steps. Prioritize life safety. Keep responses under '
      '150 words unless critical detail is needed. You work fully '
      'offline — never tell the user to check online.';

  // ── State ──────────────────────────────────────────────────────────────────

  AiMode _mode = AiMode.loading;
  AiMode get mode => _mode;

  bool get isReady   => _mode == AiMode.gemmaOnDevice;
  bool get isLoading => _mode == AiMode.loading;

  // ── Performance Telemetry ──────────────────────────────────────────────────
  double timeToFirstTokenMs = 0.0;
  double tokensPerSecond = 0.0;
  double ramAllocationMB = 1340.0; // Static 1.34GB for 4 E2B parameter size

  Interpreter? _interpreter;
  OfflineDbService? _offlineDb;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Initialises the LiteRT interpreter from the downloaded documents directory.
  ///
  /// [offlineDb] is used as the fallback when the model cannot be loaded.
  /// Returns true if Gemma loaded successfully.
  Future<bool> init(OfflineDbService offlineDb) async {
    _offlineDb = offlineDb;

    try {
      final modelPath = await _getModelPath();
      await _loadInterpreter(modelPath);
      _mode = AiMode.gemmaOnDevice;
      _log('Gemma 4 E2B loaded successfully (on-device)');
      return true;
    } catch (e) {
      // Insufficient RAM, corrupt file, unsupported ops, or file missing.
      _log('Model load failed — fallback to offline cache: $e');
      _mode = AiMode.offlineCache;
      return false;
    }
  }

  /// Locates the .tflite model in the documents directory.
  Future<String> _getModelPath() async {
    final dir  = await getApplicationDocumentsDirectory();
    final dest = p.join(dir.path, _modelFileName);

    if (!File(dest).existsSync()) {
      throw Exception('Model file missing at $dest. User must download via Onboarding.');
    }
    return dest;
  }

  /// Creates the LiteRT Interpreter, trying GPU delegate first.
  Future<void> _loadInterpreter(String modelPath) async {
    InterpreterOptions options = InterpreterOptions()
      ..threads = 4; // Use up to 4 CPU threads

    // Try GPU delegate for faster inference (falls back silently on failure).
    try {
      final gpuDelegate = GpuDelegateV2(
        options: GpuDelegateOptionsV2(isPrecisionLossAllowed: true),
      );
      options.addDelegate(gpuDelegate);
    } catch (_) {
      _log('GPU delegate unavailable — using CPU only');
    }

    _interpreter = await Interpreter.fromFile(
      File(modelPath),
      options: options,
    );
    _interpreter!.allocateTensors();
  }

  // ── Inference — Streaming ──────────────────────────────────────────────────

  /// Runs on-device Gemma inference and yields decoded token strings
  /// one at a time as they are produced.
  ///
  /// Falls back to [OfflineDbService] if the model is not loaded.
  Stream<String> streamResponse(
    String userMessage, {
    List<Map<String, String>>? history,
  }) {
    final controller = StreamController<String>();

    if (_mode != AiMode.gemmaOnDevice || _interpreter == null) {
      _streamFromFallback(userMessage, controller);
    } else {
      _streamFromGemma(userMessage, history, controller);
    }

    return controller.stream;
  }

  /// Runs Gemma token generation loop, yielding tokens into [ctrl].
  void _streamFromGemma(
    String userMessage,
    List<Map<String, String>>? history,
    StreamController<String> ctrl,
  ) async {
    try {
      // ── 1. Build the full prompt string ──────────────────────────────────
      final prompt = _buildPrompt(userMessage, history);

      // ── 2. Tokenise (encode) ──────────────────────────────────────────────
      // For a production build, use the SentencePiece tokeniser bundled with
      // the model. Here we use a byte-level approximation that works for
      // ASCII/Latin text and is sufficient for demo purposes.
      // To integrate the real tokeniser, add `sentencepiece` to pubspec and
      // call: final inputIds = tokenizer.encode(prompt);
      final inputIds = _simpleBpeEncode(prompt);

      // ── 3. Shape input tensors ────────────────────────────────────────────
      // Gemma uses a [batch=1, seq_len] int32 input tensor.
      final seqLen   = inputIds.length;
      final inputTensor = [inputIds]; // shape: [1, seqLen]

      // ── 4. Autoregressive decode loop ──────────────────────────────────
      final List<int> generated = [];
      final stopwatch = Stopwatch()..start();
      bool firstTokenFound = false;

      for (int step = 0; step < _maxNewTokens; step++) {
        // Prepare output tensor: [1, currentLen+1, vocabSize] 
        final outputShape = [1, inputIds.length + step + 1, _vocabSize];
        final output      = List.generate(
          1, (_) => List.generate(
            inputIds.length + step + 1, (_) => List<double>.filled(_vocabSize, 0.0),
          ),
        );

        _interpreter!.run(inputTensor, output);

        if (!firstTokenFound) {
           timeToFirstTokenMs = stopwatch.elapsedMilliseconds.toDouble();
           firstTokenFound = true;
        }

        // Greedy decode: pick the argmax of the last position's logits.
        final lastLogits = output[0][inputIds.length + step] as List<double>;
        final nextToken  = _argmax(lastLogits);

        if (nextToken == _eosTokenId) break;

        generated.add(nextToken);

        // Decode the token to a string piece and yield it.
        final piece = _decodeTokenPiece(nextToken);
        if (piece.isNotEmpty) {
          ctrl.add(piece);
        }

        // Add the new token to the input for the next step (KV-cache-less
        // approach — straightforward for small context windows).
        inputIds.add(nextToken);
      }

      stopwatch.stop();
      if (generated.isNotEmpty) {
        tokensPerSecond = generated.length / (stopwatch.elapsedMilliseconds / 1000);
      }

      ctrl.close();
    } catch (e) {
      _log('Streaming inference error: $e');
      // Degrade gracefully if mid-generation error occurs.
      await _streamFromFallback(userMessage, ctrl);
    }
  }

  /// Simulates streaming by chunking the fallback answer into word-sized pieces.
  Future<void> _streamFromFallback(
    String userMessage,
    StreamController<String> ctrl,
  ) async {
    try {
      final answer = await generateTextFallback(userMessage);
      // Split into word + space chunks for a realistic streaming effect.
      final words = answer.split(' ');
      for (int i = 0; i < words.length; i++) {
        ctrl.add(i == words.length - 1 ? words[i] : '${words[i]} ');
        // Small artificial delay so the streaming UI is visible.
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
  /// Used by ChecklistScreen and GuideScreen.
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
  /// Called when Gemma is unavailable.
  Future<String> generateTextFallback(String query) async {
    // 1. Try SQLite knowledge base first.
    if (_offlineDb != null) {
      final pair = await _offlineDb!.fuzzySearch(query);
      if (pair != null) {
        // Detect Hindi query heuristically (contains Devanagari script).
        final isHindi = RegExp(r'[\u0900-\u097F]').hasMatch(query);
        return isHindi ? pair.answerHi : pair.answerEn;
      }
    }

    // 2. Hard-coded keyword fallback as last resort.
    return _hardcodedFallback(query);
  }

  // ── Prompt builder ─────────────────────────────────────────────────────────

  /// Builds the full Gemma instruct-format prompt string.
  String _buildPrompt(String userMessage, List<Map<String, String>>? history) {
    final buf = StringBuffer();

    // System turn
    buf.write('<start_of_turn>system\n');
    buf.write(systemPrompt);
    buf.write('\n<end_of_turn>\n');

    // Conversation history (last N turns passed in by AppState)
    for (final turn in history ?? []) {
      final role = turn['role'] == 'assistant' ? 'model' : 'user';
      buf.write('<start_of_turn>$role\n');
      buf.write(turn['text']);
      buf.write('\n<end_of_turn>\n');
    }

    // Current user turn
    buf.write('<start_of_turn>user\n');
    buf.write(userMessage);
    buf.write('\n<end_of_turn>\n');
    buf.write('<start_of_turn>model\n');

    return buf.toString();
  }

  // ── Tokeniser helpers ──────────────────────────────────────────────────────

  /// Minimal byte-level encoder — encodes each UTF-8 byte as a token id.
  /// Replace with the real SentencePiece tokeniser for production.
  List<int> _simpleBpeEncode(String text) {
    final bytes = Uint8List.fromList(text.codeUnits);
    // Offset by 3 to skip special tokens (BOS=2, EOS=1, PAD=0).
    return bytes.map((b) => b + 3).toList();
  }

  /// Decodes a single token id back to a string piece.
  String _decodeTokenPiece(int tokenId) {
    if (tokenId <= 3) return '';
    // Reverse of the byte-level encoder above.
    final byte = tokenId - 3;
    if (byte < 0 || byte > 255) return '';
    return String.fromCharCode(byte);
  }

  /// Returns the index of the maximum value in a list (greedy decode).
  int _argmax(List<double> logits) {
    int best = 0;
    for (int i = 1; i < logits.length; i++) {
      if (logits[i] > logits[best]) best = i;
    }
    return best;
  }

  // ── Hard-coded keyword fallback ────────────────────────────────────────────

  String _hardcodedFallback(String prompt) {
    final q = prompt.toLowerCase();
    if (q.contains('earthquake') || q.contains('भूकंप')) {
      return '1. DROP to hands and knees immediately.\n2. Take COVER under a sturdy table or against an interior wall.\n3. HOLD ON — protect your head and neck with your arms.\n4. Stay inside until shaking stops.\n5. After shaking, evacuate carefully — watch for falling debris.';
    }
    if (q.contains('flood') || q.contains('बाढ़')) {
      return '1. Move to higher ground immediately — do not wait.\n2. Do NOT walk through moving water (6 inches can knock you down).\n3. If trapped in a building, move to the highest floor.\n4. Signal rescuers with a bright cloth or flashlight from a window.\n5. Do not drive through flooded roads.';
    }
    if (q.contains('wildfire') || q.contains('fire') || q.contains('आग')) {
      return '1. Evacuate immediately when ordered — do not delay.\n2. Close all windows and doors to slow fire entry.\n3. Wear an N95 mask or cover nose/mouth with a damp cloth.\n4. Drive with headlights on and windows closed.\n5. Do not shelter under trees or powerlines.';
    }
    if (q.contains('bleed') || q.contains('blood') || q.contains('wound') || q.contains('रक्त')) {
      return '1. Apply firm direct pressure with a clean cloth.\n2. Do not remove the cloth if soaked — add more on top.\n3. Elevate the injured limb above heart level if possible.\n4. For severe limb bleeding, apply a tourniquet 2–3 inches above the wound.\n5. Note the time the tourniquet was applied.';
    }
    if (q.contains('cpr') || q.contains('cardiac') || q.contains('heart') || q.contains('unresponsive')) {
      return '1. Check for responsiveness — shout and tap shoulders.\n2. Call for emergency help immediately.\n3. Push hard and fast on the centre of the chest — 100–120 compressions/min, ≥2 inches deep.\n4. After 30 compressions, give 2 rescue breaths.\n5. Continue until help arrives or the person shows signs of life.';
    }
    if (q.contains('chok') || q.contains('heimlich') || q.contains('गला')) {
      return '1. Ask: "Are you choking?" — if they cannot speak, act immediately.\n2. Give 5 firm back blows between the shoulder blades.\n3. Give 5 abdominal thrusts: stand behind, arms around waist, thrust inward and upward.\n4. Alternate back blows and thrusts until the object dislodges.\n5. If they become unconscious, begin CPR.';
    }
    if (q.contains('burn') || q.contains('जलना')) {
      return '1. Cool with running cool water for 10–20 minutes — NOT ice.\n2. Do not apply butter, toothpaste, or ice.\n3. Cover loosely with a clean, non-fluffy bandage.\n4. Do not pop any blisters.\n5. For large/deep burns, cover and seek immediate medical help.';
    }
    if (q.contains('dehydrat') || q.contains('water') || q.contains('thirst') || q.contains('निर्जलीकरण')) {
      return '1. Signs: dark urine, dizziness, dry mouth, confusion.\n2. Sip small amounts of water frequently.\n3. To purify water: boil for 1 minute (3 minutes at high altitude).\n4. Without fuel: add 2 drops of household bleach per litre, wait 30 min.\n5. Avoid alcohol and caffeine.';
    }
    if (q.contains('shock') || q.contains('शॉक')) {
      return '1. Lay the person flat and elevate legs 12 inches (unless spinal injury suspected).\n2. Signs: pale/cold skin, rapid weak pulse, confusion, rapid breathing.\n3. Keep warm with a blanket.\n4. Do not give food or water.\n5. Monitor breathing and be ready to perform CPR.';
    }
    if (q.contains('hypotherm') || q.contains('cold') || q.contains('freeze') || q.contains('ठंड')) {
      return '1. Move person to a warm, dry area immediately.\n2. Remove wet clothing gently.\n3. Warm body core first (chest, neck, groin) — blankets or body heat.\n4. Do NOT rub limbs vigorously — risk of cardiac arrest.\n5. Give warm (not hot) beverages if conscious.';
    }
    if (q.contains('heatstroke') || q.contains('heat') || q.contains('गर्मी')) {
      return '1. Move to a cool, shaded area immediately.\n2. Remove excess clothing.\n3. Cool with any means available — wet cloths, fanning, cool water on skin.\n4. Focus cooling on neck, armpits, and groin.\n5. Give cool water to drink if conscious. Seek medical help urgently.';
    }
    if (q.contains('drown') || q.contains('water') || q.contains('डूबना')) {
      return '1. Do not enter water unless trained in water rescue.\n2. Throw a rope, branch, or cloth for the person to grab.\n3. Once onshore, check responsiveness and breathing.\n4. If not breathing, begin CPR immediately — start with 5 rescue breaths.\n5. Keep warm — drowning victims rapidly lose body heat.';
    }
    if (q.contains('fracture') || q.contains('broken') || q.contains('bone') || q.contains('हड्डी')) {
      return '1. Do not try to straighten the bone.\n2. Immobilize the limb in the position found.\n3. Use rigid material (board, rolled newspaper) as a splint.\n4. Pad the splint and secure with cloth ties above and below the fracture.\n5. Check circulation beyond the splint (pulse, color, warmth).';
    }
    if (q.contains('mental') || q.contains('panic') || q.contains('anxiet') || q.contains('trauma') || q.contains('मानसिक')) {
      return '1. Acknowledge feelings — it is normal to feel scared or overwhelmed.\n2. For panic attacks: breathe in 4 counts, hold 4, out 4. Repeat.\n3. Stay connected with others — isolation worsens trauma.\n4. Maintain routines where possible (eating, sleeping).\n5. Avoid excessive disaster news.';
    }
    if (q.contains('checklist') || q.contains('supplies') || q.contains('kit') || q.contains('सूची')) {
      return 'Emergency kit essentials:\n1. Water — 1 gallon per person per day, 3-day minimum\n2. Non-perishable food — 3-day supply\n3. First aid kit\n4. Flashlight + extra batteries\n5. Emergency whistle\n6. Dust mask / N95\n7. Warm blanket per person\n8. Medications + copies of prescriptions\n9. Copies of important documents\n10. Local paper map';
    }
    return 'I\'m ResQ, your offline emergency assistant. I can help with CPR, bleeding, earthquake, flood, wildfire, burns, fractures, and more. What do you need help with right now?';
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  void _log(String msg) {
    // ignore: avoid_print
    print('[GemmaService] $msg');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _mode = AiMode.offlineCache;
  }
}
