import 'dart:convert';

import '../../translation/utils/english_morphology_resolver.dart';
import '../utils/article_text_parser.dart';
import 'article_level.dart';

/// Podcast (AI) sesli okuma dosyası içindeki tek bir cümlenin milisaniye
/// cinsinden başlangıç ve bitiş zaman aralığı.
class ArticleAudioSegment {
  const ArticleAudioSegment({
    required this.paragraphIndex,
    required this.sentenceIndex,
    required this.startMs,
    required this.endMs,
  });

  final int paragraphIndex;
  final int sentenceIndex;
  final int startMs;
  final int endMs;

  static ArticleAudioSegment? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final p = _parseInt(map['p'] ?? map['paragraph'] ?? map['paragraph_index']);
    final s = _parseInt(map['s'] ?? map['sentence'] ?? map['sentence_index']);
    final start = _parseInt(map['start_ms'] ?? map['startMs']);
    final end = _parseInt(map['end_ms'] ?? map['endMs']);
    if (start < 0 || end <= start) return null;
    return ArticleAudioSegment(
      paragraphIndex: p < 0 ? 0 : p,
      sentenceIndex: s < 0 ? 0 : s,
      startMs: start,
      endMs: end,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'p': paragraphIndex,
        's': sentenceIndex,
        'start_ms': startMs,
        'end_ms': endMs,
      };

  static int _parseInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw.trim()) ?? -1;
    return -1;
  }
}

/// Uzak `articles.json` kaynağından çekilen ve yerel SQLite önbelleğinde
/// saklanan makale veri modeli.
class Article {
  const Article({
    required this.id,
    required this.title,
    this.summary = '',
    this.content = '',
    this.category = '',
    this.level = '',
    this.language = 'en',
    this.author = '',
    this.imageUrl,
    this.sourceUrl,
    this.audioUrl,
    this.audioSegments = const <ArticleAudioSegment>[],
    this.readingTimeMinutes = 0,
    this.readingTimeLabel = '',
    this.tags = const <String>[],
    this.wordMeanings = const <String, String>{},
    this.sentenceTranslations = const <String, String>{},
    this.paragraphTranslations = const <String>[],
    this.isHidden = false,
    this.publishAt,
    this.publishedAt,
    this.updatedAt,
    this.sortOrder = 0,
    this.rawJson = '{}',
  });

  final String id;
  final String title;
  final String summary;
  final String content;
  final String category;
  final String level;
  final String language;
  final String author;
  final String? imageUrl;
  final String? sourceUrl;

  /// Stüdyo / Podcast AI sesli okuma dosyasının uzak adresi (`.m4a` / `.mp3`).
  /// Boşsa uygulama cihazın yerleşik TTS motoruyla cümle cümle okur.
  final String? audioUrl;

  /// Podcast ses dosyasındaki cümle-zaman eşleşmeleri (geriye/ileriye cümle
  /// atlama ve canlı cümle vurgulama için).
  final List<ArticleAudioSegment> audioSegments;

  bool get hasPodcastAudio =>
      audioUrl != null && audioUrl!.trim().isNotEmpty;
  final int readingTimeMinutes;
  final String readingTimeLabel;
  final List<String> tags;

  /// Makale içinde yazar/editör tarafından tanımlanmış bağlamsal kelime
  /// anlamları (`word_meanings` haritası; küçük harfe normalleştirilmiş anahtar).
  final Map<String, String> wordMeanings;

  /// Makale verisinde hazır tutulan cümle çevirileri (`sentence_translations`).
  /// Anahtarlar normalize edilmiş İngilizce cümle, değerler Türkçe çeviridir.
  final Map<String, String> sentenceTranslations;

  /// Makale verisinde hazır tutulan paragraf çevirileri (`paragraph_translations`).
  /// Paragraf sırasıyla birebir eşleşir.
  final List<String> paragraphTranslations;

  /// Yönetici tarafından gizlenmiş makale (`is_hidden: true`).
  /// Uygulamada son kullanıcıya hiçbir ekranda gösterilmez.
  final bool isHidden;

  /// Planlı yayın tarih/saati (`publish_at`). Gelecekteyse zamanı gelene kadar
  /// kullanıcıya görünmez; zamanı gelince bilgisayar kapalı olsa bile otomatik açılır.
  final DateTime? publishAt;

  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final int sortOrder;

  /// Gelecekte JSON kaynağına eklenecek ek alanların önbellekte kaybolmaması
  /// için ham JSON kaydı saklanır.
  final String rawJson;

  /// Makalenin verilen UTC zamanında son kullanıcıya görünür olup olmadığını döner.
  bool isVisibleAt(DateTime nowUtc) {
    if (isHidden) return false;
    final scheduled = publishAt;
    if (scheduled != null && scheduled.toUtc().isAfter(nowUtc.toUtc())) {
      return false;
    }
    return true;
  }

  /// Açık makalenin `word_meanings` haritasında önce kelimenin kendisini,
  /// bulunamazsa `EnglishMorphologyResolver` kök/temel form adaylarını arar.
  ({String matchedKey, String meaning})? findWordMeaning(String rawWord) {
    if (wordMeanings.isEmpty) return null;
    final candidates = EnglishMorphologyResolver.resolveCandidates(rawWord);
    for (final candidate in candidates) {
      final value = wordMeanings[candidate];
      if (value != null && value.trim().isNotEmpty) {
        return (matchedKey: candidate, meaning: value.trim());
      }
    }
    return null;
  }

  /// Verilen paragraf indeksi için makalede tanımlı hazır Türkçe çeviriyi döndürür.
  String? findParagraphTranslation(int paragraphIndex) {
    if (paragraphIndex < 0 || paragraphIndex >= paragraphTranslations.length) {
      return null;
    }
    final value = paragraphTranslations[paragraphIndex].trim();
    return value.isEmpty ? null : value;
  }

  /// Verilen İngilizce cümle için makalede tanımlı hazır Türkçe çeviriyi döndürür.
  String? findSentenceTranslation(String rawSentence) {
    if (sentenceTranslations.isEmpty) return null;
    final key = normalizeTranslationKey(rawSentence);
    if (key.isEmpty) return null;

    final exact = sentenceTranslations[key];
    if (exact != null && exact.trim().isNotEmpty) {
      return exact.trim();
    }

    final strippedKey = _stripEdgePunctuation(key);
    if (strippedKey.isEmpty) return null;
    for (final entry in sentenceTranslations.entries) {
      if (_stripEdgePunctuation(entry.key) == strippedKey &&
          entry.value.trim().isNotEmpty) {
        return entry.value.trim();
      }
    }
    return null;
  }

  /// Seçili cümle, çoklu cümle veya tam paragraf için makale verisindeki hazır
  /// Türkçe çeviriyi arar (`paragraph_translations` ve `sentence_translations`).
  String? findPreparedTranslation({
    required String selectedText,
    int? paragraphIndex,
    String? fullParagraphText,
  }) {
    final normalizedSelected = normalizeTranslationKey(selectedText);
    if (normalizedSelected.isEmpty) return null;

    // 1) Seçim ilgili paragrafın tamamını (veya neredeyse tamamını) kapsıyorsa
    //    doğrudan hazır paragraf çevirisini döndür.
    if (paragraphIndex != null) {
      final presetParagraph = findParagraphTranslation(paragraphIndex);
      if (presetParagraph != null && fullParagraphText != null) {
        final normPara = normalizeTranslationKey(fullParagraphText);
        if (normPara.isNotEmpty &&
            (normalizedSelected == normPara ||
                _stripEdgePunctuation(normalizedSelected) ==
                    _stripEdgePunctuation(normPara) ||
                normalizedSelected.length >= (normPara.length * 0.92).round())) {
          return presetParagraph;
        }
      }
    }

    // 2) Tek bir cümle (veya doğrudan tanımlı parça) olarak eşleşiyorsa döndür.
    final directSentence = findSentenceTranslation(selectedText);
    if (directSentence != null) {
      return directSentence;
    }

    // 3) Birden fazla cümle seçildiyse ve hepsi sentence_translations içinde
    //    hazırsa sırayla birleştirerek döndür.
    if (sentenceTranslations.isNotEmpty) {
      final split = ArticleTextParser.splitParagraphSentences(
        <String>[selectedText],
      );
      if (split.length > 1) {
        final translatedParts = <String>[];
        for (final span in split) {
          final partTr = findSentenceTranslation(span.text);
          if (partTr == null) {
            translatedParts.clear();
            break;
          }
          translatedParts.add(partTr);
        }
        if (translatedParts.isNotEmpty) {
          return translatedParts.join(' ');
        }
      }
    }

    return null;
  }

  static String normalizeTranslationKey(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll('İ', 'i')
        .toLowerCase();
  }

  static String _stripEdgePunctuation(String input) {
    return input
        .replaceAll(RegExp(r'^[\s\p{P}]+|[\s\p{P}]+$', unicode: true), '')
        .trim();
  }

  /// Kısa makale açıklaması (`description` / `summary` alanı).
  String get description => summary;

  /// CEFR seviye kodu (A1–C2) eşleşmesi.
  ArticleLevel? get parsedLevel => ArticleLevel.tryParse(level);

  /// Kart ve okuma ekranında gösterilecek okuma süresi metni
  /// (örneğin `"5 - 8 dk"` veya `"4 - 6 dk"`).
  String get formattedReadingTime {
    final explicit = readingTimeLabel.trim();
    if (explicit.isNotEmpty) {
      final hasUnit = RegExp(
        r'(dk|dakika|min|minute)',
        caseSensitive: false,
      ).hasMatch(explicit);
      return hasUnit ? explicit : '$explicit dk';
    }

    if (readingTimeMinutes > 0) {
      if (readingTimeMinutes <= 2) {
        return '1 - 3 dk';
      }
      final minMinutes = readingTimeMinutes - 1;
      final maxMinutes = readingTimeMinutes + 1;
      return '$minMinutes - $maxMinutes dk';
    }

    final trimmedContent = content.trim();
    if (trimmedContent.isNotEmpty) {
      final wordCount = trimmedContent
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;
      if (wordCount > 0) {
        final low = (wordCount / 180).floor().clamp(1, 60);
        final rawHigh = (wordCount / 120).ceil().clamp(low + 1, 75);
        return '$low - $rawHigh dk';
      }
    }

    return '3 - 5 dk';
  }

  /// Esnek JSON ayrıştırıcı (`snake_case` ve `camelCase` alan adlarını destekler).
  /// Başlığı tamamen boş olan geçersiz kayıtlar için `null` döner.
  static Article? tryFromJson(
    Map<String, Object?> json, {
    int fallbackIndex = 0,
  }) {
    final title = _readString(json, const <String>['title', 'name']);
    if (title.isEmpty) return null;

    final rawId = _readString(json, const <String>['id', 'slug', 'key']);
    final id = rawId.isNotEmpty ? rawId : 'article_${fallbackIndex + 1}';

    final summary = _readString(
      json,
      const <String>['description', 'summary', 'subtitle', 'excerpt'],
    );
    final content = _readContent(json);
    final category = _readString(json, const <String>['category', 'topic']);
    final level = _readString(
      json,
      const <String>['level', 'difficulty', 'cefr'],
    );
    final rawLanguage = _readString(json, const <String>['language', 'lang']);
    final language = rawLanguage.isNotEmpty ? rawLanguage : 'en';
    final author = _readString(json, const <String>['author', 'byline']);

    final imageUrl = _readNullableString(
      json,
      const <String>['image_url', 'imageUrl', 'cover_url', 'coverUrl', 'image'],
    );
    final sourceUrl = _readNullableString(
      json,
      const <String>['source_url', 'sourceUrl', 'url', 'link'],
    );
    final audioUrl = _readNullableString(
      json,
      const <String>['audio_url', 'audioUrl', 'podcast_url', 'podcastUrl'],
    );
    final audioSegments = _readAudioSegments(
      json['audio_segments'] ?? json['audioSegments'],
    );

    final readingTimeLabel = _readReadingTimeLabel(json);
    final readingTimeMinutes = _readInt(
      json,
      const <String>[
        'reading_time_minutes',
        'readingTimeMinutes',
        'read_time',
        'readTime',
        'reading_time',
        'readingTime',
      ],
    );

    final tags = _readStringList(json['tags']);
    final wordMeanings = _readWordMeanings(
      json['word_meanings'] ?? json['wordMeanings'],
    );
    final sentenceTranslations = _readSentenceTranslations(
      json['sentence_translations'] ?? json['sentenceTranslations'],
    );
    final paragraphTranslations = _readParagraphTranslations(
      json['paragraph_translations'] ?? json['paragraphTranslations'],
    );
    final isHidden = _readBool(
      json,
      const <String>['is_hidden', 'isHidden', 'hidden'],
    );
    final publishAt = _readDateTime(
      json,
      const <String>['publish_at', 'publishAt', 'scheduled_at', 'scheduledAt'],
    );
    final publishedAt = _readDateTime(
      json,
      const <String>['published_at', 'publishedAt', 'date'],
    );
    final updatedAt = _readDateTime(
      json,
      const <String>['updated_at', 'updatedAt'],
    );

    String encodedRaw;
    try {
      encodedRaw = jsonEncode(json);
    } catch (_) {
      encodedRaw = '{}';
    }

    return Article(
      id: id,
      title: title,
      summary: summary,
      content: content,
      category: category,
      level: level,
      language: language,
      author: author,
      imageUrl: imageUrl,
      sourceUrl: sourceUrl,
      audioUrl: audioUrl,
      audioSegments: List<ArticleAudioSegment>.unmodifiable(audioSegments),
      readingTimeMinutes: readingTimeMinutes < 0 ? 0 : readingTimeMinutes,
      readingTimeLabel: readingTimeLabel,
      tags: List<String>.unmodifiable(tags),
      wordMeanings: Map<String, String>.unmodifiable(wordMeanings),
      sentenceTranslations:
          Map<String, String>.unmodifiable(sentenceTranslations),
      paragraphTranslations: List<String>.unmodifiable(paragraphTranslations),
      isHidden: isHidden,
      publishAt: publishAt,
      publishedAt: publishedAt,
      updatedAt: updatedAt,
      sortOrder: fallbackIndex,
      rawJson: encodedRaw,
    );
  }

  factory Article.fromDbRow(Map<String, Object?> row) {
    final publishedMillis = row['published_at'] as int?;
    final updatedMillis = row['updated_at'] as int?;
    final rawJson = (row['raw_json'] as String?) ?? '{}';
    final extractedAudio = _extractAudioFromRawJson(rawJson);
    final extractedTranslations = _extractPreparedTranslationsFromRawJson(rawJson);
    final extractedVisibility = _extractVisibilityFromRawJson(rawJson);

    return Article(
      id: (row['id'] as String? ?? '').trim(),
      title: (row['title'] as String? ?? '').trim(),
      summary: (row['summary'] as String? ?? '').trim(),
      content: (row['content'] as String? ?? ''),
      category: (row['category'] as String? ?? '').trim(),
      level: (row['level'] as String? ?? '').trim(),
      language: (row['language'] as String? ?? 'en').trim(),
      author: (row['author'] as String? ?? '').trim(),
      imageUrl: _trimOrNull(row['image_url'] as String?),
      sourceUrl: _trimOrNull(row['source_url'] as String?),
      audioUrl: extractedAudio.audioUrl,
      audioSegments: extractedAudio.audioSegments,
      readingTimeMinutes: (row['reading_time_minutes'] as int?) ?? 0,
      readingTimeLabel: (row['reading_time_label'] as String? ?? '').trim(),
      tags: List<String>.unmodifiable(
        _decodeTagsJson(row['tags_json'] as String?),
      ),
      wordMeanings: Map<String, String>.unmodifiable(
        _extractWordMeaningsFromRawJson(rawJson),
      ),
      sentenceTranslations: extractedTranslations.sentenceTranslations,
      paragraphTranslations: extractedTranslations.paragraphTranslations,
      isHidden: extractedVisibility.isHidden,
      publishAt: extractedVisibility.publishAt,
      publishedAt: publishedMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(publishedMillis)
          : null,
      updatedAt: updatedMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(updatedMillis)
          : null,
      sortOrder: (row['sort_order'] as int?) ?? 0,
      rawJson: rawJson,
    );
  }

  Map<String, Object?> toDbRow({required int cachedAtMillis}) {
    return <String, Object?>{
      'id': id,
      'title': title,
      'summary': summary,
      'content': content,
      'category': category,
      'level': level,
      'language': language,
      'author': author,
      'image_url': imageUrl,
      'source_url': sourceUrl,
      'reading_time_minutes': readingTimeMinutes,
      'reading_time_label': readingTimeLabel,
      'tags_json': jsonEncode(tags),
      'published_at': publishedAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'sort_order': sortOrder,
      'raw_json': rawJson,
      'cached_at': cachedAtMillis,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'description': summary,
      'summary': summary,
      'content': content,
      'category': category,
      'level': level,
      'language': language,
      'author': author,
      if (imageUrl != null) 'image_url': imageUrl,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (audioUrl != null) 'audio_url': audioUrl,
      if (audioSegments.isNotEmpty)
        'audio_segments': audioSegments.map((e) => e.toJson()).toList(),
      'reading_time_minutes': readingTimeMinutes,
      if (readingTimeLabel.isNotEmpty) 'reading_time': readingTimeLabel,
      'tags': tags,
      if (wordMeanings.isNotEmpty) 'word_meanings': wordMeanings,
      if (sentenceTranslations.isNotEmpty)
        'sentence_translations': sentenceTranslations,
      if (paragraphTranslations.isNotEmpty)
        'paragraph_translations': paragraphTranslations,
      if (isHidden) 'is_hidden': true,
      if (publishAt != null) 'publish_at': publishAt!.toUtc().toIso8601String(),
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  static ({bool isHidden, DateTime? publishAt}) _extractVisibilityFromRawJson(
    String rawJson,
  ) {
    if (rawJson.trim().isEmpty || rawJson == '{}') {
      return (isHidden: false, publishAt: null);
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        final map = Map<String, Object?>.from(decoded);
        return (
          isHidden: _readBool(
            map,
            const <String>['is_hidden', 'isHidden', 'hidden'],
          ),
          publishAt: _readDateTime(
            map,
            const <String>[
              'publish_at',
              'publishAt',
              'scheduled_at',
              'scheduledAt',
            ],
          ),
        );
      }
    } catch (_) {}
    return (isHidden: false, publishAt: null);
  }

  static bool _readBool(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final norm = value.trim().toLowerCase();
        if (norm == 'true' || norm == '1' || norm == 'yes') return true;
        if (norm == 'false' || norm == '0' || norm == 'no') return false;
      }
    }
    return false;
  }

  static List<ArticleAudioSegment> _readAudioSegments(Object? raw) {
    if (raw is! List) return const <ArticleAudioSegment>[];
    final list = <ArticleAudioSegment>[];
    for (final item in raw) {
      final parsed = ArticleAudioSegment.tryFromJson(item);
      if (parsed != null) {
        list.add(parsed);
      }
    }
    return list;
  }

  static ({String? audioUrl, List<ArticleAudioSegment> audioSegments})
      _extractAudioFromRawJson(String rawJson) {
    if (rawJson.trim().isEmpty || rawJson == '{}') {
      return (audioUrl: null, audioSegments: const <ArticleAudioSegment>[]);
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        final map = Map<String, Object?>.from(decoded);
        final url = _readNullableString(
          map,
          const <String>['audio_url', 'audioUrl', 'podcast_url', 'podcastUrl'],
        );
        final segments = _readAudioSegments(
          map['audio_segments'] ?? map['audioSegments'],
        );
        return (
          audioUrl: url,
          audioSegments: List<ArticleAudioSegment>.unmodifiable(segments),
        );
      }
    } catch (_) {
      // Bozuk ham JSON uygulamayı etkilememeli.
    }
    return (audioUrl: null, audioSegments: const <ArticleAudioSegment>[]);
  }

  static Map<String, String> _readSentenceTranslations(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = normalizeTranslationKey(entry.key.toString());
      final val = (entry.value?.toString() ?? '').trim();
      if (key.isNotEmpty && val.isNotEmpty) {
        result[key] = val;
      }
    }
    return result;
  }

  static List<String> _readParagraphTranslations(Object? raw) {
    if (raw is List) {
      return raw
          .map((item) => (item?.toString() ?? '').trim())
          .toList(growable: false);
    }
    if (raw is Map) {
      final indexed = <int, String>{};
      var maxIdx = -1;
      for (final entry in raw.entries) {
        final idx = int.tryParse(entry.key.toString().trim());
        final val = (entry.value?.toString() ?? '').trim();
        if (idx != null && idx >= 0 && val.isNotEmpty) {
          indexed[idx] = val;
          if (idx > maxIdx) maxIdx = idx;
        }
      }
      if (maxIdx < 0) return const <String>[];
      return List<String>.generate(
        maxIdx + 1,
        (i) => indexed[i] ?? '',
        growable: false,
      );
    }
    return const <String>[];
  }

  static ({
    Map<String, String> sentenceTranslations,
    List<String> paragraphTranslations,
  }) _extractPreparedTranslationsFromRawJson(String rawJson) {
    if (rawJson.trim().isEmpty || rawJson == '{}') {
      return (
        sentenceTranslations: const <String, String>{},
        paragraphTranslations: const <String>[],
      );
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        final map = Map<String, Object?>.from(decoded);
        return (
          sentenceTranslations: Map<String, String>.unmodifiable(
            _readSentenceTranslations(
              map['sentence_translations'] ?? map['sentenceTranslations'],
            ),
          ),
          paragraphTranslations: List<String>.unmodifiable(
            _readParagraphTranslations(
              map['paragraph_translations'] ?? map['paragraphTranslations'],
            ),
          ),
        );
      }
    } catch (_) {
      // Bozuk ham JSON uygulamayı etkilememeli.
    }
    return (
      sentenceTranslations: const <String, String>{},
      paragraphTranslations: const <String>[],
    );
  }

  static Map<String, String> _readWordMeanings(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = EnglishMorphologyResolver.normalize(entry.key.toString());
      final val = (entry.value?.toString() ?? '').trim();
      if (key.isNotEmpty && val.isNotEmpty) {
        result[key] = val;
      }
    }
    return result;
  }

  static Map<String, String> _extractWordMeaningsFromRawJson(String rawJson) {
    if (rawJson.trim().isEmpty || rawJson == '{}') {
      return const <String, String>{};
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        return _readWordMeanings(
          decoded['word_meanings'] ?? decoded['wordMeanings'],
        );
      }
    } catch (_) {
      // Bozuk ham JSON uygulamayı etkilememeli.
    }
    return const <String, String>{};
  }

  static String _readReadingTimeLabel(Map<String, Object?> json) {
    for (final key in const <String>[
      'reading_time_label',
      'readingTimeLabel',
      'estimated_read_time',
      'estimatedReadTime',
      'reading_time',
      'readingTime',
      'read_time_text',
      'readTimeText',
      'duration',
    ]) {
      final value = json[key];
      if (value is String) {
        final trimmed = value.trim();
        // Yalnızca düz tam sayı ise ("5") onu readingTimeMinutes'a bırak;
        // aralık veya birimli metin ise ("5 - 8 dk", "4-6 min") doğrudan koru.
        if (trimmed.isNotEmpty && int.tryParse(trimmed) == null) {
          return trimmed;
        }
      }
    }
    return '';
  }

  static String _readString(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) return trimmed;
      } else if (value is num) {
        return value.toString();
      }
    }
    return '';
  }

  static String? _readNullableString(
    Map<String, Object?> json,
    List<String> keys,
  ) {
    final value = _readString(json, keys);
    return value.isEmpty ? null : value;
  }

  static String _readContent(Map<String, Object?> json) {
    for (final key in const <String>['content', 'body', 'text']) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is List) {
        final joined = value
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .join('\n\n');
        if (joined.isNotEmpty) return joined;
      }
    }
    final paragraphs = json['paragraphs'];
    if (paragraphs is List) {
      return paragraphs
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join('\n\n');
    }
    return '';
  }

  static int _readInt(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  static List<String> _readStringList(Object? raw) {
    if (raw is List) {
      return raw
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static DateTime? _readDateTime(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      } else if (value is int) {
        // Saniye mi milisaniye mi olduğunu tahmin et.
        final millis = value < 100000000000 ? value * 1000 : value;
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }
    return null;
  }

  static List<String> _decodeTagsJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is List) {
        return decoded
            .map((item) => item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      // Bozuk etiket önbelleği uygulamayı bozmamalı.
    }
    return const <String>[];
  }

  static String? _trimOrNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Uzak JSON kaynağından gelen makale listesi ve sürüm/ETag üst verisi.
class ArticleFeedPayload {
  const ArticleFeedPayload({
    required this.articles,
    this.remoteVersion,
    this.updatedAt,
    this.etag,
    this.serverTimeUtc,
    this.notModified = false,
  });

  const ArticleFeedPayload.notModified({this.etag, this.serverTimeUtc})
      : articles = const <Article>[],
        remoteVersion = null,
        updatedAt = null,
        notModified = true;

  final List<Article> articles;
  final String? remoteVersion;
  final DateTime? updatedAt;
  final String? etag;
  final DateTime? serverTimeUtc;
  final bool notModified;
}

/// Yerel önbelleğin son senkronizasyon üst verileri.
class ArticleSyncMetadata {
  const ArticleSyncMetadata({
    this.lastSyncedAt,
    this.etag,
    this.remoteVersion,
    this.sourceUrl,
  });

  static const ArticleSyncMetadata empty = ArticleSyncMetadata();

  final DateTime? lastSyncedAt;
  final String? etag;
  final String? remoteVersion;
  final String? sourceUrl;

  ArticleSyncMetadata copyWith({
    DateTime? lastSyncedAt,
    String? etag,
    String? remoteVersion,
    String? sourceUrl,
  }) {
    return ArticleSyncMetadata(
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      etag: etag ?? this.etag,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
}

/// Uzak makale senkronizasyonunun sonucu.
enum ArticleSyncStatus {
  /// Uzaktan taze veri çekildi ve yerel önbellek güncellendi.
  updated,

  /// Uzak kaynak değişmemiş (HTTP 304); mevcut yerel önbellek güncel.
  notModified,

  /// Ağ yok veya istek başarısız; mevcut yerel önbellek korundu.
  offlineFallback,
}

class ArticleSyncResult {
  const ArticleSyncResult({
    required this.status,
    required this.articles,
    required this.metadata,
    this.serverTimeUtc,
    this.errorMessage,
  });

  final ArticleSyncStatus status;
  final List<Article> articles;
  final ArticleSyncMetadata metadata;
  final DateTime? serverTimeUtc;
  final String? errorMessage;

  bool get isOfflineFallback => status == ArticleSyncStatus.offlineFallback;
}
