import '../../translation/models/word_lexicon_info.dart';
import '../../translation/services/word_lexicon_service.dart';
import '../models/article.dart';

/// Makale okuma ekranında bir kelimeye bakıldığında:
/// - **Eş anlamlılar & Zıt anlamlılar** için öncelikle açık makalenin
///   `word_relations` haritasındaki (o cümledeki anlama birebir uyan)
///   bağlamsal eş/zıt anlamları döndürür.
/// - **US / UK IPA** okunuşunu ise her zaman doğrulanmış sözlük kaynağından
///   ([WordLexiconService]) alır (uydurma IPA üretilmez).
/// - Makalede ilgili kelime için bağlamsal kayıt yoksa genel çevrimdışı/çevrimiçi
///   sözlük yedeğine sorunsuz düşer.
class ArticleWordLexiconService extends WordLexiconService {
  ArticleWordLexiconService({
    required this.article,
    WordLexiconService? baseService,
  })  : _baseService = baseService ?? WordLexiconService.shared,
        super(enableOnlineEnrichment: false);

  final Article article;
  final WordLexiconService _baseService;

  @override
  Future<WordLexiconInfo?> lookup(
    String rawWord, {
    bool allowOnline = true,
  }) async {
    final cleaned = rawWord.trim().toLowerCase();
    if (cleaned.isEmpty) return null;

    final contextual = article.findWordRelations(cleaned);
    final base = await _baseService.lookup(cleaned, allowOnline: allowOnline);
    if (contextual == null) {
      return base;
    }

    return WordLexiconInfo(
      word: (base != null && base.word.isNotEmpty) ? base.word : cleaned,
      ipaUs: base?.ipaUs,
      ipaUk: base?.ipaUk,
      synonyms: contextual.synonyms,
      antonyms: contextual.antonyms,
    );
  }

  @override
  void dispose() {
    // Paylaşılan _baseService üst katman tarafından yönetilir.
  }
}
