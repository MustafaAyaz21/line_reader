import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../translation/models/word_meaning.dart';
import '../models/saved_word.dart';
import '../models/word_list.dart';

/// Özel kelime listeleri ve listelere bağlı kelimeler için SQLite veri erişim katmanı.
class WordRepository {
  WordRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<Database> _getReadyDatabase() async {
    final db = await _appDatabase.database;
    await _appDatabase.ensureWordListsAndWordsSchema(db);
    return db;
  }

  /// Tüm kelime listelerini kelime sayılarıyla birlikte döner.
  /// Varsayılan "Favoriler" listesi her zaman ilk sırada gelir.
  Future<List<WordList>> getAllLists() async {
    final db = await _getReadyDatabase();
    final rows = await db.rawQuery('''
      SELECT
        l.id,
        l.name,
        l.color_value,
        l.is_default,
        l.created_at,
        COUNT(w.id) AS word_count
      FROM ${AppDatabase.wordListsTable} l
      LEFT JOIN ${AppDatabase.wordsTable} w ON w.list_id = l.id
      GROUP BY l.id
      ORDER BY l.is_default DESC, l.created_at ASC
    ''');

    return rows.map(WordList.fromMap).toList();
  }

  Future<int> getDefaultFavoritesListId() async {
    final db = await _appDatabase.database;
    return _appDatabase.ensureWordListsAndWordsSchema(db);
  }

  Future<WordList> createList({
    required String name,
    required int colorValue,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Liste adı boş olamaz.');
    }

    final db = await _getReadyDatabase();
    final duplicate = await db.query(
      AppDatabase.wordListsTable,
      where: 'LOWER(name) = ?',
      whereArgs: <Object>[trimmed.toLowerCase()],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw const FormatException('Bu isimde bir kelime listesi zaten var.');
    }

    final now = DateTime.now();
    final id = await db.insert(
      AppDatabase.wordListsTable,
      <String, Object?>{
        'name': trimmed,
        'color_value': colorValue,
        'is_default': 0,
        'created_at': now.millisecondsSinceEpoch,
      },
    );

    return WordList(
      id: id,
      name: trimmed,
      colorValue: colorValue,
      isDefault: false,
      createdAt: now,
      wordCount: 0,
    );
  }

  Future<void> updateList({
    required int id,
    required String name,
    required int colorValue,
    required bool isDefault,
  }) async {
    final db = await _getReadyDatabase();

    if (isDefault) {
      // Varsayılan "Favoriler" listesinin adı korunur, rengi özelleştirilebilir.
      await db.update(
        AppDatabase.wordListsTable,
        <String, Object?>{'color_value': colorValue},
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      return;
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Liste adı boş olamaz.');
    }

    final duplicate = await db.query(
      AppDatabase.wordListsTable,
      where: 'LOWER(name) = ? AND id != ?',
      whereArgs: <Object>[trimmed.toLowerCase(), id],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw const FormatException('Bu isimde başka bir liste zaten var.');
    }

    await db.update(
      AppDatabase.wordListsTable,
      <String, Object?>{
        'name': trimmed,
        'color_value': colorValue,
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  /// Özel bir kelime listesini ve içindeki kelimeleri siler.
  /// Varsayılan "Favoriler" listesi silinmeye karşı korunur.
  Future<void> deleteList(int id) async {
    final db = await _getReadyDatabase();
    await db.transaction((txn) async {
      final rows = await txn.query(
        AppDatabase.wordListsTable,
        where: 'id = ?',
        whereArgs: <Object>[id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      if ((rows.first['is_default'] as int? ?? 0) == 1) {
        return;
      }

      await txn.delete(
        AppDatabase.wordsTable,
        where: 'list_id = ?',
        whereArgs: <Object>[id],
      );
      await txn.delete(
        AppDatabase.wordListsTable,
        where: 'id = ? AND is_default = 0',
        whereArgs: <Object>[id],
      );
    });
  }

  Future<List<SavedWord>> getWordsByList(int listId) async {
    final db = await _getReadyDatabase();
    final rows = await db.query(
      AppDatabase.wordsTable,
      where: 'list_id = ?',
      whereArgs: <Object>[listId],
      orderBy: 'created_at DESC',
    );
    return rows.map(SavedWord.fromMap).toList();
  }

  Future<SaveWordStatus> saveWord({
    required int listId,
    required String word,
    required String meaning,
    List<MeaningEntry> meanings = const <MeaningEntry>[],
  }) async {
    final db = await _getReadyDatabase();
    final trimmedWord = word.trim();
    if (trimmedWord.isEmpty) {
      return SaveWordStatus.error;
    }

    // Seçilen liste ID'si gerçekten mevcut değilse varsayılan "Favoriler" listesini kullan.
    var resolvedListId = listId;
    final listCheck = await db.query(
      AppDatabase.wordListsTable,
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object>[resolvedListId],
      limit: 1,
    );
    if (listCheck.isEmpty) {
      resolvedListId = await _appDatabase.ensureWordListsAndWordsSchema(db);
    }

    // Aynı listede aynı kelime zaten varsa açıkça tespit et.
    final existing = await db.query(
      AppDatabase.wordsTable,
      columns: const <String>['id'],
      where: 'list_id = ? AND LOWER(word) = ?',
      whereArgs: <Object>[
        resolvedListId,
        trimmedWord.replaceAll('İ', 'i').toLowerCase(),
      ],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return SaveWordStatus.alreadyExists;
    }

    final newWord = SavedWord(
      listId: resolvedListId,
      word: trimmedWord,
      meaning: meaning,
      meanings: meanings,
      createdAt: DateTime.now(),
    );

    final insertedId = await db.insert(
      AppDatabase.wordsTable,
      newWord.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (insertedId <= 0) {
      return SaveWordStatus.alreadyExists;
    }

    debugPrint(
      '[WordRepository] Kelime kaydedildi: "$trimmedWord" -> '
      'listId=$resolvedListId (rowId=$insertedId)',
    );
    return SaveWordStatus.saved;
  }

  Future<void> deleteWord(int id) async {
    final db = await _getReadyDatabase();
    await db.delete(
      AppDatabase.wordsTable,
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }
}
