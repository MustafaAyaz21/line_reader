import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/word_meaning.dart';

/// SQLite önbelleğinden okunan çeviri kaydı.
class CachedTranslation {
  const CachedTranslation({
    required this.meaning,
    required this.source,
  });

  final WordMeaning meaning;
  final String source;
}

/// Sorgulanan kelime + bağlam cümlesi sonuçlarını (4 anlamlı liste dahil)
/// yerel SQLite veri tabanında kalıcı olarak önbellekleyen depo.
class TranslationCacheRepository {
  TranslationCacheRepository(this._appDatabase);

  static const String sourceGemini = 'gemini';
  static const String sourcePrimaryFree = 'contextual_free';
  static const String sourceFallbackFree = 'dictionary_free';

  final AppDatabase _appDatabase;

  static String normalizeContext(String? sentence) {
    if (sentence == null) return '';
    return sentence.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String buildCacheKey({
    required String word,
    String? contextSentence,
  }) {
    final normalizedWord = word.trim().replaceAll('İ', 'i').toLowerCase();
    final normalizedSentence =
        normalizeContext(contextSentence).replaceAll('İ', 'i').toLowerCase();
    return '$normalizedWord|$normalizedSentence';
  }

  Future<CachedTranslation?> find({
    required String word,
    String? contextSentence,
  }) async {
    final db = await _appDatabase.database;
    await _appDatabase.ensureTranslationCacheTable(db);
    final key = buildCacheKey(word: word, contextSentence: contextSentence);

    final rows = await db.query(
      AppDatabase.translationCacheTable,
      where: 'cache_key = ?',
      whereArgs: <Object>[key],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    final rawMeaningsJson = row['meanings_json'] as String?;

    // Eski tek anlamlı önbellek kayıtları (`meanings_json` boş) yeni 4 anlamlı
    // yapıyı engellememesi için önbellek ıskası sayılır ve taze sorguyla yenilenir.
    if (rawMeaningsJson == null || rawMeaningsJson.trim().isEmpty) {
      return null;
    }

    final entries = _decodeEntries(rawMeaningsJson);
    if (entries.isEmpty) {
      return null;
    }

    final rawContext = (row['context_sentence'] as String?) ?? '';

    return CachedTranslation(
      source: (row['source'] as String?) ?? sourcePrimaryFree,
      meaning: WordMeaning.fromEntries(
        word: row['word'] as String,
        entries: entries,
        contextSentence: rawContext.isNotEmpty ? rawContext : null,
      ),
    );
  }

  Future<void> put({
    required WordMeaning meaning,
    required String source,
  }) async {
    final db = await _appDatabase.database;
    await _appDatabase.ensureTranslationCacheTable(db);
    final normalizedSentence = normalizeContext(meaning.contextSentence);
    final key = buildCacheKey(
      word: meaning.word,
      contextSentence: normalizedSentence,
    );

    final encodedEntries = jsonEncode(
      meaning.orderedEntries.map((entry) => entry.toJson()).toList(),
    );

    await db.insert(
      AppDatabase.translationCacheTable,
      <String, Object?>{
        'cache_key': key,
        'word': meaning.word,
        'context_sentence': normalizedSentence,
        'translation': meaning.translation,
        'part_of_speech': meaning.partOfSpeech?.label,
        'meanings_json': encodedEntries,
        'source': source,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clear() async {
    final db = await _appDatabase.database;
    await _appDatabase.ensureTranslationCacheTable(db);
    await db.delete(AppDatabase.translationCacheTable);
  }

  List<MeaningEntry> _decodeEntries(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List<Object?>) return const <MeaningEntry>[];
      final entries = <MeaningEntry>[];
      for (final item in decoded) {
        if (item is Map<String, Object?>) {
          final entry = MeaningEntry.fromJson(item);
          if (entry.translation.isNotEmpty) {
            entries.add(entry);
          }
        }
      }
      return entries;
    } catch (_) {
      return const <MeaningEntry>[];
    }
  }
}
