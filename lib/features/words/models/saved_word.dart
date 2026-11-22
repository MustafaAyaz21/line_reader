import 'dart:convert';

import '../../../core/settings/ipa_accent_controller.dart';
import '../../translation/models/word_lexicon_info.dart';
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
    this.ipaUs,
    this.ipaUk,
    this.synonyms = const <String>[],
    this.antonyms = const <String>[],
  });

  static const String defaultPlaceholderMeaning =
      'Bu kelime için anlam bilgisi yakında burada gösterilecek.';

  final int? id;
  final int listId;
  final String word;
  final String meaning;
  final DateTime createdAt;
  final List<MeaningEntry> meanings;
  final String? ipaUs;
  final String? ipaUk;
  final List<String> synonyms;
  final List<String> antonyms;

  bool get hasLexiconMeta =>
      (ipaUs != null && ipaUs!.trim().isNotEmpty) ||
      (ipaUk != null && ipaUk!.trim().isNotEmpty) ||
      synonyms.isNotEmpty ||
      antonyms.isNotEmpty;

  WordLexiconInfo? get lexiconInfo {
    if (!hasLexiconMeta) return null;
    return WordLexiconInfo(
      word: word,
      ipaUs: ipaUs,
      ipaUk: ipaUk,
      synonyms: synonyms,
      antonyms: antonyms,
    );
  }

  ({String ipa, IpaAccent accent})? resolveIpa(IpaAccent preferred) {
    return lexiconInfo?.resolveIpa(preferred);
  }

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
    String? encodedMeanings;
    if (hasLexiconMeta) {
      encodedMeanings = jsonEncode(<String, Object?>{
        'm': meanings.map((entry) => entry.toJson()).toList(),
        if (ipaUs != null && ipaUs!.trim().isNotEmpty) 'us': ipaUs!.trim(),
        if (ipaUk != null && ipaUk!.trim().isNotEmpty) 'uk': ipaUk!.trim(),
        if (synonyms.isNotEmpty) 'syn': synonyms,
        if (antonyms.isNotEmpty) 'ant': antonyms,
      });
    } else if (meanings.isNotEmpty) {
      encodedMeanings =
          jsonEncode(meanings.map((entry) => entry.toJson()).toList());
    }

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
    final parsed = _decodeMeaningsPayload(rawMeaningsJson);

    return SavedWord(
      id: map['id'] as int?,
      listId: map['list_id'] as int,
      word: map['word'] as String,
      meaning: map['meaning'] as String,
      meanings: parsed.meanings,
      ipaUs: parsed.ipaUs,
      ipaUk: parsed.ipaUk,
      synonyms: parsed.synonyms,
      antonyms: parsed.antonyms,
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
    String? ipaUs,
    String? ipaUk,
    List<String>? synonyms,
    List<String>? antonyms,
  }) {
    return SavedWord(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      word: word ?? this.word,
      meaning: meaning ?? this.meaning,
      createdAt: createdAt ?? this.createdAt,
      meanings: meanings ?? this.meanings,
      ipaUs: ipaUs ?? this.ipaUs,
      ipaUk: ipaUk ?? this.ipaUk,
      synonyms: synonyms ?? this.synonyms,
      antonyms: antonyms ?? this.antonyms,
    );
  }

  static ({
    List<MeaningEntry> meanings,
    String? ipaUs,
    String? ipaUk,
    List<String> synonyms,
    List<String> antonyms,
  }) _decodeMeaningsPayload(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return (
        meanings: const <MeaningEntry>[],
        ipaUs: null,
        ipaUk: null,
        synonyms: const <String>[],
        antonyms: const <String>[],
      );
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is List<Object?>) {
        return (
          meanings: _parseMeaningList(decoded),
          ipaUs: null,
          ipaUk: null,
          synonyms: const <String>[],
          antonyms: const <String>[],
        );
      }
      if (decoded is Map) {
        final rawList = decoded['m'];
        final meanings = rawList is List<Object?>
            ? _parseMeaningList(rawList)
            : const <MeaningEntry>[];
        final us = (decoded['us'] as String?)?.trim();
        final uk = (decoded['uk'] as String?)?.trim();
        final syn = _parseStringList(decoded['syn']);
        final ant = _parseStringList(decoded['ant']);
        return (
          meanings: meanings,
          ipaUs: (us != null && us.isNotEmpty) ? us : null,
          ipaUk: (uk != null && uk.isNotEmpty) ? uk : null,
          synonyms: syn,
          antonyms: ant,
        );
      }
    } catch (_) {}
    return (
      meanings: const <MeaningEntry>[],
      ipaUs: null,
      ipaUk: null,
      synonyms: const <String>[],
      antonyms: const <String>[],
    );
  }

  static List<MeaningEntry> _parseMeaningList(List<Object?> raw) {
    final list = <MeaningEntry>[];
    for (final item in raw) {
      if (item is Map) {
        final entry = MeaningEntry.fromJson(Map<String, Object?>.from(item));
        if (entry.translation.isNotEmpty) {
          list.add(entry);
        }
      }
    }
    return List<MeaningEntry>.unmodifiable(list);
  }

  static List<String> _parseStringList(Object? raw) {
    if (raw is! List) return const <String>[];
    final result = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final clean = (item?.toString() ?? '').trim().toLowerCase();
      if (clean.isNotEmpty && seen.add(clean)) {
        result.add(clean);
      }
    }
    return List<String>.unmodifiable(result);
  }

  static MeaningEntry _parseFallbackMeaning(String raw) {
    final trimmed = raw.trim();
    final match = RegExp(
      r'^(.*?)\s*\((noun|verb|adjective|adverb|phrase|idiom|preposition|conjunction)\)\s*$',
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
