import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/word_meaning.dart';
import 'gemini_translation_service.dart';
import 'word_translation_service.dart';

/// Yalnızca tarayıcı (Web) ekranında **kayıtlı kullanıcı** bir kelimeye
/// dokunduğunda/seçtiğinde, kelimenin geçtiği cümleyi bağlam olarak alıp
/// Cloudflare Workers AI üzerinden birebir Türkçe anlam üreten servis.
///
/// - APK içine hiçbir gizli API anahtarı koymaz.
/// - Misafir kullanıcılar bu servisi kullanamaz (doğrudan ücretsiz sözlüklere geçer).
/// - Kayıtlı kullanıcının Firebase ID Token'ı `Authorization: Bearer` ile Worker'a
///   gönderilir; günlük ücretsiz Workers AI kotası dolarsa (HTTP 429) veya ağ
///   hatası olursa [CachedTranslationService] otomatik olarak ücretsiz sözlüklere düşer.
class BrowserAiTranslationService implements WordTranslationService {
  BrowserAiTranslationService({
    String? proxyEndpoint,
    bool Function()? isUserAuthenticatedProvider,
    Future<String?> Function()? authTokenProvider,
    String? Function()? apiKeyProvider,
    WordTranslationService? geminiService,
    http.Client? httpClient,
  })  : _proxyEndpoint =
            (proxyEndpoint ?? ApiConfig.browserAiTranslateEndpoint).trim(),
        _isUserAuthenticatedProvider = isUserAuthenticatedProvider,
        _authTokenProvider = authTokenProvider,
        _apiKeyProvider = apiKeyProvider ?? _defaultApiKeyProvider,
        _geminiService = geminiService ??
            GeminiTranslationService(
              apiKeyProvider: apiKeyProvider ?? _defaultApiKeyProvider,
              httpClient: httpClient,
            ),
        _ownsGemini = geminiService == null,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  final String _proxyEndpoint;
  final bool Function()? _isUserAuthenticatedProvider;
  final Future<String?> Function()? _authTokenProvider;
  final String? Function() _apiKeyProvider;
  final WordTranslationService _geminiService;
  final bool _ownsGemini;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  static String? _defaultApiKeyProvider() {
    final managed = ApiConfig.managedGeminiApiKey.trim();
    return managed.isNotEmpty ? managed : null;
  }

  bool get isConfigured {
    if (_proxyEndpoint.startsWith('http')) return true;
    final key = _apiKeyProvider()?.trim() ?? '';
    return key.isNotEmpty;
  }

  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    // Misafir kullanıcılar AI bağlamsal çeviriyi kullanamaz -> ücretsiz sözlüğe düş.
    final isAuthenticated = _isUserAuthenticatedProvider?.call() ?? true;
    if (!isAuthenticated) {
      throw const TranslationException(
        type: TranslationErrorType.unauthorized,
        message: 'Bağlamsal AI çeviri yalnızca kayıtlı kullanıcılar içindir.',
      );
    }

    if (_proxyEndpoint.startsWith('http')) {
      try {
        return await _lookupViaProxy(
          word: word,
          contextSentence: contextSentence,
        );
      } on TranslationException {
        final key = _apiKeyProvider()?.trim() ?? '';
        if (key.isEmpty) rethrow;
      }
    }

    final key = _apiKeyProvider()?.trim() ?? '';
    if (key.isEmpty) {
      throw const TranslationException(
        type: TranslationErrorType.unauthorized,
        message: 'Tarayıcı AI servisi yapılandırılmadı.',
      );
    }

    return _geminiService.lookup(
      word: word,
      contextSentence: contextSentence,
    );
  }

  Future<WordMeaning> _lookupViaProxy({
    required String word,
    String? contextSentence,
  }) async {
    final token = (await _authTokenProvider?.call())?.trim() ?? '';
    if (_authTokenProvider != null && token.isEmpty) {
      throw const TranslationException(
        type: TranslationErrorType.unauthorized,
        message: 'AI çeviri için geçerli kullanıcı oturumu gerekli.',
      );
    }

    final uri = Uri.parse(_proxyEndpoint);
    http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'User-Agent': 'LineReaderApp',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, Object?>{
              'word': word.trim(),
              if (contextSentence != null && contextSentence.trim().isNotEmpty)
                'context_sentence': contextSentence.trim(),
              'target_language': 'tr',
            }),
          )
          .timeout(ApiConfig.requestTimeout);
    } on TimeoutException {
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'AI çeviri sunucusu zaman aşımına uğradı.',
      );
    } on SocketException {
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'İnternet bağlantısı kurulamadı.',
      );
    } catch (error) {
      debugPrint('[BrowserAiTranslationService] Proxy hatasi: $error');
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'AI çeviri sunucusuna erişilemedi.',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const TranslationException(
        type: TranslationErrorType.unauthorized,
        message: 'AI çeviri oturumu doğrulanamadı.',
      );
    }

    if (response.statusCode == 429) {
      throw const TranslationException(
        type: TranslationErrorType.rateLimited,
        message: 'Günlük AI çeviri kotası doldu; ücretsiz sözlük kullanılıyor.',
      );
    }

    if (response.statusCode != 200) {
      throw TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'AI çeviri sunucusu yanıt vermedi (HTTP ${response.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) {
        throw const FormatException('Beklenmeyen JSON kökü');
      }

      final entries = <MeaningEntry>[];
      final rawMeanings = decoded['meanings'];
      if (rawMeanings is List) {
        for (var i = 0; i < rawMeanings.length; i++) {
          final item = rawMeanings[i];
          if (item is Map) {
            final map = Map<String, Object?>.from(item);
            final translation =
                (map['translation'] ?? map['meaning'] ?? '').toString().trim();
            if (translation.isEmpty) continue;
            entries.add(
              MeaningEntry(
                translation: translation,
                partOfSpeech: WordPartOfSpeech.tryParse(
                  (map['partOfSpeech'] ?? map['part_of_speech'])?.toString(),
                ),
                isContextual: i == 0 || map['isContextual'] == true,
              ),
            );
          } else if (item is String && item.trim().isNotEmpty) {
            entries.add(
              MeaningEntry(
                translation: item.trim(),
                isContextual: i == 0,
              ),
            );
          }
        }
      }

      if (entries.isEmpty) {
        final single =
            (decoded['translation'] ?? decoded['meaning'] ?? '').toString().trim();
        if (single.isNotEmpty) {
          entries.add(
            MeaningEntry(
              translation: single,
              partOfSpeech: WordPartOfSpeech.tryParse(
                (decoded['partOfSpeech'] ?? decoded['part_of_speech'])
                    ?.toString(),
              ),
              isContextual: true,
            ),
          );
        }
      }

      if (entries.isEmpty) {
        throw const FormatException('Anlam listesi boş');
      }

      return WordMeaning.fromEntries(
        word: word,
        entries: entries,
        contextSentence: contextSentence,
      );
    } catch (error) {
      debugPrint('[BrowserAiTranslationService] Proxy yanit hatasi: $error');
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'AI çeviri yanıtı okunamadı.',
      );
    }
  }

  @override
  void dispose() {
    if (_ownsGemini) {
      _geminiService.dispose();
    }
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}
