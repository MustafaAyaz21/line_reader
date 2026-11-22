import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/article_reader_models.dart';

/// Okuma ekranı tercihlerini ve makale bazlı altını çizme kayıtlarını
/// kalıcı olarak saklayan soyut depo.
abstract class ArticleReaderStore {
  Future<ArticleReaderPreferences> loadPreferences();

  Future<void> savePreferences(ArticleReaderPreferences preferences);

  Future<List<ArticleUnderline>> getUnderlinesForArticle(String articleId);

  Future<void> saveUnderlinesForArticle(
    String articleId,
    List<ArticleUnderline> underlines,
  );
}

/// Okuma ekranı arka plan tonu, font boyutu ve makale bazlı alt çizgi
/// kayıtlarını yerel SQLite veri tabanında saklayan depo.
class ArticleReaderRepository implements ArticleReaderStore {
  ArticleReaderRepository(this._appDatabase);

  static const String _toneSettingKey = 'article_reader_tone';
  static const String _fontSizeSettingKey = 'article_reader_font_size';

  final AppDatabase _appDatabase;

  Future<Database> _getReadyDatabase() async {
    final db = await _appDatabase.database;
    await _appDatabase.ensureSettingsTable(db);
    await _appDatabase.ensureArticleUnderlinesTable(db);
    return db;
  }

  @override
  Future<ArticleReaderPreferences> loadPreferences() async {
    final db = await _getReadyDatabase();
    final rows = await db.query(
      AppDatabase.settingsTable,
      where: '"key" IN (?, ?)',
      whereArgs: const <Object>[_toneSettingKey, _fontSizeSettingKey],
    );

    String? rawTone;
    String? rawFontSize;
    for (final row in rows) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key == _toneSettingKey) {
        rawTone = value;
      } else if (key == _fontSizeSettingKey) {
        rawFontSize = value;
      }
    }

    final tone = ArticleReaderTone.fromStorageKey(rawTone);
    final parsedSize = double.tryParse((rawFontSize ?? '').trim());
    final fontSize = parsedSize != null
        ? parsedSize
            .clamp(
              ArticleReaderPreferences.minFontSize,
              ArticleReaderPreferences.maxFontSize,
            )
            .toDouble()
        : ArticleReaderPreferences.defaultFontSize;

    return ArticleReaderPreferences(tone: tone, fontSize: fontSize);
  }

  @override
  Future<void> savePreferences(ArticleReaderPreferences preferences) async {
    final db = await _getReadyDatabase();
    final clampedSize = preferences.fontSize
        .clamp(
          ArticleReaderPreferences.minFontSize,
          ArticleReaderPreferences.maxFontSize,
        )
        .toDouble();

    await db.transaction((txn) async {
      await txn.insert(
        AppDatabase.settingsTable,
        <String, Object?>{
          'key': _toneSettingKey,
          'value': preferences.tone.storageKey,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        AppDatabase.settingsTable,
        <String, Object?>{
          'key': _fontSizeSettingKey,
          'value': clampedSize.toStringAsFixed(1),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<List<ArticleUnderline>> getUnderlinesForArticle(
    String articleId,
  ) async {
    final trimmedId = articleId.trim();
    if (trimmedId.isEmpty) return const <ArticleUnderline>[];

    final db = await _getReadyDatabase();
    final rows = await db.query(
      AppDatabase.articleUnderlinesTable,
      where: 'article_id = ?',
      whereArgs: <Object>[trimmedId],
      orderBy: 'paragraph_index ASC, start_offset ASC',
    );

    return rows
        .map(ArticleUnderline.fromDbRow)
        .where((item) => item.endOffset > item.startOffset)
        .toList(growable: false);
  }

  @override
  Future<void> saveUnderlinesForArticle(
    String articleId,
    List<ArticleUnderline> underlines,
  ) async {
    final trimmedId = articleId.trim();
    if (trimmedId.isEmpty) return;

    final db = await _getReadyDatabase();
    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.articleUnderlinesTable,
        where: 'article_id = ?',
        whereArgs: <Object>[trimmedId],
      );

      for (final item in underlines) {
        if (item.endOffset <= item.startOffset) continue;
        await txn.insert(
          AppDatabase.articleUnderlinesTable,
          ArticleUnderline(
            articleId: trimmedId,
            paragraphIndex: item.paragraphIndex,
            startOffset: item.startOffset,
            endOffset: item.endOffset,
            createdAt: item.createdAt ?? DateTime.now(),
          ).toDbRow(),
        );
      }
    });
  }
}
