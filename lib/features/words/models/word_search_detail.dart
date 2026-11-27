import '../../translation/models/word_lexicon_info.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/utils/english_morphology_resolver.dart';

/// Manuel kelime aramasında gösterilen tek bir kısa örnek cümle.
class WordExampleSentence {
  const WordExampleSentence({
    required this.english,
    this.turkish,
    this.source,
  });

  final String english;
  final String? turkish;
  /// Alıntı kaynağı: `'subtitle'` (Film/Dizi), `'tatoeba'` veya `null`.
  final String? source;
}

/// Kelime listesine manuel ekleme ekranında gösterilen ayrıntılı arama sonucu:
/// 10–15 farklı Türkçe anlam, 3 kısa örnek cümle, US/UK IPA + eş/zıt anlamlar
/// ve hatalı yazımlarda Google mantığıyla "Bunu mu aratmak istediniz?" önerileri.
class WordSearchDetail {
  const WordSearchDetail({
    required this.word,
    required this.meanings,
    required this.examples,
    this.lexiconInfo,
    this.inflectionInfo,
    this.isMisspelled = false,
    this.suggestions = const <String>[],
  });

  final String word;
  final List<MeaningEntry> meanings;
  final List<WordExampleSentence> examples;
  final WordLexiconInfo? lexiconInfo;

  /// Aranan kelime çekimli veya düzensiz bir biçimse (ör. `bought` -> `buy`)
  /// temel kelimeye yönlendiren kök/çekim bilgisini taşır.
  final WordInflectionInfo? inflectionInfo;

  /// Kelime İngilizce sözlüklerde geçersiz / yanlış yazılmış tespit edildiyse
  /// `true` olur; uydurma anlam veya hatalı telaffuz gösterilmez.
  final bool isMisspelled;

  /// Google mantığıyla önerilen doğru İngilizce kelime adayları (`elone` → `alone`).
  final List<String> suggestions;
}

/// Arama çubuğunda kullanıcı yazarken gösterilen anlık önek önerisi.
class WordPrefixSuggestion {
  const WordPrefixSuggestion({
    required this.word,
    required this.turkishPreview,
  });

  final String word;
  final String turkishPreview;
}
