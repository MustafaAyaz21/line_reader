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

  Future<String?> getGeminiApiKey() async {
    final db = await _getReadyDatabase();
    final rows = await db.query(
      AppDatabase.settingsTable,
      where: '"key" = ?',
      whereArgs: <Object>[_geminiApiKeyName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = (rows.first['value'] as String?)?.trim();
    return (value != null && value.isNotEmpty) ? value : null;
  }

  Future<void> saveGeminiApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await deleteGeminiApiKey();
      return;
    }

    final db = await _getReadyDatabase();
    await db.insert(
      AppDatabase.settingsTable,
      <String, Object?>{
        'key': _geminiApiKeyName,
        'value': trimmed,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteGeminiApiKey() async {
    final db = await _getReadyDatabase();
    await db.delete(
      AppDatabase.settingsTable,
      where: '"key" = ?',
      whereArgs: <Object>[_geminiApiKeyName],
    );
  }
}
