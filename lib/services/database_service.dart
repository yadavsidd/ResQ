// lib/services/database_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// DatabaseService — manages the local SQLite database via sqflite.
//
// Tables:
//   • chat_messages   — persists the AI chat conversation history
//   • checklist_items — stores AI-generated emergency checklist items
//   • saved_locations — stores GPS pins dropped on the offline map
//   • qa_pairs        — [v2] seeded offline knowledge base for AI fallback
//
// All operations are asynchronous and use WAL journal mode for better concurrency.
// No network connection is ever used — this is a 100% offline service.

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/chat_message.dart';
import '../models/checklist_item.dart';
import '../models/saved_location.dart';

class DatabaseService {
  static const _dbName = 'resq.db';
  static const _dbVersion = 3; // v3: added capacity to saved_locations, seeded JAIPUR data

  Database? _db;

  /// Exposes the raw database to other services (e.g. OfflineDbService).
  Database get rawDb => _database;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Opens (or creates) the SQLite database and runs migrations.
  Future<void> init() async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // Enable WAL for better concurrent read/write performance.
        // Must use rawQuery inside onConfigure — execute() is not permitted here.
        await db.rawQuery('PRAGMA journal_mode=WAL');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Chat messages table
    await db.execute('''
      CREATE TABLE chat_messages (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        text      TEXT    NOT NULL,
        role      TEXT    NOT NULL,
        timestamp TEXT    NOT NULL
      )
    ''');

    // Checklist items table
    await db.execute('''
      CREATE TABLE checklist_items (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        text       TEXT    NOT NULL,
        is_checked INTEGER NOT NULL DEFAULT 0,
        session_id INTEGER NOT NULL,
        created_at TEXT    NOT NULL
      )
    ''');

    // Saved map locations table
    await db.execute('''
      CREATE TABLE saved_locations (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        label     TEXT    NOT NULL,
        latitude  REAL    NOT NULL,
        longitude REAL    NOT NULL,
        type      TEXT    NOT NULL DEFAULT 'custom',
        capacity  INTEGER,
        saved_at  TEXT    NOT NULL
      )
    ''');

    // Q&A knowledge-base table (v2) — seeded by OfflineDbService
    await _createQaPairsTable(db);
  }

  /// Runs when an existing DB is opened at a higher version number.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createQaPairsTable(db);
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE saved_locations ADD COLUMN capacity INTEGER');
    }
  }

  Future<void> _createQaPairsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS qa_pairs (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        keywords  TEXT    NOT NULL,
        answer_en TEXT    NOT NULL,
        answer_hi TEXT    NOT NULL,
        topic     TEXT    NOT NULL
      )
    ''');
  }

  /// Seeds 10 real sample locations for Jaipur, India.
  Future<void> seedInitialLocations() async {
    final count = Sqflite.firstIntValue(
        await _database.rawQuery('SELECT COUNT(*) FROM saved_locations WHERE type != "custom"'));
    if (count != null && count > 0) return; // already seeded

    final batch = _database.batch();
    final now = DateTime.now().toIso8601String();
    
    final locations = [
      {'label': 'SMS Hospital', 'lat': 26.8943, 'lon': 75.8156, 'type': 'hospital', 'cap': 200},
      {'label': 'Fortis Hospital', 'lat': 26.8485, 'lon': 75.8015, 'type': 'hospital', 'cap': 150},
      {'label': 'Jaipur Central Shelter', 'lat': 26.9124, 'lon': 75.7873, 'type': 'shelter', 'cap': 500},
      {'label': 'Ajmeri Gate Safe Zone', 'lat': 26.9189, 'lon': 75.8188, 'type': 'shelter', 'cap': 300},
      {'label': 'Mansarovar Relief Camp', 'lat': 26.8624, 'lon': 75.7656, 'type': 'shelter', 'cap': 600},
      {'label': 'Amanishah Water Supply point', 'lat': 26.9387, 'lon': 75.7794, 'type': 'water', 'cap': null},
      {'label': 'Jal Mahal Safe Water Tank', 'lat': 26.9535, 'lon': 75.8456, 'type': 'water', 'cap': null},
      {'label': 'Vidhyadhar Nagar Police HQ', 'lat': 26.9575, 'lon': 75.7761, 'type': 'police', 'cap': null},
      {'label': 'Malviya Nagar Station', 'lat': 26.8526, 'lon': 75.8175, 'type': 'police', 'cap': null},
      {'label': 'Vaishali Nagar Response Center', 'lat': 26.9123, 'lon': 75.7441, 'type': 'police', 'cap': null},
    ];

    for (var l in locations) {
      batch.insert('saved_locations', {
        'label': l['label'],
        'latitude': l['lat'],
        'longitude': l['lon'],
        'type': l['type'],
        'capacity': l['cap'],
        'saved_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  Database get _database {
    if (_db == null) throw StateError('DatabaseService.init() has not been called.');
    return _db!;
  }

  // ── Chat Messages ──────────────────────────────────────────────────────────

  Future<int> insertChatMessage(ChatMessage msg) async =>
      _database.insert('chat_messages', msg.toMap()..remove('id'));

  Future<List<ChatMessage>> loadChatHistory({int limit = 100}) async {
    final rows = await _database.query(
      'chat_messages',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<void> clearChatHistory() async =>
      _database.delete('chat_messages');

  // ── Checklist Items ────────────────────────────────────────────────────────

  Future<void> insertChecklistItems(List<ChecklistItem> items) async {
    final batch = _database.batch();
    for (final item in items) {
      batch.insert('checklist_items', item.toMap()..remove('id'));
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChecklistItem>> loadChecklistItems({int? sessionId}) async {
    final rows = await _database.query(
      'checklist_items',
      where: sessionId != null ? 'session_id = ?' : null,
      whereArgs: sessionId != null ? [sessionId] : null,
      orderBy: 'created_at ASC',
    );
    return rows.map(ChecklistItem.fromMap).toList();
  }

  Future<void> updateChecklistItem(ChecklistItem item) async {
    await _database.update(
      'checklist_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> clearChecklist({int? sessionId}) async {
    await _database.delete(
      'checklist_items',
      where: sessionId != null ? 'session_id = ?' : null,
      whereArgs: sessionId != null ? [sessionId] : null,
    );
  }

  /// Returns the highest existing session id (used to start a new session).
  Future<int> nextChecklistSessionId() async {
    final result = await _database.rawQuery(
        'SELECT MAX(session_id) as max_id FROM checklist_items');
    final maxId = result.first['max_id'] as int?;
    return (maxId ?? 0) + 1;
  }

  // ── Saved Locations ────────────────────────────────────────────────────────

  Future<int> insertLocation(SavedLocation loc) async =>
      _database.insert('saved_locations', loc.toMap()..remove('id'));

  Future<List<SavedLocation>> loadLocations() async {
    final rows = await _database.query(
      'saved_locations',
      orderBy: 'saved_at DESC',
    );
    return rows.map(SavedLocation.fromMap).toList();
  }

  Future<void> deleteLocation(int id) async =>
      _database.delete('saved_locations', where: 'id = ?', whereArgs: [id]);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> close() async => _db?.close();
}
