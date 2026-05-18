// lib/services/app_state.dart
// ─────────────────────────────────────────────────────────────────────────────
// AppState — the central ChangeNotifier that wires all services together and
// is injected at the root of the widget tree via Provider.
//
// Responsibilities:
//   • Initialises GemmaService, DatabaseService, TtsService, and LocationService
//   • Holds the active language ('en' | 'hi') and localised strings map
//   • Loads first-aid topics from the bundled JSON asset
//   • Manages the chat history list for the ChatScreen
//   • Exposes the checklist session state for ChecklistScreen
//
// Every widget that needs a piece of global state reads it from here via
// context.watch<AppState>() or context.read<AppState>().

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/checklist_item.dart';
import '../models/first_aid_topic.dart';
import '../models/saved_location.dart';
import 'gemma_service.dart';
import 'database_service.dart';
import 'offline_db_service.dart';
import 'tts_service.dart';
import 'location_service.dart';

class AppState extends ChangeNotifier {
  // ── Services ───────────────────────────────────────────────────────────────
  final GemmaService     gemma     = GemmaService();
  final DatabaseService  db        = DatabaseService();
  final OfflineDbService offlineDb = OfflineDbService();
  final TtsService       tts       = TtsService();
  final LocationService  location  = LocationService();

  /// Current AI runtime mode — read by AiStatusWidget.
  AiMode get aiMode => gemma.mode;

  // ── Language & Localisation ────────────────────────────────────────────────
  String _language = 'en';              // 'en' or 'hi'
  Map<String, dynamic> _strings = {};   // loaded from assets/i18n/<lang>.json
  double _textScale = 1.0;
  
  SharedPreferences? _prefs;

  String get language => _language;
  double get textScale => _textScale;
  String t(String key) => _strings[key] as String? ?? key;

  // ── App Lifecycle & Nav ───────────────────────────────────────────────────
  bool _isInitialised = false;
  bool get isInitialised => _isInitialised;

  bool _hasCompletedOnboarding = false;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;

  String _initStatus = 'Starting…';
  String get initStatus => _initStatus;

  int _activeTab = 0;
  int get activeTab => _activeTab;

  void switchTab(int index) {
    if (_activeTab != index) {
      _activeTab = index;
      notifyListeners();
    }
  }

  // ── First Aid Topics ───────────────────────────────────────────────────────
  List<FirstAidTopic> topics = [];

  // ── Chat ───────────────────────────────────────────────────────────────────
  List<ChatMessage> chatHistory = [];
  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  // ── Checklist ──────────────────────────────────────────────────────────────
  List<ChecklistItem> checklistItems = [];
  int _currentChecklistSession = 0;
  bool _isGeneratingChecklist = false;
  bool get isGeneratingChecklist => _isGeneratingChecklist;

  // ── Saved Locations ────────────────────────────────────────────────────────
  List<SavedLocation> savedLocations = [];

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> init() async {
    _updateStatus('Loading preferences…');
    _prefs = await SharedPreferences.getInstance();
    _hasCompletedOnboarding = _prefs?.getBool('hasCompletedOnboarding') ?? false;
    _language = _prefs?.getString('language') ?? 'en';
    _textScale = _prefs?.getDouble('textScale') ?? 1.0;

    _updateStatus('Loading database…');
    await db.init();

    _updateStatus('Loading translations…');
    await _loadLanguage(_language);

    _updateStatus('Loading first-aid guide…');
    await _loadTopics();

    _updateStatus('Loading AI model…');
    // Pass OfflineDbService so GemmaService can delegate to it on fallback.
    await gemma.init(offlineDb);

    _updateStatus('Seeding offline knowledge base…');
    await offlineDb.init(db.rawDb);

    _updateStatus('Setting up accessibility…');
    await tts.init();

    _updateStatus('Restoring data…');
    await db.seedInitialLocations();
    chatHistory = await db.loadChatHistory();
    checklistItems = await db.loadChecklistItems();
    savedLocations = await db.loadLocations();

    // Inject a welcome message if there is no history yet.
    if (chatHistory.isEmpty) {
      final welcome = ChatMessage(
        text: t('chat_welcome'),
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );
      final id = await db.insertChatMessage(welcome);
      chatHistory.add(welcome.copyWith(id: id));
    }

    _isInitialised = true;
    notifyListeners();
  }

  void _updateStatus(String status) {
    _initStatus = status;
    notifyListeners();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> completeOnboarding() async {
    _hasCompletedOnboarding = true;
    await _prefs?.setBool('hasCompletedOnboarding', true);
    notifyListeners();
  }

  Future<void> setTextScale(double scale) async {
    if (_textScale == scale) return;
    _textScale = scale;
    await _prefs?.setDouble('textScale', scale);
    notifyListeners();
  }

  Future<void> clearAllData() async {
    await db.clearChatHistory();
    await db.clearChecklist();
    await _prefs?.clear();
  }

  // ── Language ───────────────────────────────────────────────────────────────

  Future<void> switchLanguage(String lang) async {
    if (_language == lang) return;
    _language = lang;
    await _prefs?.setString('language', lang);
    await _loadLanguage(lang);
    await tts.setLanguage(lang);
    notifyListeners();
  }

  void toggleGemma(bool val) {
    gemma.isEnabled = val;
    notifyListeners();
  }

  // ── Demo / Judge Mode ──────────────────────────────────────────────────────

  void triggerDemoScenario() {
    switchTab(0); // Switch to Chat tab
    sendMessageStreaming("I am trapped under debris after an earthquake. My leg is bleeding heavily and I cannot move.");
  }

  Future<void> _loadLanguage(String lang) async {
    final raw = await rootBundle.loadString('assets/i18n/$lang.json');
    _strings = json.decode(raw) as Map<String, dynamic>;
  }

  // ── First Aid Topics ───────────────────────────────────────────────────────

  Future<void> _loadTopics() async {
    final raw = await rootBundle.loadString('assets/first_aid/topics.json');
    final list = json.decode(raw) as List;
    topics = list.map((e) => FirstAidTopic.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ── Chat (streaming) ──────────────────────────────────────────────────────

  /// Sends [text] and streams the AI reply token-by-token into chatHistory.
  /// The placeholder bubble grows in real-time as tokens arrive.
  Future<void> sendMessageStreaming(String text) async {
    if (text.trim().isEmpty || _isGenerating) return;
    _isGenerating = true;

    // 1. Persist + show user message.
    final userMsg = ChatMessage(
      text: text.trim(),
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );
    final userId = await db.insertChatMessage(userMsg);
    chatHistory.add(userMsg.copyWith(id: userId));
    notifyListeners();

    // 2. Build multi-turn context (last 10 turns).
    final history = chatHistory
        .where((m) => m.id != userId)
        .takeLast(10)
        .map((m) => {'role': m.role.name, 'text': m.text})
        .toList();

    // 3. Add empty AI placeholder bubble.
    final placeholderTs = DateTime.now();
    chatHistory.add(ChatMessage(
      text: '',
      role: MessageRole.assistant,
      timestamp: placeholderTs,
    ));
    notifyListeners();

    // 4. Accumulate tokens — update placeholder in-place on each chunk.
    final buf = StringBuffer();
    await for (final chunk
        in gemma.streamResponse(text.trim(), history: history)) {
      buf.write(chunk);
      chatHistory[chatHistory.length - 1] = ChatMessage(
        text: buf.toString(),
        role: MessageRole.assistant,
        timestamp: placeholderTs,
      );
      notifyListeners();
    }

    // 5. Persist the completed message.
    final completed = chatHistory.last;
    final aiId = await db.insertChatMessage(completed);
    chatHistory[chatHistory.length - 1] = completed.copyWith(id: aiId);
    _isGenerating = false;
    notifyListeners();
  }

  // ── Chat (non-streaming — kept for ChecklistScreen / GuideScreen) ──────────

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isGenerating) return;
    _isGenerating = true;

    // Add user message
    final userMsg = ChatMessage(
      text: text.trim(),
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );
    final userId = await db.insertChatMessage(userMsg);
    chatHistory.add(userMsg.copyWith(id: userId));
    notifyListeners();

    // Build history for multi-turn context (last 10 turns)
    final history = chatHistory
        .where((m) => m.id != userId)
        .takeLast(10)
        .map((m) => {'role': m.role.name, 'text': m.text})
        .toList();

    // Generate AI response
    final responseText = await gemma.generateText(
      prompt: text.trim(),
      history: history,
    );

    final aiMsg = ChatMessage(
      text: responseText,
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    );
    final aiId = await db.insertChatMessage(aiMsg);
    chatHistory.add(aiMsg.copyWith(id: aiId));
    _isGenerating = false;
    notifyListeners();
  }

  Future<void> clearChat() async {
    await db.clearChatHistory();
    chatHistory.clear();
    // Re-add welcome message
    final welcome = ChatMessage(
      text: t('chat_welcome'),
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    );
    final id = await db.insertChatMessage(welcome);
    chatHistory.add(welcome.copyWith(id: id));
    notifyListeners();
  }

  // ── Checklist ──────────────────────────────────────────────────────────────

  Future<void> generateChecklist(String disaster, int groupSize, List<String> specialNeeds) async {
    if (_isGeneratingChecklist) return;
    _isGeneratingChecklist = true;
    notifyListeners();

    String responseText;

    if (gemma.isInterpreterRunning) {
      final needs = specialNeeds.isEmpty ? 'none' : specialNeeds.join(', ');
      final prompt = 'Generate a prioritized survival checklist for $groupSize people facing a $disaster. Special needs: $needs. Format as numbered list. Include: immediate safety actions, items to grab, medical priorities, communication steps. Max 20 items. Be specific.';
      responseText = await gemma.generateText(prompt: prompt);
    } else {
      // ── Hardcoded Fallback Template Engine ────────────────────────────────
      final buf = StringBuffer();
      buf.writeln('1. Stay calm and assess your immediate surroundings.');
      buf.writeln('2. Ensure all $groupSize members of your group are accounted for.');
      
      if (disaster == 'Earthquake') {
        buf.writeln('3. Drop, Cover, and Hold On! Move away from windows.');
        buf.writeln('4. Prepare for aftershocks by moving to a structurally secure location.');
      } else if (disaster == 'Flood') {
        buf.writeln('3. Move to higher ground immediately.');
        buf.writeln('4. Do NOT attempt to walk or drive through moving water.');
      } else if (disaster == 'Wildfire') {
        buf.writeln('3. Evacuate immediately if ordered; keep windows closed to slow smoke.');
        buf.writeln('4. Wear N95 masks or damp cloths over your mouth to filter ash.');
      } else if (disaster == 'Cyclone') {
        buf.writeln('3. Stay indoors and away from all glass and exterior doors.');
        buf.writeln('4. Relocate to a small, windowless interior room on the lowest level.');
      } else {
        buf.writeln('3. Listen to local authorities for immediate evacuation orders.');
        buf.writeln('4. Grab your pre-packed emergency "go-bag" and keep it accessible.');
      }

      int step = 5;
      if (specialNeeds.contains('Elderly')) {
        buf.writeln('${step++}. Secure mobility aids (canes/walkers) and secure a supply of critical prescriptions.');
      }
      if (specialNeeds.contains('Infant')) {
        buf.writeln('${step++}. Pack ample baby formula, clean water, diapers, and warm blankets for the infant.');
      }
      if (specialNeeds.contains('Disabled')) {
        buf.writeln('${step++}. Map out accessible evacuation routes and ready specialized medical support equipment.');
      }
      if (specialNeeds.contains('Pets')) {
        buf.writeln('${step++}. Secure pets on strong leashes or inside hard carriers with their food and documentation.');
      }
      if (specialNeeds.contains('Medical')) {
        buf.writeln('${step++}. Keep all vital medications, a complete first-aid kit, and medical records readily at hand.');
      }
      
      buf.writeln('${step++}. Attempt to notify your emergency contacts via SMS if networks allow.');
      responseText = buf.toString();
    }

    // Parse numbered lines from the AI response
    final lines = responseText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => RegExp(r'^\d+[\.\)]').hasMatch(l))
        .map((l) => l.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), ''))
        .where((l) => l.isNotEmpty)
        .toList();

    // Clear previous checklist and start a new session
    _currentChecklistSession = await db.nextChecklistSessionId();
    await db.clearChecklist();
    checklistItems.clear();

    final now = DateTime.now();
    final newItems = lines.asMap().entries.map((e) => ChecklistItem(
          text: e.value,
          sessionId: _currentChecklistSession,
          createdAt: now.add(Duration(milliseconds: e.key)),
        )).toList();

    await db.insertChecklistItems(newItems);
    checklistItems = await db.loadChecklistItems(sessionId: _currentChecklistSession);

    _isGeneratingChecklist = false;
    notifyListeners();
  }

  Future<void> toggleChecklistItem(int index) async {
    final item = checklistItems[index];
    final updated = item.copyWith(isChecked: !item.isChecked);
    checklistItems[index] = updated;
    await db.updateChecklistItem(updated);
    notifyListeners();
  }

  Future<void> clearChecklist() async {
    await db.clearChecklist();
    checklistItems.clear();
    notifyListeners();
  }

  // ── Saved Locations ────────────────────────────────────────────────────────

  Future<void> saveLocation(SavedLocation loc) async {
    final id = await db.insertLocation(loc);
    savedLocations.insert(0, loc.copyWith(id: id));
    notifyListeners();
  }

  Future<void> deleteLocation(int id) async {
    await db.deleteLocation(id);
    savedLocations.removeWhere((l) => l.id == id);
    notifyListeners();
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    tts.dispose();
    gemma.dispose();
    db.close();
    super.dispose();
  }
}

// Extension to safely take-last N items from a list.
// Extension to safely take-last N items from an iterable.
extension _IterableX<T> on Iterable<T> {
  Iterable<T> takeLast(int n) => skip(length > n ? length - n : 0);
}
