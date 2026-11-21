import 'dart:convert';

import '../../translation/models/word_meaning.dart';

/// Kelime kaydetme işleminin sonucunu temsil eder.
enum SaveWordStatus {
  saved,
  alreadyExists,
  error,
}

/// Yerel veri tabanında belirli bir kelime listesine bağlı saklanan kelime modeli.
class SavedWord {
  const SavedWord({
    this.id,
    required this.listId,
    required this.word,
    required this.meaning,
    required this.createdAt,
    this.meanings = const <MeaningEntry>[],
  });

  static const String defaultPlaceholderMeaning =
      'Bu kelime için anlam bilgisi yakında burada gösterilecek.';

  final int? id;
  final int listId;
  final String word;
  final String meaning;
  final DateTime createdAt;
  final List<MeaningEntry> meanings;

  /// Kayıtlı tüm anlamları (en fazla 4) sıralı şekilde döner.
  /// Eski tek anlamlı kayıtlar için `meaning` alanından tek madde üretir.
  List<MeaningEntry> get allMeanings {
    if (meanings.isNotEmpty) return meanings;
    return <MeaningEntry>[_parseFallbackMeaning(meaning)];
  }

  /// Liste görünümünde tüm anlamların yan yana sıralanmış hali:
  /// örn. `insan (adjective) • beşeri (adjective) • insani (adjective) • insanoğlu (noun)`.
  String get inlineMeaningsText {
    if (meanings.isEmpty) return meaning;
    return meanings.map((entry) => entry.baseFormatted).join(' • ');
  }

  Map<String, Object?> toMap() {
    final encodedMeanings = meanings.isNotEmpty
        ? jsonEncode(meanings.map((entry) => entry.toJson()).toList())
        : null;

    return <String, Object?>{
      if (id != null) 'id': id,
      'list_id': listId,
      'word': word,
      'meaning': meanings.isNotEmpty ? inlineMeaningsText : meaning,
      'meanings_json': encodedMeanings,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory SavedWord.fromMap(Map<String, Object?> map) {
    final rawMeaningsJson = map['meanings_json'] as String?;
    final parsedMeanings = _decodeMeanings(rawMeaningsJson);

    return SavedWord(
      id: map['id'] as int?,
      listId: map['list_id'] as int,
      word: map['word'] as String,
      meaning: map['meaning'] as String,
      meanings: parsedMeanings,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
      ),
    );
  }

  SavedWord copyWith({
    int? id,
    int? listId,
    String? word,
    String? meaning,
    DateTime? createdAt,
    List<MeaningEntry>? meanings,
  }) {
    return SavedWord(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      word: word ?? this.word,
      meaning: meaning ?? this.meaning,
      createdAt: createdAt ?? this.createdAt,
      meanings: meanings ?? this.meanings,
    );
  }

  static List<MeaningEntry> _decodeMeanings(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return const <MeaningEntry>[];
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List<Object?>) return const <MeaningEntry>[];
      final list = <MeaningEntry>[];
      for (final item in decoded) {
        if (item is Map<String, Object?>) {
          final entry = MeaningEntry.fromJson(item);
          if (entry.translation.isNotEmpty) {
            list.add(entry);
          }
        }
      }
      return List<MeaningEntry>.unmodifiable(list);
    } catch (_) {
      return const <MeaningEntry>[];
    }
  }

  static MeaningEntry _parseFallbackMeaning(String raw) {
    final trimmed = raw.trim();
    final match = RegExp(
      r'^(.*?)\s*\((noun|verb|adjective|adverb)\)\s*$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (match != null) {
      return MeaningEntry(
        translation: match.group(1)!.trim(),
        partOfSpeech: WordPartOfSpeech.tryParse(match.group(2)),
        isContextual: true,
      );
    }

    return MeaningEntry(
      translation: trimmed,
      isContextual: true,
    );
  }
}
