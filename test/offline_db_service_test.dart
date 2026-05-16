import 'package:flutter_test/flutter_test.dart';
import 'package:resq/services/offline_db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Database db;
  late OfflineDbService offlineDb;

  setUpAll(() {
    // Initialize FFI for running sqflite in Dart test environment
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Start with empty preferences
    SharedPreferences.setMockInitialValues({});
    
    // Create an in-memory database for testing
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    
    // Create the schema manually since DatabaseService isn't being used here
    await db.execute('''
      CREATE TABLE qa_pairs (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        keywords  TEXT    NOT NULL,
        answer_en TEXT    NOT NULL,
        answer_hi TEXT    NOT NULL,
        topic     TEXT    NOT NULL
      )
    ''');

    offlineDb = OfflineDbService();
    await offlineDb.init(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Seeds exactly 30 Q&A pairs on first launch', () async {
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM qa_pairs'));
    expect(count, 30);
    
    // Check that calling init again doesn't double-seed
    await offlineDb.init(db);
    final countAfter = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM qa_pairs'));
    expect(countAfter, 30);
  });

  test('Fuzzy search finds CPR instructions using English keyword', () async {
    final result = await offlineDb.fuzzySearch('how to do cpr compressions');
    expect(result, isNotNull);
    expect(result!.topic, 'CPR');
    expect(result.answerEn.toLowerCase(), contains('compressions'));
  });

  test('Fuzzy search returns null for unrelated queries', () async {
    final result = await offlineDb.fuzzySearch('how to bake a cake xyzzy');
    expect(result, isNull);
  });

  test('Fuzzy search finds Flood instructions using Hindi keyword', () async {
    final result = await offlineDb.fuzzySearch('बाढ़ में क्या करें');
    expect(result, isNotNull);
    expect(result!.topic, 'Flood');
    expect(result.answerHi, contains('बाढ़'));
  });
}
