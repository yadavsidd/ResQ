// lib/screens/guide_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// GuideScreen — a searchable library of 15 first-aid topics loaded from the
// bundled assets/first_aid/topics.json.  Tapping a topic opens a detail view
// where the user can read step-by-step instructions, hear them via TTS, or
// ask the on-device Gemma AI follow-up questions — all offline.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/first_aid_topic.dart';
import '../services/app_state.dart';
import '../widgets/emergency_card.dart';
import '../widgets/offline_badge.dart';

// ── Icon mapping ────────────────────────────────────────────────────────────
final _iconMap = <String, IconData>{
  'favorite': Icons.favorite_rounded,
  'water_drop': Icons.water_drop_rounded,
  'landscape': Icons.landscape_rounded,
  'waves': Icons.waves_rounded,
  'local_fire_department': Icons.local_fire_department_rounded,
  'sick': Icons.sick_rounded,
  'thermostat': Icons.thermostat_rounded,
  'accessibility': Icons.accessibility_new_rounded,
  'ac_unit': Icons.ac_unit_rounded,
  'water': Icons.water_rounded,
  'healing': Icons.healing_rounded,
  'bolt': Icons.bolt_rounded,
  'psychology': Icons.psychology_rounded,
  'child_care': Icons.child_care_rounded,
  'sos': Icons.sos_rounded,
};

// ── Accent colours cycling across cards ──────────────────────────────────────
const _accentColors = [
  Colors.red,
  Colors.deepOrange,
  Colors.orange,
  Colors.blue,
  Colors.teal,
  Colors.purple,
  Colors.indigo,
  Colors.pink,
  Colors.cyan,
  Colors.green,
  Colors.amber,
  Colors.lightBlue,
  Colors.deepPurple,
  Colors.lime,
  Colors.redAccent,
];

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String _search = '';

  List<FirstAidTopic> _filtered(AppState state) {
    List<FirstAidTopic> filtered;
    if (_search.isEmpty) {
      filtered = List.from(state.topics);
    } else {
      final q = _search.toLowerCase();
      filtered = state.topics.where((t) {
        return t.title.toLowerCase().contains(q) ||
            t.titleHi.contains(q) ||
            t.summary.toLowerCase().contains(q);
      }).toList();
    }
    
    // Sort logic to pin High Priority topics (CPR & Bleeding)
    filtered.sort((a, b) {
       final aPriority = (a.id == 1 || a.id == 2) ? 1 : 0;
       final bPriority = (b.id == 1 || b.id == 2) ? 1 : 0;
       if (aPriority != bPriority) return bPriority.compareTo(aPriority);
       return a.id.compareTo(b.id);
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final filtered = _filtered(state);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.medical_services_rounded,
                color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(state.t('guide_title'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final newLang = state.language == 'en' ? 'hi' : 'en';
              state.switchLanguage(newLang);
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
            child: Text(
              state.language == 'en' ? 'HI' : 'EN',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const OfflineBadge(), 
          const SizedBox(width: 8)
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: state.t('guide_search_hint'),
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: filtered.length,
        itemBuilder: (ctx, i) {
          final topic = filtered[i];
          final accent = _accentColors[topic.id % _accentColors.length];
          final isPriority = topic.id == 1 || topic.id == 2;
          
          return EmergencyCard(
            title: topic.localTitle(state.language),
            summary: topic.localSummary(state.language),
            icon: _iconMap[topic.icon] ?? Icons.help_outline_rounded,
            accentColor: accent,
            isPriority: isPriority,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => _TopicDetailScreen(
                  topic: topic,
                  accentColor: accent,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Topic detail screen ───────────────────────────────────────────────────────

class _TopicDetailScreen extends StatefulWidget {
  final FirstAidTopic topic;
  final Color accentColor;

  const _TopicDetailScreen(
      {required this.topic, required this.accentColor});

  @override
  State<_TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<_TopicDetailScreen> {
  final TextEditingController _aiCtrl = TextEditingController();
  String? _aiAnswer;
  bool _loading = false;

  Future<void> _askAI(AppState state) async {
    final q = _aiCtrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _aiAnswer = null;
    });
    final prompt =
        'Regarding the topic "${widget.topic.title}": $q. Provide a concise, accurate answer.';
    final answer = await state.gemma.generateText(prompt: prompt);
    if (mounted) {
      setState(() {
        _aiAnswer = answer;
        _loading = false;
      });
    }
  }

  String _mapEmoji(String stepStr) {
    final lower = stepStr.toLowerCase();
    if (lower.contains('call ') || lower.contains('help') || lower.contains('emergency') || lower.contains('पुकारें')) return '📞 ';
    if (lower.contains('cpr') || lower.contains('chest') || lower.contains('heart') || lower.contains('छाती')) return '🫀 ';
    if (lower.contains('pressure') || lower.contains('cloth') || lower.contains('tourniquet') || lower.contains('रक्तस्राव')) return '🩸 ';
    if (lower.contains('evacuate') || lower.contains('move ') || lower.contains('leave') || lower.contains('निकलें')) return '🚶 ';
    if (lower.contains('drop') || lower.contains('cover') || lower.contains('table') || lower.contains('घुटनों')) return '🛡️ ';
    if (lower.contains('water') || lower.contains('flood') || lower.contains('wash') || lower.contains('पानी')) return '🌊 ';
    if (lower.contains('fire') || lower.contains('smoke') || lower.contains('mask') || lower.contains('आग')) return '🔥 ';
    if (lower.contains('back blows') || lower.contains('choking') || lower.contains('heimlich') || lower.contains('पीठ')) return '🫁 ';
    if (lower.contains('burn') || lower.contains('cool') || lower.contains('ठंडे')) return '🧊 ';
    if (lower.contains('bone') || lower.contains('splint') || lower.contains('immobilize') || lower.contains('हड्डी')) return '🦴 ';
    if (lower.contains('warm') || lower.contains('cold') || lower.contains('blanket') || lower.contains('कंबल')) return '🧣 ';
    if (lower.contains('drink') || lower.contains('purify') || lower.contains('bleach') || lower.contains('पिएं')) return '💧 ';
    if (lower.contains('wound') || lower.contains('infection') || lower.contains('bandage') || lower.contains('घाव') || lower.contains('पट्टी')) return '🩹 ';
    if (lower.contains('shock') || lower.contains('legs') || lower.contains('पैर')) return '⚡ ';
    if (lower.contains('panic') || lower.contains('feelings') || lower.contains('breathe') || lower.contains('सांस')) return '🧠 ';
    if (lower.contains('infant') || lower.contains('child') || lower.contains('baby') || lower.contains('शिशु')) return '👶 ';
    if (lower.contains('signal') || lower.contains('whistle') || lower.contains('sos') || lower.contains('संकेत')) return '🆘 ';
    return '🔸 '; // Default
  }

  @override
  void dispose() {
    _aiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final lang = state.language;
    final colorScheme = Theme.of(context).colorScheme;
    final steps = widget.topic.localSteps(lang);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic.localTitle(lang),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          // TTS: read all steps aloud
          IconButton(
            icon: const Icon(Icons.volume_up_rounded),
            tooltip: state.t('speak'),
            onPressed: () {
              final text = steps.asMap().entries
                  .map((e) => '${e.key + 1}. ${e.value}')
                  .join('. ');
              state.tts.speak(text);
            },
          ),
          const OfflineBadge(),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Summary banner ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: widget.accentColor.withOpacity(0.3), width: 1),
            ),
            child: Text(
              widget.topic.localSummary(lang),
              style: TextStyle(
                  fontSize: 14, color: colorScheme.onSurface, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),

          // ── Step-by-step instructions ──────────────────────────────────────
          Text('Steps',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: widget.accentColor)),
          const SizedBox(height: 10),
          ...steps.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: widget.accentColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${e.key + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_mapEmoji(e.value) + e.value,
                          style: const TextStyle(fontSize: 14, height: 1.45)),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 24),

          // ── AI Q&A section ────────────────────────────────────────────────
          Text(state.t('guide_ask_ai'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary)),
          const SizedBox(height: 10),
          TextField(
            controller: _aiCtrl,
            decoration: InputDecoration(
              hintText: 'Ask a follow-up question…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.smart_toy_rounded, size: 18),
            label: Text(state.t('guide_ask_ai')),
            onPressed: _loading ? null : () => _askAI(state),
          ),
          if (_aiAnswer != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.smart_toy_rounded,
                          size: 14, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(state.t('guide_ai_answer'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => state.tts.speak(_aiAnswer!),
                        child: Icon(Icons.volume_up_rounded,
                            size: 16, color: colorScheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_aiAnswer!,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: colorScheme.onPrimaryContainer)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
