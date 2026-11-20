import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/favorite_site.dart';

/// Tarayıcı favori siteleri için yerel SQLite veri erişim katmanı.
class FavoriteSitesRepository {
  FavoriteSitesRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<Database> _getReadyDatabase() async {
    final db = await _appDatabase.database;
    await _appDatabase.ensureFavoriteSitesTable(db);
    return db;
  }

  static String normalizeUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.endsWith('/') && trimmed.length > 8) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Future<List<FavoriteSite>> getAll() async {
    final db = await _getReadyDatabase();
    final rows = await db.query(
      AppDatabase.favoriteSitesTable,
      orderBy: 'created_at DESC',
    );
    return rows.map(FavoriteSite.fromMap).toList();
  }

  Future<FavoriteSite> save({
    required String title,
    required String url,
  }) async {
    final db = await _getReadyDatabase();
    final normalizedUrl = normalizeUrl(url);
    final site = FavoriteSite(
      title: title,
      url: normalizedUrl,
      createdAt: DateTime.now(),
    );

    final id = await db.insert(
      AppDatabase.favoriteSitesTable,
      site.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return FavoriteSite(
      id: id,
      title: site.displayTitle,
      url: normalizedUrl,
      createdAt: site.createdAt,
    );
  }

  Future<void> deleteById(int id) async {
    final db = await _getReadyDatabase();
    await db.delete(
      AppDatabase.favoriteSitesTable,
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  Future<void> deleteByUrl(String url) async {
    final db = await _getReadyDatabase();
    final normalizedUrl = normalizeUrl(url);
    await db.delete(
      AppDatabase.favoriteSitesTable,
      where: 'url = ? OR url = ?',
      whereArgs: <Object>[normalizedUrl, '$normalizedUrl/'],
    );
  }
}
