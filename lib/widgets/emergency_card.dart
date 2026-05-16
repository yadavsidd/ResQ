// lib/widgets/emergency_card.dart
// ─────────────────────────────────────────────────────────────────────────────
// EmergencyCard — a reusable card widget used on the Guide screen to display
// a first-aid topic summary.  Tapping it navigates to the detail view.

import 'package:flutter/material.dart';

class EmergencyCard extends StatelessWidget {
  final String title;
  final String summary;
  final IconData icon;
  final Color accentColor;
  final bool isPriority; // Priority flag for emergency highlights
  final VoidCallback onTap;

  const EmergencyCard({
    super.key,
    required this.title,
    required this.summary,
    required this.icon,
    required this.accentColor,
    this.isPriority = false, // Default off
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: isPriority ? 4 : 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isPriority
            ? const BorderSide(color: Colors.redAccent, width: 2.5) // Urgent thick border
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, // Fits grid bounds
            children: [
              // Icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isPriority ? Colors.red.withOpacity(0.15) : accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: isPriority ? Colors.red : accentColor, size: 26),
              ),
              const SizedBox(height: 10),
              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Summary
              Expanded(
                child: Text(
                  summary,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurface.withOpacity(0.65)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
