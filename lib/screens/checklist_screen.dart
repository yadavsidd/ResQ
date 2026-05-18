// lib/screens/checklist_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// ChecklistScreen — lets users describe their disaster situation and generates
// a personalised emergency action checklist using on-device Gemma 4.
//
// Features:
//   • Text prompt describing the situation → AI generates numbered checklist
//   • Each item can be checked off; state persists in SQLite
//   • TTS reads unchecked items aloud for hands-free use
//   • Progress bar shows completion percentage
//   • Works fully offline — Gemma runs on-device via LiteRT

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../widgets/offline_badge.dart';

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  // Form State
  String _disasterType = 'Earthquake';
  int _peopleNum = 1;
  final Set<String> _specialNeeds = {};

  final List<String> _disasters = ['Earthquake', 'Flood', 'Wildfire', 'Cyclone', 'General Emergency'];
  final List<String> _availableNeeds = ['Elderly', 'Infant', 'Disabled', 'Pets', 'Medical'];

  Future<void> _generate(AppState state) async {
    FocusScope.of(context).unfocus();
    await state.generateChecklist(_disasterType, _peopleNum, _specialNeeds.toList());
  }

  void _readAllAloud(AppState state) {
    final unchecked = state.checklistItems
        .where((i) => !i.isChecked)
        .map((i) => i.text)
        .toList();
    if (unchecked.isEmpty) {
      state.tts.speak('All items are checked. Great work!');
    } else {
      state.tts.speak(unchecked.join('. Next: '));
    }
  }

  void _copyToClipboard(AppState state) {
    final text = state.checklistItems.map((i) => '${i.isChecked ? "[x]" : "[ ]"} ${i.text}').join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checklist copied to clipboard')));
  }

  void _shareViaSms(AppState state) {
    final text = state.checklistItems.map((i) => '${i.isChecked ? "[x]" : "[ ]"} ${i.text}').join('\n');
    final uri = Uri(scheme: 'sms', queryParameters: {'body': 'ResQ Emergency Checklist:\n\n$text'});
    launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    final total = state.checklistItems.length;
    final checked = state.checklistItems.where((i) => i.isChecked).length;
    final progress = total == 0 ? 0.0 : checked / total;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.checklist_rounded, color: colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(state.t('checklist_title'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          const OfflineBadge(),
          const SizedBox(width: 4),
          if (state.checklistItems.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Reset Checklist',
              onPressed: () => state.clearChecklist(),
            ),
            IconButton(
              icon: const Icon(Icons.volume_up_rounded),
              tooltip: state.t('speak'),
              onPressed: () => _readAllAloud(state),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Generate Form Area ──────────────────────────────────────────────
          if (total == 0) // Only show form entirely if checklist is empty, or show a compact version? The user wants "re-runs Gemma 4 inference with same inputs", so I should keep the form visible but maybe compact, or just keep it there. It's actually better to keep it there so they can change values and hit regenerate.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: _disasterType,
                  decoration: InputDecoration(
                     labelText: 'What disaster are you facing?',
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                     filled: true,
                     fillColor: colorScheme.surface,
                     contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: _disasters.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setState(() => _disasterType = v!),
                ),
                const SizedBox(height: 12),
                
                Row(
                  children: [
                    const Text('Group size:', style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _peopleNum > 1 ? () => setState(() => _peopleNum--) : null,
                    ),
                    Text('$_peopleNum', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _peopleNum < 20 ? () => setState(() => _peopleNum++) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                const Text('Special needs:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 0,
                  children: _availableNeeds.map((need) {
                    final isSelected = _specialNeeds.contains(need);
                    return FilterChip(
                      label: Text(need),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) _specialNeeds.add(need);
                          else _specialNeeds.remove(need);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                FilledButton.icon(
                  icon: state.isGeneratingChecklist
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(state.isGeneratingChecklist ? 'Generating...' : 'Generate Checklist'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: state.isGeneratingChecklist ? null : () => _generate(state),
                ),
              ],
            ),
          ),

          // ── Progress bar (shown when items exist) ──────────────────────────
          if (total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$checked / $total completed',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withOpacity(0.65))),
                      Text('${(progress * 100).toInt()}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),

          // ── Checklist items ────────────────────────────────────────────────
          Expanded(
            child: state.checklistItems.isEmpty
                ? _EmptyChecklist(message: state.t('checklist_empty'))
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: state.checklistItems.length,
                    itemBuilder: (ctx, i) {
                      final item = state.checklistItems[i];
                      return CheckboxListTile(
                        value: item.isChecked,
                        onChanged: (_) => state.toggleChecklistItem(i),
                        title: Text(
                          item.text,
                          style: TextStyle(
                            fontSize: 14,
                            decoration: item.isChecked
                                ? TextDecoration.lineThrough
                                : null,
                            color: item.isChecked
                                ? colorScheme.onSurface.withOpacity(0.45)
                                : colorScheme.onSurface,
                          ),
                        ),
                        secondary: Text(
                          '${i + 1}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary),
                        ),
                        controlAffinity: ListTileControlAffinity.trailing,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      );
                    },
                  ),
          ),

          // ── Bottom Action row ────────────────────────────────────────────
          if (total > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(state),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy List'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _shareViaSms(state),
                      icon: const Icon(Icons.sms_rounded, size: 16),
                      label: const Text('SMS Action'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.isGeneratingChecklist ? null : () => _generate(state),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Regenerate'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyChecklist extends StatelessWidget {
  final String message;
  const _EmptyChecklist({required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.playlist_add_rounded,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.25)),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5))),
            ],
          ),
        ),
      );
}
