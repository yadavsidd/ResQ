// lib/widgets/ai_status_widget.dart
// ─────────────────────────────────────────────────────────────────────────────
// AiStatusWidget — compact chip that communicates the current AI runtime mode
// to the user at a glance.
//
// States:
//   AiMode.loading        → blue pulsing pill + linear progress bar
//   AiMode.gemmaOnDevice  → green pill "Gemma 4 AI Ready (On-Device)"
//   AiMode.offlineCache   → orange pill "AI Offline — Using Cached Responses"
//
// Usage:
//   AiStatusWidget()                   // compact chip (for AppBar.actions)
//   AiStatusWidget(showBar: true)      // compact chip + loading progress bar
//                                      // (shown in ChatScreen body header)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/gemma_service.dart';

class AiStatusWidget extends StatelessWidget {
  /// When true, adds a thin animated LinearProgressIndicator below the chip
  /// during the loading state.  Use this variant inside the screen body.
  final bool showBar;

  const AiStatusWidget({super.key, this.showBar = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final mode  = state.gemma.mode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Chip(mode: mode),
        if (showBar && mode == AiMode.loading) ...[
          const SizedBox(height: 4),
          const _LoadingBar(),
        ],
      ],
    );
  }
}

// ── Chip ──────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final AiMode mode;
  const _Chip({required this.mode});

  @override
  Widget build(BuildContext context) {
    final config = _chipConfig(mode);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: config.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon / spinner
          if (mode == AiMode.loading)
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(config.fg),
              ),
            )
          else
            Icon(config.icon, size: 11, color: config.fg),
          const SizedBox(width: 5),
          Text(
            config.label,
            style: TextStyle(
              color: config.fg,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  _ChipConfig _chipConfig(AiMode m) {
    switch (m) {
      case AiMode.loading:
        return _ChipConfig(
          bg:    const Color(0xFF1565C0).withOpacity(0.15),
          fg:    const Color(0xFF1565C0),
          icon:  Icons.sync_rounded,
          label: 'Initializing Gemma 4 AI…',
        );
      case AiMode.gemmaOnDevice:
        return _ChipConfig(
          bg:    const Color(0xFF2E7D32).withOpacity(0.15),
          fg:    const Color(0xFF2E7D32),
          icon:  Icons.smart_toy_rounded,
          label: 'Gemma 4 AI Ready (On-Device)',
        );
      case AiMode.offlineCache:
        return _ChipConfig(
          bg:    const Color(0xFFE65100).withOpacity(0.15),
          fg:    const Color(0xFFE65100),
          icon:  Icons.storage_rounded,
          label: 'AI Offline — Using Cached Responses',
        );
    }
  }
}

class _ChipConfig {
  final Color bg;
  final Color fg;
  final IconData icon;
  final String label;
  const _ChipConfig({required this.bg, required this.fg, required this.icon, required this.label});
}

// ── Loading bar ───────────────────────────────────────────────────────────────

class _LoadingBar extends StatefulWidget {
  const _LoadingBar();
  @override
  State<_LoadingBar> createState() => _LoadingBarState();
}

class _LoadingBarState extends State<_LoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 2,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => LinearProgressIndicator(
            value: null, // indeterminate
            backgroundColor:
                const Color(0xFF1565C0).withOpacity(0.12),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF1565C0)),
          ),
        ),
      );
}
