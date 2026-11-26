import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../models/saved_word.dart';

/// Kelime kartlarında hangi bilgilerin gösterileceğini tutan kullanıcı tercihleri.
class FlashcardDisplayPrefs {
  const FlashcardDisplayPrefs({
    this.showIpa = true,
    this.showSynonyms = true,
    this.showAntonyms = true,
    this.showExamples = true,
  });

  final bool showIpa;
  final bool showSynonyms;
  final bool showAntonyms;
  final bool showExamples;

  FlashcardDisplayPrefs copyWith({
    bool? showIpa,
    bool? showSynonyms,
    bool? showAntonyms,
    bool? showExamples,
  }) {
    return FlashcardDisplayPrefs(
      showIpa: showIpa ?? this.showIpa,
      showSynonyms: showSynonyms ?? this.showSynonyms,
      showAntonyms: showAntonyms ?? this.showAntonyms,
      showExamples: showExamples ?? this.showExamples,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'showIpa': showIpa,
        'showSynonyms': showSynonyms,
        'showAntonyms': showAntonyms,
        'showExamples': showExamples,
      };

  factory FlashcardDisplayPrefs.fromJson(Map<String, Object?> json) {
    return FlashcardDisplayPrefs(
      showIpa: json['showIpa'] != false,
      showSynonyms: json['showSynonyms'] != false,
      showAntonyms: json['showAntonyms'] != false,
      showExamples: json['showExamples'] != false,
    );
  }
}

/// Kelimelerin öğrenilme durumunu ("Öğrendiklerim" / "Henüz Öğrenmediklerim")
/// ve kart görünüm tercihlerini SQLite `app_settings` tablosunda saklar.
class WordLearningProgressService {
  WordLearningProgressService._();

  static final WordLearningProgressService instance =
      WordLearningProgressService._();

  static const String _learnedWordsKey = 'learning_learned_words_v1';
  static const String _displayPrefsKey = 'learning_flashcard_prefs_v1';

  static String normalizeWordKey(SavedWord word) {
    return word.word.trim().replaceAll('İ', 'i').toLowerCase();
  }

  Future<Set<String>> getLearnedWordKeys() async {
    try {
      final db = await AppDatabase.instance.database;
      await AppDatabase.instance.ensureSettingsTable(db);
      final rows = await db.query(
        AppDatabase.settingsTable,
        columns: const <String>['value'],
        where: '"key" = ?',
        whereArgs: <Object>[_learnedWordsKey],
        limit: 1,
      );
      if (rows.isEmpty) return <String>{};
      final raw = rows.first['value'] as String?;
      if (raw == null || raw.trim().isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  Future<void> _saveLearnedWordKeys(Set<String> keys) async {
    try {
      final db = await AppDatabase.instance.database;
      await AppDatabase.instance.ensureSettingsTable(db);
      await db.insert(
        AppDatabase.settingsTable,
        <String, Object?>{
          'key': _learnedWordsKey,
          'value': jsonEncode(keys.toList()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> markWordLearned(SavedWord word) async {
    final key = normalizeWordKey(word);
    if (key.isEmpty) return;
    final current = await getLearnedWordKeys();
    if (current.add(key)) {
      await _saveLearnedWordKeys(current);
    }
  }

  Future<void> markWordUnlearned(SavedWord word) async {
    final key = normalizeWordKey(word);
    if (key.isEmpty) return;
    final current = await getLearnedWordKeys();
    if (current.remove(key)) {
      await _saveLearnedWordKeys(current);
    }
  }

  bool isWordLearned(SavedWord word, Set<String> learnedKeys) {
    return learnedKeys.contains(normalizeWordKey(word));
  }

  Future<FlashcardDisplayPrefs> getDisplayPrefs() async {
    try {
      final db = await AppDatabase.instance.database;
      await AppDatabase.instance.ensureSettingsTable(db);
      final rows = await db.query(
        AppDatabase.settingsTable,
        columns: const <String>['value'],
        where: '"key" = ?',
        whereArgs: <Object>[_displayPrefsKey],
        limit: 1,
      );
      if (rows.isEmpty) return const FlashcardDisplayPrefs();
      final raw = rows.first['value'] as String?;
      if (raw == null || raw.trim().isEmpty) {
        return const FlashcardDisplayPrefs();
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return FlashcardDisplayPrefs.fromJson(
          Map<String, Object?>.from(decoded),
        );
      }
    } catch (_) {}
    return const FlashcardDisplayPrefs();
  }

  Future<void> saveDisplayPrefs(FlashcardDisplayPrefs prefs) async {
    try {
      final db = await AppDatabase.instance.database;
      await AppDatabase.instance.ensureSettingsTable(db);
      await db.insert(
        AppDatabase.settingsTable,
        <String, Object?>{
          'key': _displayPrefsKey,
          'value': jsonEncode(prefs.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }
}
