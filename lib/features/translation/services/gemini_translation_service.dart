import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/word_meaning.dart';
import '../utils/turkish_infinitive_normalizer.dart';
import 'word_translation_service.dart';

/// Gemini API anahtarı bağlantı testinin sonucunu taşır.
class GeminiTestResult {
  const GeminiTestResult({
    required this.isSuccess,
    required this.message,
    this.isNetworkError = false,
  });

  final bool isSuccess;
  final String message;
  final bool isNetworkError;
}

/// Kullanıcının isteğe bağlı olarak girdiği Gemini API anahtarıyla çalışan,
/// bağlama duyarlı, fiilleri mastar formda döndüren ve sözcük türünü belirleyen servis.
///
/// Varsayılan olarak `ApiConfig.geminiModel` (`gemini-3.0-flash`) kullanılır;
/// bir model HTTP 404 döndürürse alternatif güncel modeller otomatik denenir.
class GeminiTranslationService implements WordTranslationService {
  GeminiTranslationService({
    required String? Function() apiKeyProvider,
    http.Client? httpClient,
    String? model,
    List<String>? fallbackModels,
  })  : _apiKeyProvider = apiKeyProvider,
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _customModel = model,
        _customFallbackModels = fallbackModels;

  static const String _systemPrompt = '''
You are a concise contextual dictionary for Turkish language learners reading articles.
Given a target word and the sentence where it appears, return up to 4 distinct Turkish dictionary meanings ordered as follows:
- Item 1 (index 0): MUST be the single most accurate Turkish meaning for the target word in the given context sentence (e.g. "hard" in a difficulty context -> "zor", in a texture context -> "sert"; "play" for an instrument -> "çalmak", for a game/sport -> "oynamak").
- Items 2, 3, and 4 (indices 1..3): The next 3 most frequent, distinct Turkish dictionary meanings of the target word in descending frequency order. Never repeat item 1 or duplicate any meaning. Provide 4 distinct meanings whenever the word has multiple senses or close common usages; never return empty entries.

STRICT RULES:
1. Verb infinitive rule: Whenever a meaning is a verb (even if the word is conjugated in the sentence like "playing", "played", "plays", "went"), NEVER use Turkish tense, aspect, or person suffixes (NEVER write "çalıyor", "oynuyor", "çalmakta", "gitti", "koşar"). ALWAYS return the plain Turkish infinitive (mastar) form ending in -mak/-mek (e.g. "çalmak", "oynamak", "gitmek", "koşmak").
2. Conciseness: Keep each "meaning" short (1-2 Turkish words, lowercase dictionary form, no parentheses, no punctuation, no extra explanation).
3. Part of speech: For each meaning, set "partOfSpeech" to strictly one of: "noun", "verb", "adjective", "adverb" (or null only if it does not fit these four categories).
4. Output format: Respond ONLY with valid JSON:
{"meanings": [{"meaning": "<turkish meaning>", "partOfSpeech": "<noun|verb|adjective|adverb|null>"}]}
''';

  final String? Function() _apiKeyProvider;
  final http.Client _httpClient;
  final bool _ownsClient;
  final String? _customModel;
  final List<String>? _customFallbackModels;

  /// En son başarılı olan model adını önbellekte tutar (tekrar 404 denemesini önler).
  String? _activeModel;

  String get activeModel =>
      _activeModel ?? _customModel ?? ApiConfig.geminiModel;

  List<String> _buildCandidateModels() {
    final ordered = <String>[
      if (_activeModel != null) _activeModel!,
      if (_customModel != null) _customModel!,
      ApiConfig.geminiModel,
      ...(_customFallbackModels ?? ApiConfig.geminiFallbackModels),
    ];

    final seen = <String>{};
    final result = <String>[];
    for (final candidate in ordered) {
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) {
    final apiKey = _apiKeyProvider()?.trim() ?? '';
    return _lookupWithApiKey(
      apiKey: apiKey,
      word: word,
      contextSentence: contextSentence,
    );
  }

  /// Verilen API anahtarını gerçek bir `generateContent` çağrısıyla doğrular.
  Future<GeminiTestResult> testConnection(String rawApiKey) async {
    final apiKey = rawApiKey.trim();
    if (apiKey.isEmpty) {
      return const GeminiTestResult(
        isSuccess: false,
        message: 'Lütfen geçerli bir Gemini API anahtarı girin.',
      );
    }

    try {
      final sample = await _lookupWithApiKey(
        apiKey: apiKey,
        word: 'hard',
        contextSentence: 'This exam is very hard.',
      );
      final usedModel = activeModel;
      debugPrint(
        '[GeminiTranslationService] Baglanti testi basarili '
        '(model: $usedModel, ornek: ${sample.formattedMeaning})',
      );
      return GeminiTestResult(
        isSuccess: true,
        message:
            'Bağlantı doğrulandı ($usedModel • örnek: ${sample.formattedMeaning}).',
      );
    } on TranslationException catch (error) {
      debugPrint(
        '[GeminiTranslationService] Baglanti testi basarisiz '
        '(${error.type}): ${error.message}',
      );
      return GeminiTestResult(
        isSuccess: false,
        message: error.message,
        isNetworkError: error.type == TranslationErrorType.network,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[GeminiTranslationService] Baglanti testinde beklenmeyen hata: '
        '$error\n$stackTrace',
      );
      return const GeminiTestResult(
        isSuccess: false,
        message: 'Gemini bağlantısı test edilirken beklenmeyen bir hata oluştu.',
      );
    }
  }

  Future<WordMeaning> _lookupWithApiKey({
    required String apiKey,
    required String word,
    String? contextSentence,
  }) async {
    if (apiKey.isEmpty) {
      debugPrint('[GeminiTranslationService] Hata: API anahtari bos.');
      throw const TranslationException(
        type: TranslationErrorType.unauthorized,
        message: 'Gemini API anahtarı tanımlı değil.',
      );
    }

    final normalizedContext = _normalizeContext(contextSentence);
    final candidateModels = _buildCandidateModels();
    TranslationException? lastNotFoundError;

    for (var i = 0; i < candidateModels.length; i++) {
      final model = candidateModels[i];
      final response = await _postGenerateContent(
        apiKey: apiKey,
        model: model,
        word: word,
        contextSentence: normalizedContext,
      );

      if (response.statusCode == 404) {
        final error = _buildHttpError(response, model: model);
        lastNotFoundError = error;
        if (_activeModel == model) {
          _activeModel = null;
        }
        if (i < candidateModels.length - 1) {
          debugPrint(
            '[GeminiTranslationService] $model kullanilamiyor (HTTP 404), '
            'sonraki model deneniyor: ${candidateModels[i + 1]}',
          );
          continue;
        }
        throw error;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        // HTTP 400 (API_KEY_INVALID), 401, 403, 429 vb. hatalarda alternatif
        // model denemeden doğrudan net hata döndür.
        throw _buildHttpError(response, model: model);
      }

      final meaning = _parseResponse(
        responseBody: response.body,
        word: word,
        contextSentence: normalizedContext,
        model: model,
      );
      _activeModel = model;
      return meaning;
    }

    throw lastNotFoundError ??
        const TranslationException(
          type: TranslationErrorType.unknown,
          message: 'Kullanılabilir bir Gemini modeli bulunamadı (HTTP 404).',
        );
  }

  Future<http.Response> _postGenerateContent({
    required String apiKey,
    required String model,
    required String word,
    required String? contextSentence,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.geminiBaseUrl}/$model:generateContent',
    );

    final userPrompt = contextSentence != null
        ? 'Target word: "$word"\nContext sentence: "$contextSentence"'
        : 'Target word: "$word"';

    final generationConfig = <String, Object?>{
      'temperature': 0.1,
      'maxOutputTokens': 768,
      'responseMimeType': 'application/json',
      'responseSchema': <String, Object?>{
        'type': 'OBJECT',
        'properties': <String, Object?>{
          'meanings': <String, Object?>{
            'type': 'ARRAY',
            'items': <String, Object?>{
              'type': 'OBJECT',
              'properties': <String, Object?>{
                'meaning': <String, Object?>{'type': 'STRING'},
                'partOfSpeech': <String, Object?>{
                  'type': 'STRING',
                  'nullable': true,
                },
              },
              'required': <String>['meaning'],
            },
          },
        },
        'required': <String>['meanings'],
      },
      // Gemini 2.5 modellerinde düşünme tokenlarının JSON çıktısını kesmesini önle.
      if (model.startsWith('gemini-2.5'))
        'thinkingConfig': <String, Object?>{
          'thinkingBudget': 0,
        },
    };

    final requestBody = jsonEncode(<String, Object?>{
      'systemInstruction': <String, Object?>{
        'parts': <Map<String, String>>[
          <String, String>{'text': _systemPrompt},
        ],
      },
      'contents': <Map<String, Object?>>[
        <String, Object?>{
          'role': 'user',
          'parts': <Map<String, String>>[
            <String, String>{'text': userPrompt},
          ],
        },
      ],
      'generationConfig': generationConfig,
    });

    try {
      return await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: requestBody,
          )
          .timeout(ApiConfig.requestTimeout);
    } on TimeoutException catch (error) {
      debugPrint(
        '[GeminiTranslationService] Zaman asimi ($model): $error',
      );
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'Gemini isteği zaman aşımına uğradı. Tekrar deneyin.',
      );
    } on SocketException catch (error) {
      debugPrint(
        '[GeminiTranslationService] Ag hatasi (SocketException): $error',
      );
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'İnternet bağlantısı kurulamadı.',
      );
    } on http.ClientException catch (error) {
      debugPrint(
        '[GeminiTranslationService] HTTP istemci hatasi: $error',
      );
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'Gemini servisine bağlanılamadı.',
      );
    }
  }

  TranslationException _buildHttpError(
    http.Response response, {
    required String model,
  }) {
    final statusCode = response.statusCode;
    final parsedError = _extractApiErrorDetails(response.body);
    final apiMessage = parsedError.message;
    final reason = parsedError.reason;

    debugPrint(
      '[GeminiTranslationService] HTTP $statusCode '
      '(model: $model, reason: ${reason ?? "none"}): '
      '${apiMessage ?? response.body}',
    );

    final looksLikeInvalidKey = statusCode == 401 ||
        statusCode == 403 ||
        reason == 'API_KEY_INVALID' ||
        (statusCode == 400 &&
            (apiMessage?.toLowerCase().contains('api key') ?? false));

    if (looksLikeInvalidKey) {
      return TranslationException(
        type: TranslationErrorType.unauthorized,
        message: apiMessage != null
            ? 'Geçersiz Gemini API anahtarı (HTTP $statusCode): $apiMessage'
            : 'Gemini API anahtarı geçersiz veya yetkisiz (HTTP $statusCode).',
      );
    }

    if (statusCode == 404) {
      return TranslationException(
        type: TranslationErrorType.unknown,
        message: apiMessage != null
            ? 'Gemini modeli bulunamadı ($model • HTTP 404): $apiMessage'
            : 'Gemini modeli bulunamadı ($model • HTTP 404).',
      );
    }

    if (statusCode == 429) {
      return const TranslationException(
        type: TranslationErrorType.rateLimited,
        message: 'Gemini istek limiti geçici olarak doldu (HTTP 429).',
      );
    }

    return TranslationException(
      type: TranslationErrorType.unknown,
      message: apiMessage != null
          ? 'Gemini hatası (HTTP $statusCode): $apiMessage'
          : 'Gemini servisi yanıt vermedi (HTTP $statusCode).',
    );
  }

  _ApiErrorDetails _extractApiErrorDetails(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        return const _ApiErrorDetails();
      }
      final error = decoded['error'];
      if (error is! Map<String, Object?>) {
        return const _ApiErrorDetails();
      }

      final message = error['message'] as String?;
      String? reason;
      final details = error['details'];
      if (details is List<Object?>) {
        for (final item in details) {
          if (item is Map<String, Object?> && item['reason'] is String) {
            reason = item['reason'] as String;
            break;
          }
        }
      }

      return _ApiErrorDetails(message: message, reason: reason);
    } catch (_) {
      return const _ApiErrorDetails();
    }
  }

  WordMeaning _parseResponse({
    required String responseBody,
    required String word,
    required String? contextSentence,
    required String model,
  }) {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, Object?>;
      final candidates = decoded['candidates'] as List<Object?>?;
      if (candidates == null || candidates.isEmpty) {
        debugPrint(
          '[GeminiTranslationService] Bos candidates yaniti ($model): '
          '$responseBody',
        );
        throw const FormatException('Empty candidates');
      }

      final firstCandidate = candidates.first as Map<String, Object?>;
      final finishReason = firstCandidate['finishReason'] as String?;
      if (finishReason != null && finishReason != 'STOP') {
        debugPrint(
          '[GeminiTranslationService] Beklenmeyen finishReason ($model): '
          '$finishReason (body: $responseBody)',
        );
      }

      final content = firstCandidate['content'] as Map<String, Object?>?;
      final parts = content?['parts'] as List<Object?>?;
      if (parts == null || parts.isEmpty) {
        debugPrint(
          '[GeminiTranslationService] Bos parts yaniti ($model): $responseBody',
        );
        throw const FormatException('Empty parts');
      }

      final rawText = _extractAnswerText(parts);
      if (rawText == null || rawText.trim().isEmpty) {
        debugPrint(
          '[GeminiTranslationService] Yanit metni bos ($model): $responseBody',
        );
        throw const FormatException('Empty text');
      }

      final cleanedJson = _stripCodeFences(rawText);
      final payload = jsonDecode(cleanedJson) as Map<String, Object?>;

      final entries = <MeaningEntry>[];
      final rawMeanings = payload['meanings'];

      if (rawMeanings is List<Object?>) {
        for (final item in rawMeanings) {
          if (item is! Map<String, Object?>) continue;
          final parsedPos =
              WordPartOfSpeech.tryParse(item['partOfSpeech']?.toString());
          final cleanedMeaning = TurkishInfinitiveNormalizer.normalize(
            item['meaning']?.toString() ?? '',
            isVerb: parsedPos == WordPartOfSpeech.verb,
          );
          if (cleanedMeaning.isEmpty) continue;

          entries.add(
            MeaningEntry(
              translation: cleanedMeaning,
              partOfSpeech: parsedPos,
              isContextual: entries.isEmpty,
            ),
          );
        }
      } else {
        // Geriye dönük tekli JSON yanıtı desteği.
        final parsedPos =
            WordPartOfSpeech.tryParse(payload['partOfSpeech']?.toString());
        final cleanedMeaning = TurkishInfinitiveNormalizer.normalize(
          payload['meaning']?.toString() ?? '',
          isVerb: parsedPos == WordPartOfSpeech.verb,
        );
        if (cleanedMeaning.isNotEmpty) {
          entries.add(
            MeaningEntry(
              translation: cleanedMeaning,
              partOfSpeech: parsedPos,
              isContextual: true,
            ),
          );
        }
      }

      if (entries.isEmpty) {
        debugPrint(
          '[GeminiTranslationService] Temizlenmis anlam bos ($model): '
          '$cleanedJson',
        );
        throw const FormatException('Empty meaning');
      }

      return WordMeaning.fromEntries(
        word: word,
        entries: entries,
        contextSentence: contextSentence,
      );
    } catch (error) {
      debugPrint(
        '[GeminiTranslationService] Yanit ayristirma hatasi ($model): $error '
        '| rawBody: $responseBody',
      );
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'Gemini yanıtı beklenen JSON biçiminde okunamadı.',
      );
    }
  }

  /// Düşünme (`thought: true`) parçalarını atlayarak asıl metin yanıtını döner.
  String? _extractAnswerText(List<Object?> parts) {
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is! Map<String, Object?>) continue;
      if (part['thought'] == true) continue;
      final text = part['text'];
      if (text is String && text.isNotEmpty) {
        buffer.write(text);
      }
    }
    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  String _stripCodeFences(String raw) {
    var trimmed = raw.trim();
    if (trimmed.startsWith('```')) {
      final firstNewLine = trimmed.indexOf('\n');
      if (firstNewLine != -1) {
        trimmed = trimmed.substring(firstNewLine + 1);
      }
      if (trimmed.endsWith('```')) {
        trimmed = trimmed.substring(0, trimmed.length - 3);
      }
    }
    return trimmed.trim();
  }

  String? _normalizeContext(String? sentence) {
    if (sentence == null) return null;
    final trimmed = sentence.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}

class _ApiErrorDetails {
  const _ApiErrorDetails({this.message, this.reason});

  final String? message;
  final String? reason;
}
