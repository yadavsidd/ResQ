// lib/screens/chat_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// ChatScreen — the primary AI interface where users converse with the on-device
// Gemma 4 E2B model.  Features:
//   • Text input and voice input (speech_to_text)
//   • TTS read-out of AI replies (via ChatBubble widget)
//   • Multi-turn conversation history persisted in SQLite
//   • Works fully offline — all inference happens on-device via LiteRT

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/app_state.dart';
import '../widgets/ai_status_widget.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize();
    setState(() {});
  }

  int _lastLength = 0;

  void _scrollToBottom({bool force = false}) {
    if (!mounted) return;
    final state = context.read<AppState>();
    final currentLength = state.chatHistory.length;
    if (!force && currentLength == _lastLength) return;
    _lastLength = currentLength;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await context.read<AppState>().sendMessageStreaming(text);
    _scrollToBottom(force: true);
  }

  Future<void> _toggleListening(AppState state) async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      final lang = state.language == 'hi' ? 'hi-IN' : 'en-US';
      await _speech.listen(
        onResult: (result) {
          _controller.text = result.recognizedWords;
          _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length));
        },
        localeId: lang,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    // Auto-scroll when new messages arrive
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.smart_toy_rounded, color: colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(state.t('nav_chat'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          const Center(child: AiStatusWidget()),
          const SizedBox(width: 6),
          // Language toggle (EN / HI)
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Text(
              state.language.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            tooltip: 'Toggle Language',
            onPressed: () {
              state.switchLanguage(state.language == 'en' ? 'hi' : 'en');
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: state.t('clear'),
            onPressed: () async {
              final confirm = await _showClearDialog(context, state);
              if (confirm == true) await state.clearChat();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Model status / loading bar
          if (state.gemma.isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: AiStatusWidget(showBar: true),
            ),

          // Chat history
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: state.chatHistory.length,
              itemBuilder: (ctx, i) {
                return ChatBubble(
                  message: state.chatHistory[i],
                  tts: state.tts,
                );
              },
            ),
          ),

          // Quick actions row
          _buildQuickActions(state, colorScheme),

          // Input area
          _buildInputBar(state, colorScheme),
        ],
      ),
    );
  }

  Widget _buildQuickActions(AppState state, ColorScheme cs) {
    final actions = [
      'CPR Help',
      "I'm Trapped",
      'Find Water',
      'Nearest Shelter'
    ];
    
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerLowest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: actions.map((text) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.tertiaryContainer,
                foregroundColor: cs.onTertiaryContainer,
                minimumSize: const Size(80, 48), // Ensure >= 48 target
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: () {
                if (!state.isGenerating) {
                  context.read<AppState>().sendMessageStreaming(text);
                  _scrollToBottom(force: true);
                }
              },
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildInputBar(AppState state, ColorScheme cs) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
        ),
        child: Row(
          children: [
            // Mic button (static, no animation)
            if (_speechAvailable)
              Container(
                decoration: BoxDecoration(
                  color: _isListening
                      ? cs.errorContainer
                      : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(
                      _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      size: 24),
                  color: _isListening ? cs.error : cs.onSurface,
                  onPressed: () => _toggleListening(state),
                ),
              ),
            if (_speechAvailable) const SizedBox(width: 8),
            
            // Text field
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: 4,
                minLines: 1,
                style: const TextStyle(fontSize: 16), // Accessible font target
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: state.t('chat_hint'),
                  hintStyle: const TextStyle(fontSize: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            
            // Send button (static, no animation)
            Container(
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: state.isGenerating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                onPressed: state.isGenerating ? null : _send,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showClearDialog(BuildContext ctx, AppState state) =>
      showDialog<bool>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          title: const Text('Clear chat?', style: TextStyle(fontSize: 20)),
          content: const Text('All conversation history will be deleted.', style: TextStyle(fontSize: 16)),
          actions: [
            TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.pop(dctx, false),
                child: Text(state.t('back'), style: const TextStyle(fontSize: 16))),
            TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.pop(dctx, true),
                child: Text(state.t('clear'),
                    style: TextStyle(
                        fontSize: 16, color: Theme.of(ctx).colorScheme.error))),
          ],
        ),
      );
}
