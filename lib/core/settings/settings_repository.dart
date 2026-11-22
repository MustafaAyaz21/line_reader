import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// Uygulama ayarlarını (isteğe bağlı Gemini API anahtarı vb.) SQLite içinde saklar.
class SettingsRepository {
  SettingsRepository(this._appDatabase);

  static const String _geminiApiKeyName = 'gemini_api_key';

  final AppDatabase _appDatabase;

  Future<Database> _getReadyDatabase() async {
    final db = await _appDatabase.database;
    await _appDatabase.ensureSettingsTable(db);
    return db;
  }

  Future<String?> getString(String key) async {
    final db = await _getReadyDatabase();
    final rows = await db.query(
      AppDatabase.settingsTable,
      where: '"key" = ?',
      whereArgs: <Object>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = (rows.first['value'] as String?)?.trim();
    return (value != null && value.isNotEmpty) ? value : null;
  }

  Future<void> saveString(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await deleteKey(key);
      return;
    }

    final db = await _getReadyDatabase();
    await db.insert(
      AppDatabase.settingsTable,
      <String, Object?>{
        'key': key,
        'value': trimmed,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteKey(String key) async {
    final db = await _getReadyDatabase();
    await db.delete(
      AppDatabase.settingsTable,
      where: '"key" = ?',
      whereArgs: <Object>[key],
    );
  }

  Future<String?> getGeminiApiKey() => getString(_geminiApiKeyName);

  Future<void> saveGeminiApiKey(String apiKey) =>
      saveString(_geminiApiKeyName, apiKey);

  Future<void> deleteGeminiApiKey() => deleteKey(_geminiApiKeyName);
}
