import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/article.dart';

/// Makale yerel önbellek katmanı soyutlaması (SQLite deposu ve test sahteleri için).
abstract class ArticlesCacheStore {
  Future<List<Article>> getCachedArticles();

  Future<void> replaceArticles(
    List<Article> articles, {
    ArticleSyncMetadata? metadata,
  });

  Future<void> updateSyncMetadata(ArticleSyncMetadata metadata);

  Future<ArticleSyncMetadata> getSyncMetadata();

  Future<void> clearCache();
}

/// Uzak JSON kaynağından çekilen makale listesini ve senkronizasyon üst
/// verilerini yerel SQLite veri tabanında kalıcı olarak önbellekleyen depo.
class ArticlesCacheRepository implements ArticlesCacheStore {
  ArticlesCacheRepository(this._appDatabase);

  static const String _lastSyncedAtKey = 'articles_cache_last_synced_at';
  static const String _etagKey = 'articles_cache_etag';
  static const String _remoteVersionKey = 'articles_cache_remote_version';
  static const String _sourceUrlKey = 'articles_cache_source_url';

  static const List<String> _metaKeys = <String>[
    _lastSyncedAtKey,
    _etagKey,
    _remoteVersionKey,
    _sourceUrlKey,
  ];

  final AppDatabase _appDatabase;

  Future<Database> _getReadyDatabase() async {
    final db = await _appDatabase.database;
    await _appDatabase.ensureArticlesCacheTable(db);
    await _appDatabase.ensureSettingsTable(db);
    return db;
  }

  @override
  Future<List<Article>> getCachedArticles() async {
    final db = await _getReadyDatabase();
    final rows = await db.query(
      AppDatabase.articlesCacheTable,
      orderBy: 'sort_order ASC, published_at DESC',
    );
    return rows
        .map(Article.fromDbRow)
        .where((article) => article.id.isNotEmpty && article.title.isNotEmpty)
        .toList(growable: false);
  }

  /// Yeni makale listesini tek bir atomik SQLite işlemi (transaction) içinde
  /// yazar; işlem başarısız olursa önceki önbellek bozulmaz.
  @override
  Future<void> replaceArticles(
    List<Article> articles, {
    ArticleSyncMetadata? metadata,
  }) async {
    final db = await _getReadyDatabase();
    final nowMillis = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete(AppDatabase.articlesCacheTable);
      for (var i = 0; i < articles.length; i++) {
        final article = articles[i];
        final row = article.toDbRow(cachedAtMillis: nowMillis);
        row['sort_order'] = i;
        await txn.insert(
          AppDatabase.articlesCacheTable,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (metadata != null) {
        await _writeMetadataInExecutor(txn, metadata);
      }
    });
  }

  @override
  Future<void> updateSyncMetadata(ArticleSyncMetadata metadata) async {
    final db = await _getReadyDatabase();
    await db.transaction((txn) async {
      await _writeMetadataInExecutor(txn, metadata);
    });
  }

  @override
  Future<ArticleSyncMetadata> getSyncMetadata() async {
    final db = await _getReadyDatabase();
    final placeholders = List<String>.filled(_metaKeys.length, '?').join(', ');
    final rows = await db.query(
      AppDatabase.settingsTable,
      where: '"key" IN ($placeholders)',
      whereArgs: _metaKeys,
    );

    final values = <String, String>{};
    for (final row in rows) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key != null && value != null && value.trim().isNotEmpty) {
        values[key] = value.trim();
      }
    }

    final lastSyncedMillis = int.tryParse(values[_lastSyncedAtKey] ?? '');
    return ArticleSyncMetadata(
      lastSyncedAt: lastSyncedMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncedMillis)
          : null,
      etag: values[_etagKey],
      remoteVersion: values[_remoteVersionKey],
      sourceUrl: values[_sourceUrlKey],
    );
  }

  @override
  Future<void> clearCache() async {
    final db = await _getReadyDatabase();
    final placeholders = List<String>.filled(_metaKeys.length, '?').join(', ');
    await db.transaction((txn) async {
      await txn.delete(AppDatabase.articlesCacheTable);
      await txn.delete(
        AppDatabase.settingsTable,
        where: '"key" IN ($placeholders)',
        whereArgs: _metaKeys,
      );
    });
  }

  Future<void> _writeMetadataInExecutor(
    DatabaseExecutor executor,
    ArticleSyncMetadata metadata,
  ) async {
    await _upsertSetting(
      executor,
      _lastSyncedAtKey,
      metadata.lastSyncedAt?.millisecondsSinceEpoch.toString(),
    );
    await _upsertSetting(executor, _etagKey, metadata.etag);
    await _upsertSetting(executor, _remoteVersionKey, metadata.remoteVersion);
    await _upsertSetting(executor, _sourceUrlKey, metadata.sourceUrl);
  }

  Future<void> _upsertSetting(
    DatabaseExecutor executor,
    String key,
    String? value,
  ) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await executor.delete(
        AppDatabase.settingsTable,
        where: '"key" = ?',
        whereArgs: <Object>[key],
      );
      return;
    }

    await executor.insert(
      AppDatabase.settingsTable,
      <String, Object?>{
        'key': key,
        'value': trimmed,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
