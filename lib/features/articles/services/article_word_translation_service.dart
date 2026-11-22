import '../../translation/models/word_meaning.dart';
import '../../translation/services/local_dictionary_service.dart';
import '../../translation/services/word_translation_service.dart';
import '../models/article.dart';

/// Makale okuma ekranı için önceliklendirilmiş kelime çözümleme servisi:
/// 1. Önce açık olan makalenin `word_meanings` haritasına (tam kelime ve
///    kök/temel form üzerinden) bakar; bulunursa 1. sırada o cümledeki birebir
///    anlamı kesin olarak korur.
/// 2. 2.–4. sıraları önce yerel sözlükten, 4 anlama ulaşmadıysa çevrimiçi /
///    SQLite önbellekli sözlük servisinden (tekrarsız ve çevrimdışı güvenli
///    biçimde) zenginleştirir.
/// 3. Makalede tanımlı değilse doğrudan standart çeviri servisi + yerel sözlük
///    yedeği çalışır.
class ArticleWordTranslationService implements WordTranslationService {
  ArticleWordTranslationService({
    required Article article,
    required WordTranslationService fallbackService,
    LocalDictionaryService? localDictionary,
  })  : _article = article,
        _fallbackService = fallbackService,
        _localDictionary = localDictionary ?? LocalDictionaryService();

  final Article _article;
  final WordTranslationService _fallbackService;
  final LocalDictionaryService _localDictionary;

  String _normKey(String raw) => raw.trim().replaceAll('İ', 'i').toLowerCase();

  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    // 1) Açık makalenin kendi word_meanings haritasını (tam kelime + kök formu) kontrol et.
    final articleMatch = _article.findWordMeaning(word);
    if (articleMatch != null) {
      final entries = <MeaningEntry>[
        MeaningEntry(
          translation: articleMatch.meaning,
          isContextual: true,
        ),
      ];
      final seen = <String>{_normKey(articleMatch.meaning)};

      void appendExtra(List<MeaningEntry> extras) {
        for (final extra in extras) {
          if (entries.length >= WordMeaning.maxEntries) break;
          final key = _normKey(extra.translation);
          if (key.isEmpty) continue;
          if (seen.add(key)) {
            entries.add(
              MeaningEntry(
                translation: extra.translation,
                partOfSpeech: extra.partOfSpeech,
                isContextual: false,
              ),
            );
          } else if (entries.first.partOfSpeech == null &&
              key == _normKey(articleMatch.meaning) &&
              extra.partOfSpeech != null) {
            // 1. anlamın sözcük türü (fiil/isim/sıfat) bilgisi eksikse onu da tamamla.
            entries[0] = entries[0].copyWith(partOfSpeech: extra.partOfSpeech);
          }
        }
      }

      // 2-4. sıraları önce yerel sözlükten zenginleştir.
      try {
        final localExtra = await _localDictionary.lookup(
          word,
          contextSentence: contextSentence,
        );
        if (localExtra != null) {
          appendExtra(localExtra.meaning.orderedEntries);
        }
      } catch (_) {}

      // Hâlâ 4 anlama ulaşmadıysa çevrimiçi / SQLite önbellekli sözlükten tamamla
      // (ağ yoksa veya kota dolduysa sessizce eldeki 1-3 anlamla devam eder).
      if (entries.length < WordMeaning.maxEntries) {
        try {
          final remoteExtra = await _fallbackService
              .lookup(
                word: word,
                contextSentence: contextSentence,
              )
              .timeout(const Duration(seconds: 4));
          appendExtra(remoteExtra.orderedEntries);
        } catch (_) {}
      }

      return WordMeaning.fromEntries(
        word: word,
        entries: entries,
        contextSentence: contextSentence,
      );
    }

    // 2) Makalede özel anlam yoksa standart çeviri servisini (önbellek + çevrimiçi) dene.
    try {
      return await _fallbackService.lookup(
        word: word,
        contextSentence: contextSentence,
      );
    } on TranslationException catch (error) {
      // Misafir / standart günlük sınır aşıldıysa kotayı atlamadan kullanıcıya bildir.
      if (error.type == TranslationErrorType.guestLimitReached) {
        rethrow;
      }

      // 3) Çevrimdışı veya sunucu hatasında hafif yerel sözlük + kök çözümleyiciye düş.
      final localResult = await _localDictionary.lookup(
        word,
        contextSentence: contextSentence,
      );
      if (localResult != null) {
        return localResult.meaning;
      }
      rethrow;
    } catch (_) {
      final localResult = await _localDictionary.lookup(
        word,
        contextSentence: contextSentence,
      );
      if (localResult != null) {
        return localResult.meaning;
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    // `_fallbackService` üst ekrana aittir; burada kapatılmaz.
  }
}
