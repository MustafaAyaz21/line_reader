import 'dart:convert';

import '../../translation/utils/english_morphology_resolver.dart';
import 'article_level.dart';

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
    this.readingTimeMinutes = 0,
    this.readingTimeLabel = '',
    this.tags = const <String>[],
    this.wordMeanings = const <String, String>{},
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
  final int readingTimeMinutes;
  final String readingTimeLabel;
  final List<String> tags;

  /// Makale içinde yazar/editör tarafından tanımlanmış bağlamsal kelime
  /// anlamları (`word_meanings` haritası; küçük harfe normalleştirilmiş anahtar).
  final Map<String, String> wordMeanings;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final int sortOrder;

  /// Gelecekte JSON kaynağına eklenecek ek alanların önbellekte kaybolmaması
  /// için ham JSON kaydı saklanır.
  final String rawJson;

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
      readingTimeMinutes: readingTimeMinutes < 0 ? 0 : readingTimeMinutes,
      readingTimeLabel: readingTimeLabel,
      tags: List<String>.unmodifiable(tags),
      wordMeanings: Map<String, String>.unmodifiable(wordMeanings),
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
      readingTimeMinutes: (row['reading_time_minutes'] as int?) ?? 0,
      readingTimeLabel: (row['reading_time_label'] as String? ?? '').trim(),
      tags: List<String>.unmodifiable(
        _decodeTagsJson(row['tags_json'] as String?),
      ),
      wordMeanings: Map<String, String>.unmodifiable(
        _extractWordMeaningsFromRawJson(rawJson),
      ),
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
      'reading_time_minutes': readingTimeMinutes,
      if (readingTimeLabel.isNotEmpty) 'reading_time': readingTimeLabel,
      'tags': tags,
      if (wordMeanings.isNotEmpty) 'word_meanings': wordMeanings,
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
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
    this.notModified = false,
  });

  const ArticleFeedPayload.notModified({this.etag})
      : articles = const <Article>[],
        remoteVersion = null,
        updatedAt = null,
        notModified = true;

  final List<Article> articles;
  final String? remoteVersion;
  final DateTime? updatedAt;
  final String? etag;
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
    this.errorMessage,
  });

  final ArticleSyncStatus status;
  final List<Article> articles;
  final ArticleSyncMetadata metadata;
  final String? errorMessage;

  bool get isOfflineFallback => status == ArticleSyncStatus.offlineFallback;
}
