import '../../translation/models/word_meaning.dart';
import '../../translation/services/local_dictionary_service.dart';
import '../../translation/services/word_translation_service.dart';
import '../models/article.dart';

/// Makale okuma ekranı için önceliklendirilmiş kelime çözümleme servisi:
/// 1. Önce açık olan makalenin `word_meanings` haritasına (tam kelime ve
///    kök/temel form üzerinden) bakar; bulunursa o cümledeki birebir anlamı
///    anında (çevrimdışı ve kotadan düşmeden) döner.
/// 2. Makalede tanımlı değilse uygulamanın mevcut çeviri servisini
///    (`CachedTranslationService`) çağırır.
/// 3. Ağ hatası / çevrimdışı durumda hafif yerel sözlük + kök çözümleyici
///    (`LocalDictionaryService`) devreye girer.
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

      // 2-4. sıraları ağ isteği yapmadan varsa yerel sözlükten zenginleştir.
      try {
        final localExtra = await _localDictionary.lookup(
          word,
          contextSentence: contextSentence,
        );
        if (localExtra != null) {
          final seen = <String>{
            articleMatch.meaning.replaceAll('İ', 'i').toLowerCase(),
          };
          for (final extra in localExtra.meaning.orderedEntries) {
            if (entries.length >= 4) break;
            final key = extra.translation.replaceAll('İ', 'i').toLowerCase();
            if (seen.add(key)) {
              entries.add(
                MeaningEntry(
                  translation: extra.translation,
                  partOfSpeech: extra.partOfSpeech,
                  isContextual: false,
                ),
              );
            }
          }
        }
      } catch (_) {}

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
      // Misafir 40 kelime sınırı aşıldıysa kotayı atlamadan kullanıcıya bildir.
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
