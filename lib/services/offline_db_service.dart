// lib/services/offline_db_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// OfflineDbService — pre-seeded SQLite knowledge base for ResQ.
//
// Purpose
// ───────
// When Gemma 4 cannot be loaded (device RAM too low, model file absent),
// this service provides instant answers to the 30 most critical emergency
// questions from a locally seeded SQLite table — with zero latency and
// zero network dependency.
//
// Design
// ──────
//   • Table: qa_pairs (id, keywords, answer_en, answer_hi, topic)
//   • 30 Q&A rows seeded on first launch (guarded by shared_preferences flag).
//   • fuzzySearch(query): scores each row by how many of the query's keywords
//     appear in its answer_en / answer_hi columns, returns the top-scoring row.
//   • Returns null if no keyword match found (caller shows generic message).
//
// Topics covered (2 Q&A per topic = 30 total):
//   CPR, wound/bleeding, flood, earthquake, wildfire, dehydration, fractures,
//   burns, shelter, shock, choking, heatstroke, hypothermia, drowning,
//   mental health.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class QaPair {
  final int    id;
  final String keywords;   // Space-separated keywords for fuzzy matching
  final String answerEn;   // English answer
  final String answerHi;   // Hindi answer
  final String topic;      // Topic label (e.g. 'CPR', 'flood')

  const QaPair({
    required this.id,
    required this.keywords,
    required this.answerEn,
    required this.answerHi,
    required this.topic,
  });

  factory QaPair.fromMap(Map<String, dynamic> m) => QaPair(
        id:       m['id'] as int,
        keywords: m['keywords'] as String,
        answerEn: m['answer_en'] as String,
        answerHi: m['answer_hi'] as String,
        topic:    m['topic'] as String,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class OfflineDbService {
  static const _seededKey = 'resq_qa_seeded_v4';

  /// Call this after DatabaseService has created / migrated the DB.
  Future<void> init(Database db) async {
    _db = db;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) != true) {
      await _seed();
      await prefs.setBool(_seededKey, true);
    }
  }

  late final Database _db;

  // ── Seeding ────────────────────────────────────────────────────────────────

  Future<void> _seed() async {
    await _db.delete('qa_pairs');
    final batch = _db.batch();
    for (final row in _seedData) {
      batch.insert('qa_pairs', row);
    }
    await batch.commit(noResult: true);
  }

  // ── Fuzzy Search ───────────────────────────────────────────────────────────

  /// Splits [query] into tokens, scores every Q&A row by keyword overlap,
  /// and returns the highest-scoring [QaPair].  Returns null if no match.
  Future<QaPair?> fuzzySearch(String query) async {
    // Extract 2+ character words from the query.
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'[\s,\.!?\-]+'))
        .where((t) => t.length >= 2)
        .toSet()
        .toList();

    if (tokens.isEmpty) return null;

    final rows = await _db.query('qa_pairs');
    if (rows.isEmpty) return null;

    QaPair? best;
    int    bestScore = 0;

    for (final row in rows) {
      final pair = QaPair.fromMap(row);
      final haystackTokens = '${pair.keywords} ${pair.answerEn} ${pair.answerHi}'
          .toLowerCase()
          .split(RegExp(r'[\s,\.!?\-]+'))
          .toSet();

      int score = 0;
      for (final token in tokens) {
        if (haystackTokens.contains(token)) {
          score += 2; // Exact word match
        } else if (haystackTokens.any((h) => h.startsWith(token))) {
          score += 1; // Prefix match (e.g. 'stop' matches 'stopped')
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = pair;
      }
    }

    // Require at least 1 keyword match to avoid garbage results.
    return bestScore >= 1 ? best : null;
  }

  // ── Seed data ──────────────────────────────────────────────────────────────
  // 30 Q&A rows, 2 per topic × 15 topics.
  // Each row has space-separated keywords for the fuzzy matcher.

  static final List<Map<String, dynamic>> _seedData = [
    // ── 1. CPR ──────────────────────────────────────────────────────────────
    {
      'keywords': 'cpr cardiac arrest heart stopped unresponsive resuscitation',
      'topic':    'CPR',
      'answer_en':
          '1. Check responsiveness — shout and tap shoulders.\n'
          '2. Call for help immediately.\n'
          '3. Push hard on centre of chest — 100–120/min, ≥2 inches deep.\n'
          '4. After 30 compressions, give 2 rescue breaths.\n'
          '5. Continue until help arrives or person shows signs of life.',
      'answer_hi':
          '1. होश जांचें — जोर से पुकारें और कंधे थपथपाएं।\n'
          '2. तुरंत मदद के लिए पुकारें।\n'
          '3. छाती के बीच जोर से दबाएं — 100–120/मिनट, ≥2 इंच गहरा।\n'
          '4. 30 बार दबाने के बाद 2 सांसें दें।\n'
          '5. मदद आने तक जारी रखें।',
    },
    {
      'keywords': 'cpr infant child baby not breathing no pulse',
      'topic':    'CPR',
      'answer_en':
          'Child CPR (1–8 yrs): 2 fingers or 1 hand, compress 1.5–2 inches, 30:2 ratio.\n'
          'Infant CPR (<1 yr): 2 fingers on breastbone, gentle puffs only.\n'
          'Start with 5 rescue breaths for drowning victims before compressions.',
      'answer_hi':
          'बच्चे CPR (1–8 वर्ष): 2 उंगली या 1 हाथ, 1.5–2 इंच, 30:2 अनुपात।\n'
          'शिशु CPR (<1 वर्ष): स्तन हड्डी पर 2 उंगली, हल्की फूंक।\n'
          'डूबने की स्थिति में पहले 5 सांसें दें।',
    },

    // ── 2. Wound / Bleeding ───────────────────────────────────────────────────
    {
      'keywords': 'bleeding wound blood cut gash severe haemorrhage',
      'topic':    'Wound',
      'answer_en':
          '1. Apply firm direct pressure with a clean cloth.\n'
          '2. Do not remove cloth if soaked — add more on top.\n'
          '3. Elevate injured limb above heart level.\n'
          '4. For severe limb bleeding apply tourniquet 2–3 inches above wound.\n'
          '5. Note the time tourniquet was applied.',
      'answer_hi':
          '1. साफ कपड़े से सीधा दबाव दें।\n'
          '2. कपड़ा भीगे तो न हटाएं — ऊपर और रखें।\n'
          '3. घायल अंग को दिल से ऊपर उठाएं।\n'
          '4. गंभीर रक्तस्राव में घाव से 2–3 इंच ऊपर टर्निकेट लगाएं।\n'
          '5. टर्निकेट का समय नोट करें।',
    },
    {
      'keywords': 'wound cleaning infection dirty bacteria antiseptic',
      'topic':    'Wound',
      'answer_en':
          '1. Wash hands before touching the wound.\n'
          '2. Rinse wound with clean water for several minutes.\n'
          '3. Remove visible dirt with clean tweezers.\n'
          '4. Do NOT use hydrogen peroxide or iodine directly — damages tissue.\n'
          '5. Cover with clean bandage and change daily.',
      'answer_hi':
          '1. घाव छूने से पहले हाथ धोएं।\n'
          '2. साफ पानी से कई मिनट तक धोएं।\n'
          '3. साफ चिमटी से गंदगी हटाएं।\n'
          '4. हाइड्रोजन पेरोक्साइड या आयोडीन सीधे न लगाएं।\n'
          '5. साफ पट्टी लगाएं और रोज बदलें।',
    },

    // ── 3. Flood ─────────────────────────────────────────────────────────────
    {
      'keywords': 'flood flash flood water rising submerged trapped',
      'topic':    'Flood',
      'answer_en':
          '1. Move to higher ground immediately — do not wait for instructions.\n'
          '2. Do NOT walk through moving water (6 inches can knock you down).\n'
          '3. Do not drive through flooded roads.\n'
          '4. If trapped in building, move to highest floor.\n'
          '5. Signal rescuers with bright cloth or flashlight from window.',
      'answer_hi':
          '1. तुरंत ऊंची जगह पर जाएं — प्रतीक्षा न करें।\n'
          '2. बहते पानी में न चलें (6 इंच पानी गिरा सकता है)।\n'
          '3. बाढ़ वाली सड़कों पर गाड़ी न चलाएं।\n'
          '4. इमारत में फंसे हों तो सबसे ऊपरी मंजिल पर जाएं।\n'
          '5. खिड़की से कपड़े या टॉर्च से बचावकर्ताओं को संकेत दें।',
    },
    {
      'keywords': 'flood after contaminated water disease leptospirosis',
      'topic':    'Flood',
      'answer_en':
          'After a flood:\n'
          '1. Avoid floodwater — it may contain sewage, chemicals, and disease.\n'
          '2. Do not eat food that has been in contact with floodwater.\n'
          '3. Boil all drinking water for 1 minute before use.\n'
          '4. Wear rubber boots and gloves when entering flooded areas.\n'
          '5. Watch for signs of leptospirosis — fever, headache, red eyes.',
      'answer_hi':
          'बाढ़ के बाद:\n'
          '1. बाढ़ के पानी से बचें — सीवेज और रसायन हो सकते हैं।\n'
          '2. बाढ़ में डूबा खाना न खाएं।\n'
          '3. पीने का पानी 1 मिनट उबालें।\n'
          '4. बाढ़ क्षेत्र में जाते समय रबर जूते और दस्ताने पहनें।\n'
          '5. लेप्टोस्पायरोसिस के संकेत देखें — बुखार, सिरदर्द, लाल आंखें।',
    },

    // ── 4. Earthquake ─────────────────────────────────────────────────────────
    {
      'keywords': 'earthquake tremor shake aftershock drop cover hold',
      'topic':    'Earthquake',
      'answer_en':
          '1. DROP to hands and knees immediately.\n'
          '2. COVER under a sturdy table or against an interior wall.\n'
          '3. HOLD ON — protect head and neck with arms.\n'
          '4. Stay inside until shaking stops.\n'
          '5. After shaking, evacuate carefully — watch for falling debris.',
      'answer_hi':
          '1. तुरंत हाथों और घुटनों पर झुक जाएं।\n'
          '2. मजबूत मेज के नीचे या दीवार के पास आश्रय लें।\n'
          '3. थामे रहें — हाथों से सिर और गर्दन बचाएं।\n'
          '4. झटके बंद होने तक अंदर रहें।\n'
          '5. झटके बाद सावधानी से निकलें — मलबे से बचें।',
    },
    {
      'keywords': 'earthquake trapped rubble building collapse rescue',
      'topic':    'Earthquake',
      'answer_en':
          'If trapped under rubble:\n'
          '1. Do not light a match — there may be gas leaks.\n'
          '2. Cover nose/mouth with cloth to filter dust.\n'
          '3. Signal by tapping on pipes or walls — do not shout (wastes air/energy).\n'
          '4. Use a whistle if available — 3 blasts, pause, repeat.\n'
          '5. Stay calm and conserve energy while waiting for rescue.',
      'answer_hi':
          'मलबे में फंसे हों:\n'
          '1. माचिस मत जलाएं — गैस रिसाव हो सकती है।\n'
          '2. धूल छानने के लिए नाक-मुंह पर कपड़ा रखें।\n'
          '3. पाइप या दीवारों पर थपथपाएं — चिल्लाएं नहीं।\n'
          '4. सीटी हो तो — 3 बार बजाएं, रुकें, दोहराएं।\n'
          '5. शांत रहें और ऊर्जा बचाएं।',
    },

    // ── 5. Wildfire ───────────────────────────────────────────────────────────
    {
      'keywords': 'wildfire fire evacuation escape smoke ash flame',
      'topic':    'Wildfire',
      'answer_en':
          '1. Evacuate immediately when ordered — do not delay.\n'
          '2. Close all windows and doors to slow fire entry.\n'
          '3. Wear N95 mask or cover nose/mouth with damp cloth.\n'
          '4. Drive with headlights on and windows closed.\n'
          '5. Do not shelter under trees or powerlines.',
      'answer_hi':
          '1. निकासी आदेश मिलते ही तुरंत निकलें।\n'
          '2. आग को धीमा करने के लिए खिड़की-दरवाजे बंद करें।\n'
          '3. N95 मास्क या नम कपड़े से नाक-मुंह ढकें।\n'
          '4. हेडलाइट जलाकर और खिड़कियां बंद कर गाड़ी चलाएं।\n'
          '5. पेड़ों या बिजली लाइनों के नीचे न रुकें।',
    },
    {
      'keywords': 'wildfire trapped vehicle car surrounded unable escape',
      'topic':    'Wildfire',
      'answer_en':
          'If surrounded by wildfire in a vehicle:\n'
          '1. Park off the road, turn off engine.\n'
          '2. Turn on hazard lights and leave engine running for ventilation.\n'
          '3. Lie on the floor below window level.\n'
          '4. Cover yourself with a wool blanket if available.\n'
          '5. Do not run — the vehicle is safer than open air during fire passage.',
      'answer_hi':
          'गाड़ी में जंगल की आग से घिर जाएं:\n'
          '1. सड़क से हटकर रुकें, इंजन बंद करें।\n'
          '2. हैजार्ड लाइट्स चालू करें।\n'
          '3. खिड़की के स्तर से नीचे फर्श पर लेट जाएं।\n'
          '4. ऊनी कंबल से खुद को ढकें।\n'
          '5. बाहर न भागें — आग के गुजरते समय गाड़ी ज्यादा सुरक्षित है।',
    },

    // ── 6. Dehydration ────────────────────────────────────────────────────────
    {
      'keywords': 'dehydration thirst find water purify drink diarrhea vomiting',
      'topic':    'Dehydration',
      'answer_en':
          '1. Signs: dark urine, dizziness, dry mouth, confusion, sunken eyes.\n'
          '2. Sip small amounts of water frequently — not large amounts at once.\n'
          '3. To purify water: boil for 1 minute (3 min at high altitude).\n'
          '4. No fuel: add 2 drops bleach per litre, wait 30 min.\n'
          '5. Avoid alcohol and caffeine — they worsen dehydration.',
      'answer_hi':
          '1. संकेत: गहरा पेशाब, चक्कर, सूखा मुंह, भ्रम।\n'
          '2. बार-बार छोटे घूंट पिएं।\n'
          '3. पानी शुद्ध करें: 1 मिनट उबालें (ऊंचाई पर 3 मिनट)।\n'
          '4. ईंधन नहीं: प्रति लीटर 2 बूंद ब्लीच, 30 मिनट प्रतीक्षा।\n'
          '5. शराब और कैफीन से बचें।',
    },
    {
      'keywords': 'oral rehydration salt ors electrolyte diarrhea vomiting',
      'topic':    'Dehydration',
      'answer_en':
          'Homemade ORS (Oral Rehydration Solution):\n'
          '1. Mix 1 litre of clean water.\n'
          '2. Add 6 level teaspoons of sugar.\n'
          '3. Add 0.5 teaspoon of salt.\n'
          '4. Stir until dissolved.\n'
          '5. Give small sips every few minutes — especially for diarrhoea patients.',
      'answer_hi':
          'घर पर ORS बनाएं:\n'
          '1. 1 लीटर साफ पानी लें।\n'
          '2. 6 चम्मच चीनी डालें।\n'
          '3. आधा चम्मच नमक डालें।\n'
          '4. घुलने तक हिलाएं।\n'
          '5. हर कुछ मिनट में छोटे घूंट दें।',
    },

    // ── 7. Fractures ──────────────────────────────────────────────────────────
    {
      'keywords': 'fracture broken bone splint immobilize arm leg',
      'topic':    'Fracture',
      'answer_en':
          '1. Do not try to straighten the bone.\n'
          '2. Immobilize in position found.\n'
          '3. Use rigid material (board, rolled newspaper) as splint.\n'
          '4. Pad splint and secure with cloth ties above/below fracture.\n'
          '5. Check circulation (pulse, colour, warmth) beyond the splint.',
      'answer_hi':
          '1. हड्डी को सीधा करने की कोशिश न करें।\n'
          '2. जिस स्थिति में पाएं उसी में स्थिर रखें।\n'
          '3. कठोर सामग्री को स्प्लिंट बनाएं।\n'
          '4. गद्देदार बनाकर फ्रैक्चर के ऊपर-नीचे बांधें।\n'
          '5. स्प्लिंट के आगे रक्त संचार जांचें।',
    },
    {
      'keywords': 'spine neck back injury do not move paralysis',
      'topic':    'Fracture',
      'answer_en':
          'Suspected spinal injury:\n'
          '1. Do NOT move the person unless in immediate danger.\n'
          '2. Tell them to keep absolutely still.\n'
          '3. Stabilise the head and neck in the position found.\n'
          '4. Do not lift or twist the neck or back.\n'
          '5. Wait for trained rescue — spinal movement can cause paralysis.',
      'answer_hi':
          'रीढ़ की चोट का संदेह:\n'
          '1. व्यक्ति को हिलाएं नहीं जब तक तत्काल खतरा न हो।\n'
          '2. बिल्कुल स्थिर रहने को कहें।\n'
          '3. सिर और गर्दन को स्थिर करें।\n'
          '4. गर्दन या पीठ न उठाएं न मोड़ें।\n'
          '5. प्रशिक्षित बचाव का इंतजार करें।',
    },

    // ── 8. Burns ──────────────────────────────────────────────────────────────
    {
      'keywords': 'burn fire scald hot water chemical heat blister',
      'topic':    'Burns',
      'answer_en':
          '1. Cool with cool (not cold) running water for 10–20 minutes.\n'
          '2. Do NOT use ice, butter, or toothpaste.\n'
          '3. Cover loosely with clean non-fluffy bandage.\n'
          '4. Do not pop blisters.\n'
          '5. For large/deep burns: cover and seek immediate medical help.',
      'answer_hi':
          '1. 10–20 मिनट ठंडे (बर्फ नहीं) पानी से ठंडा करें।\n'
          '2. बर्फ, मक्खन या टूथपेस्ट न लगाएं।\n'
          '3. साफ पट्टी से ढीले ढंग से ढकें।\n'
          '4. फफोले न फोड़ें।\n'
          '5. बड़े/गहरे जलने के लिए तुरंत मदद लें।',
    },
    {
      'keywords': 'chemical burn acid alkaline eye skin flush',
      'topic':    'Burns',
      'answer_en':
          'Chemical burn:\n'
          '1. Brush off dry chemical before adding water.\n'
          '2. Flush with large amounts of water for 20+ minutes.\n'
          '3. Remove contaminated clothing while flushing.\n'
          '4. For eye exposure: irrigate with water continuously for 20 minutes.\n'
          '5. Do not neutralise acid with alkali or vice versa.',
      'answer_hi':
          'रासायनिक जलन:\n'
          '1. पानी डालने से पहले सूखे रसायन को झाड़ें।\n'
          '2. 20+ मिनट तक भरपूर पानी से धोएं।\n'
          '3. धोते समय दूषित कपड़े हटाएं।\n'
          '4. आंखों में हो: 20 मिनट लगातार पानी से धोएं।\n'
          '5. एसिड को क्षार से बेअसर करने की कोशिश न करें।',
    },

    // ── 9. Shelter ────────────────────────────────────────────────────────────
    {
      'keywords': 'shelter build emergency overnight survival rain cold',
      'topic':    'Shelter',
      'answer_en':
          'Improvised emergency shelter:\n'
          '1. Find natural windbreaks — rock faces, dense trees, hillsides.\n'
          '2. Insulate from the ground first (leaves, branches) — ground steals heat fastest.\n'
          '3. Build a lean-to with branches and cover with leaves or tarp.\n'
          '4. Keep the shelter small — body heat warms small spaces faster.\n'
          '5. Mark your location visibly for rescuers.',
      'answer_hi':
          'आपातकालीन आश्रय बनाएं:\n'
          '1. प्राकृतिक आड़ खोजें — चट्टान, घने पेड़, पहाड़ी।\n'
          '2. पहले जमीन से इंसुलेट करें — जमीन तेजी से गर्मी चुराती है।\n'
          '3. टहनियों से लीन-टू बनाकर पत्तियों या तिरपाल से ढकें।\n'
          '4. आश्रय को छोटा रखें — शरीर की गर्मी तेज काम करती है।\n'
          '5. बचावकर्ताओं के लिए अपनी स्थिति स्पष्ट चिह्नित करें।',
    },
    {
      'keywords': 'shelter urban building safe collapse aftershock gas leak',
      'topic':    'Shelter',
      'answer_en':
          'Sheltering in a damaged building:\n'
          '1. Do not enter if walls are visibly cracked or floors buckled.\n'
          '2. Turn off gas at the main valve if you smell gas.\n'
          '3. Stay away from damaged utilities (fallen power lines).\n'
          '4. Use stairs only — lifts may be damaged.\n'
          '5. Stay on the ground floor or evacuate if aftershocks expected.',
      'answer_hi':
          'क्षतिग्रस्त इमारत में आश्रय:\n'
          '1. अगर दीवारें टूटी हों तो अंदर न जाएं।\n'
          '2. गैस की गंध हो तो मुख्य वाल्व बंद करें।\n'
          '3. गिरी बिजली लाइनों से दूर रहें।\n'
          '4. केवल सीढ़ियां उपयोग करें — लिफ्ट क्षतिग्रस्त हो सकती है।\n'
          '5. आफ्टरशॉक की संभावना हो तो भूतल पर रहें या निकलें।',
    },

    // ── 10. Shock ─────────────────────────────────────────────────────────────
    {
      'keywords': 'shock trauma blood loss pale cold clammy rapid pulse',
      'topic':    'Shock',
      'answer_en':
          '1. Lay flat and elevate legs 12 inches (unless spinal injury).\n'
          '2. Signs: pale/cold skin, rapid weak pulse, confusion, rapid breathing.\n'
          '3. Keep warm with a blanket.\n'
          '4. Do not give food or water.\n'
          '5. Monitor breathing; be ready to perform CPR.',
      'answer_hi':
          '1. लिटाएं और पैर 12 इंच ऊपर करें (रीढ़ चोट न हो तो)।\n'
          '2. संकेत: पीली/ठंडी त्वचा, तेज कमजोर नाड़ी, भ्रम।\n'
          '3. कंबल से गर्म रखें।\n'
          '4. खाना या पानी न दें।\n'
          '5. सांस की निगरानी करें; CPR के लिए तैयार रहें।',
    },
    {
      'keywords': 'anaphylaxis allergic reaction swelling throat breathing epinephrine',
      'topic':    'Shock',
      'answer_en':
          'Anaphylactic shock:\n'
          '1. Use epinephrine auto-injector (EpiPen) immediately if available.\n'
          '2. Lay flat with legs elevated (or sit up if breathing is difficult).\n'
          '3. Call emergency services immediately.\n'
          '4. Be ready to give CPR if breathing stops.\n'
          '5. Loosen tight clothing around neck and waist.',
      'answer_hi':
          'एनाफिलेक्टिक शॉक:\n'
          '1. उपलब्ध हो तो तुरंत एपिनेफ्रिन इंजेक्टर (EpiPen) लगाएं।\n'
          '2. लिटाएं; सांस लेने में कठिनाई हो तो बैठाएं।\n'
          '3. तुरंत आपातकालीन उपचार का अनुरोध करें।\n'
          '4. सांस रुके तो CPR के लिए तैयार रहें।\n'
          '5. गर्दन और कमर के कपड़े ढीले करें।',
    },

    // ── 11. Choking ───────────────────────────────────────────────────────────
    {
      'keywords': 'choking heimlich cannot breathe speak silent cough object throat',
      'topic':    'Choking',
      'answer_en':
          '1. Ask: "Are you choking?" — if silent cough, act immediately.\n'
          '2. Give 5 firm back blows between shoulder blades.\n'
          '3. Give 5 abdominal thrusts: stand behind, arms around waist, thrust inward/upward.\n'
          '4. Alternate back blows and thrusts until object dislodges.\n'
          '5. If unconscious, begin CPR.',
      'answer_hi':
          '1. पूछें "क्या आपका गला रुक गया?" — तुरंत काम करें।\n'
          '2. कंधे के ब्लेड के बीच 5 बार जोर से मारें।\n'
          '3. पेट पर 5 बार जोर लगाएं: पीछे से हाथ कमर के चारों ओर।\n'
          '4. वस्तु निकलने तक बारी-बारी से दोहराएं।\n'
          '5. बेहोश हो जाएं तो CPR शुरू करें।',
    },
    {
      'keywords': 'choking pregnant obese large person alternative technique',
      'topic':    'Choking',
      'answer_en':
          'Choking in pregnant or obese persons:\n'
          '1. Give 5 back blows first (same as standard).\n'
          '2. For chest thrusts instead of abdominal: place hands on centre of chest.\n'
          '3. Push straight inward 1.5–2 inches.\n'
          '4. Repeat until object dislodges or person becomes unconscious.\n'
          '5. If unconscious, start CPR and look in mouth before each breath.',
      'answer_hi':
          'गर्भवती या मोटे व्यक्ति में गला रुकना:\n'
          '1. पहले 5 पीठ थपथपाएं।\n'
          '2. पेट की जगह छाती पर दबाएं: छाती के बीच हाथ रखें।\n'
          '3. सीधे अंदर 1.5–2 इंच दबाएं।\n'
          '4. बेहोश होने तक या वस्तु निकलने तक दोहराएं।\n'
          '5. बेहोश हो जाएं तो CPR शुरू करें।',
    },

    // ── 12. Heatstroke ────────────────────────────────────────────────────────
    {
      'keywords': 'heatstroke heat exhaustion fever confusion hot dry skin',
      'topic':    'Heatstroke',
      'answer_en':
          '1. Move to a cool shaded area immediately.\n'
          '2. Remove excess clothing.\n'
          '3. Cool rapidly: wet cloths, fanning, cool water on skin.\n'
          '4. Focus on neck, armpits, and groin (large blood vessels).\n'
          '5. Give cool water if conscious. Seek medical help urgently — heatstroke is life-threatening.',
      'answer_hi':
          '1. तुरंत ठंडी छायादार जगह पर ले जाएं।\n'
          '2. अतिरिक्त कपड़े हटाएं।\n'
          '3. तेजी से ठंडा करें: नम कपड़े, पंखा, ठंडा पानी।\n'
          '4. गर्दन, बगल और जांघ पर ध्यान दें।\n'
          '5. होश में हो तो ठंडा पानी दें। जानलेवा है — तुरंत मदद लें।',
    },
    {
      'keywords': 'heat cramp exhaustion dizziness sweating pale cool',
      'topic':    'Heatstroke',
      'answer_en':
          'Heat exhaustion (milder than heatstroke):\n'
          '1. Move person to a cool area.\n'
          '2. Have them lie down with legs slightly elevated.\n'
          '3. Apply cool, wet cloths to the skin.\n'
          '4. Sip cool water or sports drink slowly.\n'
          '5. If not improved in 15 minutes or condition worsens, treat as heatstroke.',
      'answer_hi':
          'हीट एग्जॉशन (हीटस्ट्रोक से कम गंभीर):\n'
          '1. ठंडी जगह पर ले जाएं।\n'
          '2. पैर थोड़े ऊपर करके लिटाएं।\n'
          '3. त्वचा पर ठंडे नम कपड़े रखें।\n'
          '4. ठंडा पानी या स्पोर्ट्स ड्रिंक धीरे-धीरे पिलाएं।\n'
          '5. 15 मिनट में सुधार न हो तो हीटस्ट्रोक मानें।',
    },

    // ── 13. Hypothermia ───────────────────────────────────────────────────────
    {
      'keywords': 'hypothermia cold freeze shiver temperature body warmth',
      'topic':    'Hypothermia',
      'answer_en':
          '1. Move to a warm dry area immediately.\n'
          '2. Remove wet clothing gently.\n'
          '3. Warm core first: chest, neck, groin — blankets or body heat.\n'
          '4. Do NOT rub limbs vigorously — risk of cardiac arrest.\n'
          '5. Give warm (not hot) beverages if conscious and can swallow.',
      'answer_hi':
          '1. तुरंत गर्म सूखी जगह पर ले जाएं।\n'
          '2. गीले कपड़े धीरे से हटाएं।\n'
          '3. पहले शरीर का मुख्य भाग गर्म करें: छाती, गर्दन, जांघ।\n'
          '4. हाथ-पैरों को जोर से न रगड़ें — कार्डियक अरेस्ट का खतरा।\n'
          '5. होश में हो और निगल सके तो गर्म पेय दें।',
    },
    {
      'keywords': 'frostbite frozen finger toe ear nose numb white blue',
      'topic':    'Hypothermia',
      'answer_en':
          'Frostbite:\n'
          '1. Do NOT rewarm if refreezing is possible — that causes more damage.\n'
          '2. Move to a warm area before rewarming.\n'
          '3. Rewarm affected parts gently in warm water (37–40°C / 99–104°F).\n'
          '4. Do not rub frostbitten skin — causes tissue damage.\n'
          '5. Cover with loose sterile bandages after rewarming.',
      'answer_hi':
          'फ्रॉस्टबाइट:\n'
          '1. अगर दोबारा जमने का खतरा हो तो गर्म न करें।\n'
          '2. गर्म जगह पर जाने के बाद ही गर्म करें।\n'
          '3. गर्म पानी (37–40°C) में धीरे से गर्म करें।\n'
          '4. ठंडी त्वचा को न रगड़ें।\n'
          '5. गर्म करने के बाद ढीली ड्रेसिंग लगाएं।',
    },

    // ── 14. Drowning ──────────────────────────────────────────────────────────
    {
      'keywords': 'drowning water rescue unconscious not breathing nearly drowned',
      'topic':    'Drowning',
      'answer_en':
          '1. Do not enter water unless trained — throw a rope or flotation aid.\n'
          '2. Once onshore, check responsiveness and breathing.\n'
          '3. If not breathing: start CPR with 5 rescue breaths first (before compressions).\n'
          '4. Continue 30:2 compression-breath ratio.\n'
          '5. Keep warm — drowning victims lose body heat rapidly.',
      'answer_hi':
          '1. प्रशिक्षित न हों तो पानी में न जाएं — रस्सी फेंकें।\n'
          '2. किनारे पर आने के बाद होश और सांस जांचें।\n'
          '3. सांस न हो: पहले 5 सांसें दें फिर CPR करें।\n'
          '4. 30:2 का अनुपात जारी रखें।\n'
          '5. गर्म रखें — डूबने वाले तेजी से ठंडे हो जाते हैं।',
    },
    {
      'keywords': 'drowning swimming current rip current river sea boat capsize',
      'topic':    'Drowning',
      'answer_en':
          'Caught in a rip current:\n'
          '1. Do NOT swim directly against the current — you will exhaust yourself.\n'
          '2. Swim parallel to shore until out of the current.\n'
          '3. Then swim diagonally back to shore.\n'
          '4. Float on your back to rest and conserve energy.\n'
          '5. Signal for help by waving one arm.',
      'answer_hi':
          'रिप करंट में फंस जाएं:\n'
          '1. सीधे करंट के विरुद्ध तैरने की कोशिश न करें।\n'
          '2. किनारे के समानांतर तैरें जब तक करंट से बाहर न हों।\n'
          '3. फिर तिरछे किनारे की ओर तैरें।\n'
          '4. ऊर्जा बचाने के लिए पीठ के बल तैरें।\n'
          '5. एक हाथ हिलाकर मदद के लिए संकेत दें।',
    },

    // ── 15. Mental Health ─────────────────────────────────────────────────────
    {
      'keywords': 'mental health panic attack anxiety stress trauma PTSD disaster',
      'topic':    'Mental Health',
      'answer_en':
          '1. Acknowledge feelings — fear, anger, and numbness are normal.\n'
          '2. Panic attack: breathe in 4 counts, hold 4, out 4. Repeat.\n'
          '3. Stay connected — isolation worsens trauma.\n'
          '4. Maintain routines: eating, sleeping at regular times.\n'
          '5. Limit excessive disaster news consumption.',
      'answer_hi':
          '1. भावनाओं को स्वीकारें — डर, गुस्सा, सुन्नपन सामान्य है।\n'
          '2. पैनिक अटैक: 4 में सांस लें, 4 रोकें, 4 में छोड़ें।\n'
          '3. जुड़े रहें — अकेलापन आघात बढ़ाता है।\n'
          '4. नियमित खाना-सोना बनाए रखें।\n'
          '5. अत्यधिक समाचार देखने से बचें।',
    },
    {
      'keywords': 'child mental health scared crying shock disaster children comfort',
      'topic':    'Mental Health',
      'answer_en':
          'Supporting children after disaster:\n'
          '1. Stay calm yourself — children mirror adult emotions.\n'
          '2. Give honest, age-appropriate explanations.\n'
          '3. Maintain routines as much as possible.\n'
          '4. Allow them to express feelings through drawing or talking.\n'
          '5. Limit children\'s exposure to disaster imagery and news.',
      'answer_hi':
          'आपदा के बाद बच्चों की मदद:\n'
          '1. खुद शांत रहें — बच्चे वयस्कों की भावनाएं दर्शाते हैं।\n'
          '2. उम्र के अनुसार सरल और सच्ची जानकारी दें।\n'
          '3. जितना हो सके दिनचर्या बनाए रखें।\n'
          '4. ड्राइंग या बातचीत से भावनाएं व्यक्त करने दें।\n'
          '5. आपदा की तस्वीरें और खबरें बच्चों से दूर रखें।',
    },
    // ── 16. Snakebite ────────────────────────────────────────────────────────
    {
      'keywords': 'snake snakebite bite venom poisonous cobra viper',
      'topic':    'Snakebite',
      'answer_en':
          '1. Keep the victim calm and absolutely still to slow venom spread.\n'
          '2. Keep the bitten area below the level of the heart.\n'
          '3. Remove tight clothing, rings, or watches near the bite.\n'
          '4. Do NOT cut the wound, attempt to suck out venom, or apply ice.\n'
          '5. Seek immediate emergency medical care for antivenom.',
      'answer_hi':
          '1. पीड़ित को शांत और बिल्कुल स्थिर रखें।\n'
          '2. काटे गए अंग को दिल के स्तर से नीचे रखें।\n'
          '3. घाव के पास से अंगूठियां या तंग कपड़े हटा दें।\n'
          '4. घाव को न काटें, जहर न चूसें और बर्फ न लगाएं।\n'
          '5. एंटीवेनम के लिए तुरंत अस्पताल जाएं।',
    },
    {
      'keywords': 'snakebite tourniquet tie wrap bandage venom restrict',
      'topic':    'Snakebite',
      'answer_en':
          '1. Do NOT apply a tight tourniquet (can cause limb loss).\n'
          '2. You may apply a broad pressure bandage over the bite.\n'
          '3. Wrap it firmly like a sprained ankle, but not so tight it stops blood flow.\n'
          '4. Immobilize the limb using a splint.\n'
          '5. Carry the victim if possible; do not let them walk.',
      'answer_hi':
          '1. तंग टर्निकेट (रस्सी) न बांधें (अंग काटना पड़ सकता है)।\n'
          '2. आप घाव पर चौड़ी दबाव वाली पट्टी बांध सकते हैं।\n'
          '3. इसे मोच की तरह मजबूती से बांधें, लेकिन खून न रुके।\n'
          '4. स्प्लिंट का उपयोग कर अंग को स्थिर करें।\n'
          '5. हो सके तो पीड़ित को उठाकर ले जाएं; चलने न दें।',
    },

    // ── 17. Heart Attack ─────────────────────────────────────────────────────
    {
      'keywords': 'heart attack chest pain pressure squeeze left arm jaw',
      'topic':    'Heart Attack',
      'answer_en':
          '1. Have the person sit down, rest, and try to keep calm.\n'
          '2. Loosen any tight clothing around the neck and chest.\n'
          '3. Ask if they take chest pain medication (like nitroglycerin) and help them take it.\n'
          '4. If conscious and not allergic, give them one adult aspirin to chew.\n'
          '5. Call emergency services immediately. If unconscious, begin CPR.',
      'answer_hi':
          '1. व्यक्ति को बैठाएं, आराम कराएं और शांत रखें।\n'
          '2. गर्दन और छाती के आसपास के तंग कपड़े ढीले करें।\n'
          '3. अगर उनके पास सीने के दर्द की दवा हो तो लेने में मदद करें।\n'
          '4. अगर होश में हैं और एलर्जी नहीं है, तो एक एस्पिरिन चबाने को दें।\n'
          '5. तुरंत एंबुलेंस बुलाएं। बेहोश होने पर CPR शुरू करें।',
    },

    // ── 18. Poisoning ────────────────────────────────────────────────────────
    {
      'keywords': 'poison swallowed drank toxic chemical bleach cleaner acid',
      'topic':    'Poisoning',
      'answer_en':
          '1. Find out exactly what was swallowed, how much, and when.\n'
          '2. Do NOT induce vomiting unless instructed by a medical professional.\n'
          '3. Do NOT give water or milk to drink unless advised (can worsen chemical burns).\n'
          '4. Wipe any remaining poison from the mouth with a cloth.\n'
          '5. Keep the container and bring it to the hospital.',
      'answer_hi':
          '1. पता लगाएं कि क्या, कितना और कब निगला गया है।\n'
          '2. डॉक्टर के कहे बिना उल्टी कराने की कोशिश न करें।\n'
          '3. सलाह के बिना पानी या दूध न दें (जहर फैल सकता है)।\n'
          '4. मुंह में बचे हुए जहर को कपड़े से पोंछ लें।\n'
          '5. जहर का डिब्बा संभाल कर रखें और अस्पताल ले जाएं।',
    },

    // ── 19. Power Outage ─────────────────────────────────────────────────────
    {
      'keywords': 'power outage blackout electricity cut grid failure dark',
      'topic':    'Power Outage',
      'answer_en':
          '1. Use flashlights instead of candles to prevent fire hazards.\n'
          '2. Keep refrigerators and freezers closed (food stays cold for hours).\n'
          '3. Unplug major appliances to protect them from power surges when power returns.\n'
          '4. Do not use gas stoves, grills, or generators indoors due to carbon monoxide risk.\n'
          '5. Listen to a battery-powered radio for local updates.',
      'answer_hi':
          '1. आग से बचने के लिए मोमबत्ती के बजाय टॉर्च का उपयोग करें।\n'
          '2. फ्रिज के दरवाजे बंद रखें (खाना घंटों तक ठंडा रहेगा)।\n'
          '3. बिजली आने पर झटके से बचाने के लिए बड़े उपकरण अनप्लग करें।\n'
          '4. गैस स्टोव या जनरेटर का घर के अंदर उपयोग न करें (जहरीली गैस का खतरा)।\n'
          '5. स्थानीय समाचार के लिए बैटरी वाला रेडियो सुनें।',
    },

    // ── 20. Dog / Animal Bite ────────────────────────────────────────────────
    {
      'keywords': 'dog bite animal stray rabies scratch teeth wound infection',
      'topic':    'Animal Bite',
      'answer_en':
          '1. Wash the wound immediately with plenty of soap and running water for 15 minutes.\n'
          '2. Apply an antiseptic or iodine lotion if available.\n'
          '3. Cover with a clean, sterile bandage.\n'
          '4. Seek medical attention immediately for rabies and tetanus vaccinations.\n'
          '5. Try to note the animal\'s appearance and location for health authorities.',
      'answer_hi':
          '1. घाव को तुरंत बहुत सारे साबुन और बहते पानी से 15 मिनट तक धोएं।\n'
          '2. अगर हो तो एंटीसेप्टिक या आयोडीन लोशन लगाएं।\n'
          '3. साफ, कीटाणुरहित पट्टी से ढक दें।\n'
          '4. रेबीज और टिटनेस के टीके के लिए तुरंत डॉक्टर के पास जाएं।\n'
          '5. जानवर की पहचान और स्थान याद रखें।',
    },
  ];
}
