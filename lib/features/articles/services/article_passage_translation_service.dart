import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/article.dart';
import '../utils/article_text_parser.dart';

/// Seçilen cümle veya paragrafın çeviri sonucu.
class PassageTranslationResult {
  const PassageTranslationResult({
    required this.originalText,
    required this.translatedText,
    required this.isFromArticlePreset,
  });

  final String originalText;
  final String translatedText;

  /// `true` ise çeviri doğrudan makalenin hazır `sentence_translations` veya
  /// `paragraph_translations` alanından sıfır ağ gecikmesiyle alınmıştır.
  final bool isFromArticlePreset;
}

class PassageTranslationException implements Exception {
  const PassageTranslationException(this.message);

  final String message;

  @override
  String toString() => 'PassageTranslationException: $message';
}

/// Test edilebilir cümle/paragraf çeviri soyutlaması.
abstract class ArticlePassageTranslator {
  Future<PassageTranslationResult> translate({
    required Article article,
    required String selectedText,
    int? paragraphIndex,
    String? fullParagraphText,
  });

  void dispose();
}

/// Makale okuma ekranında seçilen cümleleri, çoklu cümleleri veya tam
/// paragrafları Türkçeye çeviren servis:
/// 1. Önce makale verisindeki hazır `paragraph_translations` ve
///    `sentence_translations` alanlarına bakar (anında, çevrimdışı, hatasız).
/// 2. Oturum içi bellek önbelleğini kontrol eder.
/// 3. Makalede hazır çeviri yoksa ücretsiz çeviri uç noktası üzerinden
///    (uzun paragrafları cümle sınırlarından bölerek) temiz Türkçe çeviri alır.
class ArticlePassageTranslationService implements ArticlePassageTranslator {
  ArticlePassageTranslationService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const int _maxChunkChars = 850;
  static const int _maxCacheEntries = 60;

  final http.Client _httpClient;
  final bool _ownsClient;
  final Map<String, String> _sessionCache = <String, String>{};

  @override
  Future<PassageTranslationResult> translate({
    required Article article,
    required String selectedText,
    int? paragraphIndex,
    String? fullParagraphText,
  }) async {
    final cleanedOriginal = selectedText
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleanedOriginal.isEmpty) {
      throw const PassageTranslationException(
        'Çevrilecek bir cümle veya paragraf seçilmedi.',
      );
    }

    // 1) Önce makalenin hazır sentence_translations / paragraph_translations verisine bak.
    final preset = article.findPreparedTranslation(
      selectedText: cleanedOriginal,
      paragraphIndex: paragraphIndex,
      fullParagraphText: fullParagraphText,
    );
    if (preset != null && preset.isNotEmpty) {
      return PassageTranslationResult(
        originalText: cleanedOriginal,
        translatedText: preset,
        isFromArticlePreset: true,
      );
    }

    // 2) Oturum içi bellek önbelleği
    final cacheKey = Article.normalizeTranslationKey(cleanedOriginal);
    final cached = _sessionCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return PassageTranslationResult(
        originalText: cleanedOriginal,
        translatedText: cached,
        isFromArticlePreset: false,
      );
    }

    // 3) Uzun paragrafları güvenli parçalara bölerek ücretsiz çeviri uç noktasıyla çevir.
    final chunks = _splitIntoChunks(cleanedOriginal);
    final translatedParts = <String>[];

    for (final chunk in chunks) {
      final translated = await _translateChunkOnline(chunk);
      if (translated == null || translated.trim().isEmpty) {
        throw const PassageTranslationException(
          'Seçili metin şu anda çevrilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      }
      translatedParts.add(translated.trim());
    }

    final combined = translatedParts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (combined.isEmpty) {
      throw const PassageTranslationException(
        'Çeviri sonucu alınamadı. Lütfen tekrar deneyin.',
      );
    }

    _storeSessionCache(cacheKey, combined);
    return PassageTranslationResult(
      originalText: cleanedOriginal,
      translatedText: combined,
      isFromArticlePreset: false,
    );
  }

  List<String> _splitIntoChunks(String text) {
    if (text.length <= _maxChunkChars) {
      return <String>[text];
    }

    final sentences = ArticleTextParser.splitParagraphSentences(<String>[text]);
    if (sentences.isEmpty) {
      return <String>[text];
    }

    final chunks = <String>[];
    final buffer = StringBuffer();
    for (final sentence in sentences) {
      final sText = sentence.text.trim();
      if (sText.isEmpty) continue;
      if (buffer.isNotEmpty && buffer.length + sText.length + 1 > _maxChunkChars) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sText);
    }
    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
    }
    return chunks.isEmpty ? <String>[text] : chunks;
  }

  Future<String?> _translateChunkOnline(String chunk) async {
    final googleResult = await _fetchGoogleTranslate(chunk);
    if (googleResult != null && googleResult.isNotEmpty) {
      return googleResult;
    }

    if (chunk.length <= 450) {
      final myMemoryResult = await _fetchMyMemoryTranslate(chunk);
      if (myMemoryResult != null && myMemoryResult.isNotEmpty) {
        return myMemoryResult;
      }
    }

    return null;
  }

  Future<String?> _fetchGoogleTranslate(String text) async {
    try {
      final uri = Uri.parse(ApiConfig.contextualTranslateBaseUrl).replace(
        queryParameters: <String, String>{
          'client': 'gtx',
          'sl': 'en',
          'tl': 'tr',
          'dt': 't',
          'q': text,
        },
      );
      final response = await _httpClient
          .get(
            uri,
            headers: const <String, String>{'User-Agent': 'LineReaderApp'},
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! List || decoded.isEmpty) return null;

      final segments = decoded[0];
      if (segments is! List) return null;

      final buffer = StringBuffer();
      for (final seg in segments) {
        if (seg is List && seg.isNotEmpty && seg[0] is String) {
          buffer.write(seg[0] as String);
        }
      }
      final result = buffer.toString().trim();
      return result.isEmpty ? null : result;
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchMyMemoryTranslate(String text) async {
    try {
      final uri = Uri.parse(ApiConfig.myMemoryBaseUrl).replace(
        queryParameters: <String, String>{
          'q': text,
          'langpair': 'en|tr',
        },
      );
      final response = await _httpClient
          .get(
            uri,
            headers: const <String, String>{'User-Agent': 'LineReaderApp'},
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;
      final responseData = decoded['responseData'];
      if (responseData is! Map) return null;
      final translated = (responseData['translatedText'] as String? ?? '').trim();
      return translated.isEmpty ? null : translated;
    } catch (_) {
      return null;
    }
  }

  void _storeSessionCache(String key, String value) {
    if (_sessionCache.length >= _maxCacheEntries) {
      _sessionCache.remove(_sessionCache.keys.first);
    }
    _sessionCache[key] = value;
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
