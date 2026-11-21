/// Kelimenin sözcük türü.
enum WordPartOfSpeech {
  noun('noun'),
  verb('verb'),
  adjective('adjective'),
  adverb('adverb'),
  phrase('phrase'),
  idiom('idiom'),
  preposition('preposition'),
  conjunction('conjunction');

  const WordPartOfSpeech(this.label);

  final String label;

  static WordPartOfSpeech? tryParse(String? rawValue) {
    if (rawValue == null) return null;
    final normalized = rawValue.trim().toLowerCase();
    return switch (normalized) {
      'noun' || 'n' || 'isim' => WordPartOfSpeech.noun,
      'verb' || 'v' || 'fiil' => WordPartOfSpeech.verb,
      'adjective' || 'adj' || 'sıfat' => WordPartOfSpeech.adjective,
      'adverb' || 'adv' || 'zarf' => WordPartOfSpeech.adverb,
      'phrase' || 'kalıp' || 'kalip' || 'ifade' => WordPartOfSpeech.phrase,
      'idiom' || 'deyim' => WordPartOfSpeech.idiom,
      'preposition' || 'prep' || 'edat' => WordPartOfSpeech.preposition,
      'conjunction' || 'conj' || 'bağlaç' || 'baglac' =>
        WordPartOfSpeech.conjunction,
      _ => null,
    };
  }
}

/// Tek bir anlam satırını temsil eder (anlam + sözcük türü + bağlam etiketi).
class MeaningEntry {
  const MeaningEntry({
    required this.translation,
    this.partOfSpeech,
    this.isContextual = false,
  });

  static const String contextualTag = '(cümledeki anlam)';

  final String translation;
  final WordPartOfSpeech? partOfSpeech;
  final bool isContextual;

  /// Standart kayıt biçimi: örn. `zor (adjective)` veya `çalmak (verb)`.
  String get baseFormatted {
    final pos = partOfSpeech;
    if (pos == null) return translation;
    return '$translation (${pos.label})';
  }

  /// Panel görünüm biçimi: 1. anlamda sonuna `(cümledeki anlam)` ekler.
  String get displayText {
    if (isContextual) {
      return '$baseFormatted $contextualTag';
    }
    return baseFormatted;
  }

  MeaningEntry copyWith({
    String? translation,
    WordPartOfSpeech? partOfSpeech,
    bool? isContextual,
  }) {
    return MeaningEntry(
      translation: translation ?? this.translation,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      isContextual: isContextual ?? this.isContextual,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'translation': translation,
      'partOfSpeech': partOfSpeech?.label,
      'isContextual': isContextual,
    };
  }

  factory MeaningEntry.fromJson(Map<String, Object?> json) {
    return MeaningEntry(
      translation: (json['translation'] as String? ?? '').trim(),
      partOfSpeech: WordPartOfSpeech.tryParse(json['partOfSpeech'] as String?),
      isContextual: json['isContextual'] == true,
    );
  }
}

/// Bağlam cümlesine göre çözümlenmiş birincil anlam ve en sık kullanılan
/// diğer anlamları (en fazla 4 madde) taşıyan model.
class WordMeaning {
  const WordMeaning({
    required this.word,
    required this.translation,
    this.partOfSpeech,
    this.contextSentence,
    this.entries = const <MeaningEntry>[],
  });

  static const int maxEntries = 4;

  final String word;
  final String translation;
  final WordPartOfSpeech? partOfSpeech;
  final String? contextSentence;
  final List<MeaningEntry> entries;

  /// En fazla 4 tekrarsız anlamdan oluşan `WordMeaning` üretir.
  /// İlk anlam her zaman `isContextual: true` olarak işaretlenir.
  factory WordMeaning.fromEntries({
    required String word,
    required List<MeaningEntry> entries,
    String? contextSentence,
  }) {
    final seenTranslations = <String>{};
    final deduplicated = <MeaningEntry>[];

    for (final entry in entries) {
      final clean = entry.translation.trim();
      if (clean.isEmpty) continue;

      final key = clean.replaceAll('İ', 'i').toLowerCase();
      if (!seenTranslations.add(key)) continue;

      deduplicated.add(
        entry.copyWith(
          translation: clean,
          isContextual: deduplicated.isEmpty,
        ),
      );

      if (deduplicated.length >= maxEntries) {
        break;
      }
    }

    if (deduplicated.isEmpty) {
      throw const FormatException('En az bir geçerli anlam gereklidir.');
    }

    final primary = deduplicated.first;
    return WordMeaning(
      word: word,
      translation: primary.translation,
      partOfSpeech: primary.partOfSpeech,
      contextSentence: contextSentence,
      entries: List<MeaningEntry>.unmodifiable(deduplicated),
    );
  }

  /// Panelde listelenecek sıralı anlamlar (1. anlam cümledeki anlamdır).
  List<MeaningEntry> get orderedEntries {
    if (entries.isNotEmpty) return entries;
    return <MeaningEntry>[
      MeaningEntry(
        translation: translation,
        partOfSpeech: partOfSpeech,
        isContextual: true,
      ),
    ];
  }

  /// Kelimelerim listesine kaydedilecek standart birincil anlam biçimi:
  /// örn. `zor (adjective)` veya `çalmak (verb)`.
  String get formattedMeaning {
    final pos = partOfSpeech;
    if (pos == null) return translation;
    return '$translation (${pos.label})';
  }
}
