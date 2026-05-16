// lib/models/first_aid_topic.dart
// ─────────────────────────────────────────────────────────────────────────────
// Data model for one of the 15 pre-stored first-aid topics.
// Topics are loaded from assets/first_aid/topics.json at startup — no network
// call required.  Both English and Hindi content are embedded in every topic
// so the full guide is accessible offline in either language.

class FirstAidTopic {
  final int id;
  final String title;          // English title
  final String titleHi;        // Hindi title
  final String icon;           // Material icon name (mapped in UI)
  final String summary;        // English one-sentence summary
  final String summaryHi;      // Hindi summary
  final List<String> steps;    // English numbered steps
  final List<String> stepsHi;  // Hindi numbered steps

  const FirstAidTopic({
    required this.id,
    required this.title,
    required this.titleHi,
    required this.icon,
    required this.summary,
    required this.summaryHi,
    required this.steps,
    required this.stepsHi,
  });

  factory FirstAidTopic.fromJson(Map<String, dynamic> json) => FirstAidTopic(
        id: json['id'] as int,
        title: json['title'] as String,
        titleHi: json['title_hi'] as String,
        icon: json['icon'] as String,
        summary: json['summary'] as String,
        summaryHi: json['summary_hi'] as String,
        steps: List<String>.from(json['steps'] as List),
        stepsHi: List<String>.from(json['steps_hi'] as List),
      );

  /// Returns the localised title based on the active language code.
  String localTitle(String lang) => lang == 'hi' ? titleHi : title;

  /// Returns the localised summary based on the active language code.
  String localSummary(String lang) => lang == 'hi' ? summaryHi : summary;

  /// Returns the localised steps list based on the active language code.
  List<String> localSteps(String lang) => lang == 'hi' ? stepsHi : steps;
}
