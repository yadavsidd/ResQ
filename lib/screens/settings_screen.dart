// lib/screens/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../services/app_state.dart';
import 'onboarding_screen.dart'; 

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearAllData(BuildContext context, AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text('This will delete your emergency checklist, chat history, saved locations, and require re-downloading the AI model and completing onboarding again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('CLEAR DATA')
          ),
        ],
      ),
    );
    if (confirmed == true) {
       final docs = await getApplicationDocumentsDirectory();
       final modelFile = File('${docs.path}/gemma-4-e2b.tflite');
       if (await modelFile.exists()) await modelFile.delete();
              // Note: Safely dropping SQFlite instances requires app restarts, but we reset flags
        await state.clearAllData();
       
       Navigator.of(context).pushAndRemoveUntil(
         MaterialPageRoute(builder: (_) => Scaffold(
           body: Center(
             child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 const Icon(Icons.check_circle_rounded, size: 60, color: Colors.green),
                 const SizedBox(height: 16),
                 const Text('Data Cleared', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 24),
                 FilledButton(onPressed: () => exit(0), child: const Text('Exit App')),
               ],
             )
           )
         )),
         (route) => false,
       );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── Language ──────────────────────────────────────
          Text('Accessibility', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colorScheme.primary)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Language'),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('EN')),
                      ButtonSegment(value: 'hi', label: Text('HI')),
                    ],
                    selected: {state.language},
                    onSelectionChanged: (set) => state.switchLanguage(set.first),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.format_size_rounded),
                  title: const Text('Text Size'),
                  trailing: SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 1.0, label: Text('A')),
                      ButtonSegment(value: 1.2, label: Text('A', style: TextStyle(fontSize: 14))),
                      ButtonSegment(value: 1.4, label: Text('A', style: TextStyle(fontSize: 16))),
                    ],
                    selected: {state.textScale},
                    onSelectionChanged: (set) => state.setTextScale(set.first),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Hackathon Judge Tools ──────────────────────────
          Text('Hackathon Judge Tools', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colorScheme.primary)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.speed_rounded),
                  title: const Text('Performance Telemetry'),
                  subtitle: Text('TTFT: ${state.gemma.timeToFirstTokenMs.toStringAsFixed(0)}ms | TPS: ${state.gemma.tokensPerSecond.toStringAsFixed(1)} | RAM: ${state.gemma.ramAllocationMB.toStringAsFixed(1)} MB'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.rocket_launch_rounded),
                  title: const Text('Load Demo Scenario'),
                  subtitle: const Text('Injects a dramatic trapped/bleeding prompt.'),
                  trailing: const Icon(Icons.chat_bubble_outline_rounded),
                  onTap: () {
                    state.triggerDemoScenario();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Data & Storage ────────────────────────────────
          Text('Data & Offline Assets', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colorScheme.primary)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.smart_toy_rounded, color: state.gemma.isReady ? Colors.green : Colors.orange),
                  title: Text(state.gemma.isReady ? 'Gemma 4 Loaded ✓' : 'Gemma 4 Missing'),
                  subtitle: const Text('1.3 GB On-Device Model'),
                  trailing: OutlinedButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
                    },
                    child: const Text('Download'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.map_rounded),
                  title: const Text('City Map Data'),
                  subtitle: const Text('Jaipur, IN (Cached)'),
                  trailing: OutlinedButton(
                    onPressed: () {
                      state.switchTab(1); // Jump to map tab
                      Navigator.pop(context); // Close settings
                    },
                    child: const Text('Manage'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Colors.red.withOpacity(0.1),
            iconColor: Colors.red,
            textColor: Colors.red,
            leading: const Icon(Icons.delete_forever_rounded),
            title: const Text('Clear All Data', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => _clearAllData(context, state),
          ),

          const SizedBox(height: 48),
          // ── About ──────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.health_and_safety_rounded, color: colorScheme.primary, size: 36),
                ),
                const SizedBox(height: 12),
                const Text('ResQ — Offline Emergency AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Version 1.0.0 (Kaggle Hackathon)', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
