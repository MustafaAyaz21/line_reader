import 'package:flutter/foundation.dart';

import '../data/translation_cache_repository.dart';
import '../models/word_meaning.dart';
import 'contextual_free_translation_service.dart';
import 'free_dictionary_translation_service.dart';
import 'gemini_translation_service.dart';
import 'word_translation_service.dart';

/// Yerel SQLite önbelleğini, isteğe bağlı doğrulanmış Gemini API anahtarını ve
/// anahtar gerektirmeyen ücretsiz servisleri koordine eden çeviri servisi:
/// 1. Önce yerel SQLite önbelleğini kontrol eder (aynı kelime + cümle anında gelir).
/// 2. Kullanılabilir bir Gemini API anahtarı varsa önce Gemini'yi dener ve
///    başarı/yetki sonucunu `ApiKeyController` geri çağrılarına bildirir.
/// 3. Gemini başarısız olursa hatayı konsola açıkça loglar ve kesintisiz olarak
///    anahtarsız ücretsiz servislere geçer.
/// 4. Başarılı sonuçları SQLite önbelleğine yazar.
class CachedTranslationService implements WordTranslationService {
  CachedTranslationService({
    required TranslationCacheRepository cacheRepository,
    String? Function()? geminiApiKeyProvider,
    bool Function()? shouldAttemptGeminiProvider,
    VoidCallback? onGeminiVerified,
    void Function(String errorMessage)? onGeminiUnauthorized,
    WordTranslationService? geminiService,
    WordTranslationService? primaryFreeService,
    WordTranslationService? fallbackFreeService,
  })  : _cacheRepository = cacheRepository,
        _geminiApiKeyProvider = geminiApiKeyProvider,
        _shouldAttemptGeminiProvider = shouldAttemptGeminiProvider,
        _onGeminiVerified = onGeminiVerified,
        _onGeminiUnauthorized = onGeminiUnauthorized,
        _geminiService = geminiService ??
            (geminiApiKeyProvider != null
                ? GeminiTranslationService(apiKeyProvider: geminiApiKeyProvider)
                : null),
        _primaryFreeService =
            primaryFreeService ?? ContextualFreeTranslationService(),
        _fallbackFreeService =
            fallbackFreeService ?? FreeDictionaryTranslationService(),
        _ownsGeminiService =
            geminiService == null && geminiApiKeyProvider != null,
        _ownsPrimaryFreeService = primaryFreeService == null,
        _ownsFallbackFreeService = fallbackFreeService == null;

  final TranslationCacheRepository _cacheRepository;
  final String? Function()? _geminiApiKeyProvider;
  final bool Function()? _shouldAttemptGeminiProvider;
  final VoidCallback? _onGeminiVerified;
  final void Function(String errorMessage)? _onGeminiUnauthorized;
  final WordTranslationService? _geminiService;
  final WordTranslationService _primaryFreeService;
  final WordTranslationService _fallbackFreeService;
  final bool _ownsGeminiService;
  final bool _ownsPrimaryFreeService;
  final bool _ownsFallbackFreeService;

  bool get _canAttemptGemini {
    final key = _geminiApiKeyProvider?.call()?.trim();
    if (key == null || key.isEmpty) return false;
    final allowed = _shouldAttemptGeminiProvider?.call() ?? true;
    return allowed && _geminiService != null;
  }

  /// Eski veya farklı kaynaktan kalmış çeviri önbelleğini temizler.
  Future<void> clearCache() async {
    await _cacheRepository.clear();
    debugPrint('[CachedTranslationService] SQLite ceviri onbellegi temizlendi.');
  }

  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    final useGemini = _canAttemptGemini;
    CachedTranslation? cached;

    // 1) Önce yerel SQLite önbelleğini kontrol et (sıfır ağ isteği).
    try {
      cached = await _cacheRepository.find(
        word: word,
        contextSentence: contextSentence,
      );
    } catch (error) {
      debugPrint('[CachedTranslationService] Onbellek okuma hatasi: $error');
      cached = null;
    }

    if (cached != null) {
      final shouldUpgradeWithGemini =
          useGemini && cached.source != TranslationCacheRepository.sourceGemini;
      if (!shouldUpgradeWithGemini) {
        return cached.meaning;
      }
    }

    // 2) Geçerli/denenebilir Gemini anahtarı varsa önce Gemini'yi çağır.
    if (useGemini) {
      try {
        final meaning = await _geminiService!.lookup(
          word: word,
          contextSentence: contextSentence,
        );
        _onGeminiVerified?.call();
        await _saveToCacheSafely(
          meaning: meaning,
          source: TranslationCacheRepository.sourceGemini,
        );
        debugPrint(
          '[CachedTranslationService] Gemini sonucu alindi: '
          '"$word" -> ${meaning.formattedMeaning}',
        );
        return meaning;
      } on TranslationException catch (error) {
        debugPrint(
          '[CachedTranslationService] Gemini istegi basarisiz '
          '(${error.type}): ${error.message}',
        );

        if (error.type == TranslationErrorType.unauthorized) {
          _onGeminiUnauthorized?.call(error.message);
        }

        if (error.type == TranslationErrorType.network) {
          if (cached != null) return cached.meaning;
          rethrow;
        }
        // Yetki/kota/yanıt hatasında hatayı logladıktan sonra ücretsiz servise geç.
      } catch (error) {
        debugPrint(
          '[CachedTranslationService] Gemini beklenmeyen hata: $error',
        );
      }
    }

    // 3) Birincil ücretsiz bağlam + iki dilli sözlük servisi.
    try {
      final meaning = await _primaryFreeService.lookup(
        word: word,
        contextSentence: contextSentence,
      );
      await _saveToCacheSafely(
        meaning: meaning,
        source: TranslationCacheRepository.sourcePrimaryFree,
      );
      return meaning;
    } on TranslationException catch (error) {
      debugPrint(
        '[CachedTranslationService] Birincil ucretsiz servis hatasi '
        '(${error.type}): ${error.message}',
      );
      if (error.type == TranslationErrorType.network) {
        if (cached != null) return cached.meaning;
        rethrow;
      }
    }

    // 4) İkincil ücretsiz açık sözlük + çeviri servisi.
    try {
      final fallbackMeaning = await _fallbackFreeService.lookup(
        word: word,
        contextSentence: contextSentence,
      );
      await _saveToCacheSafely(
        meaning: fallbackMeaning,
        source: TranslationCacheRepository.sourceFallbackFree,
      );
      return fallbackMeaning;
    } on TranslationException catch (error) {
      debugPrint(
        '[CachedTranslationService] Yedek ucretsiz servis hatasi '
        '(${error.type}): ${error.message}',
      );
      if (cached != null) return cached.meaning;
      rethrow;
    }
  }

  Future<void> _saveToCacheSafely({
    required WordMeaning meaning,
    required String source,
  }) async {
    try {
      await _cacheRepository.put(meaning: meaning, source: source);
    } catch (error) {
      debugPrint('[CachedTranslationService] Onbellek yazma hatasi: $error');
    }
  }

  @override
  void dispose() {
    if (_ownsGeminiService) {
      _geminiService?.dispose();
    }
    if (_ownsPrimaryFreeService) {
      _primaryFreeService.dispose();
    }
    if (_ownsFallbackFreeService) {
      _fallbackFreeService.dispose();
    }
  }
}
