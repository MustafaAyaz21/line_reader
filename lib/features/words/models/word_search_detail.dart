import '../../translation/models/word_meaning.dart';

/// Manuel kelime aramasında gösterilen tek bir kısa örnek cümle.
class WordExampleSentence {
  const WordExampleSentence({
    required this.english,
    this.turkish,
  });

  final String english;
  final String? turkish;
}

/// Kelime listesine manuel ekleme ekranında gösterilen ayrıntılı arama sonucu:
/// 10–15 farklı Türkçe anlam ve 3 kısa örnek cümle.
class WordSearchDetail {
  const WordSearchDetail({
    required this.word,
    required this.meanings,
    required this.examples,
  });

  final String word;
  final List<MeaningEntry> meanings;
  final List<WordExampleSentence> examples;
}
