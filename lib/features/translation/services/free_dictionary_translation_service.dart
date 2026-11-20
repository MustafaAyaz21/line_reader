import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/word_meaning.dart';
import '../utils/turkish_infinitive_normalizer.dart';
import 'word_translation_service.dart';

/// Hiçbir API anahtarı veya kredi kartı gerektirmeyen, tamamen ücretsiz açık
/// kaynak sözlük (`dictionaryapi.dev`) ve çeviri (`mymemory.translated.net`)
/// servislerini bağlam cümlesi analiziyle birleştiren çeviri servisi.
class FreeDictionaryTranslationService implements WordTranslationService {
  FreeDictionaryTranslationService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const Set<String> _stopWords = <String>{
    'this', 'that', 'these', 'those', 'with', 'from', 'into', 'about',
    'there', 'their', 'they', 'them', 'were', 'have', 'been', 'will',
    'would', 'could', 'should', 'what', 'when', 'where', 'which', 'while',
    'your', 'ours', 'just', 'very', 'more', 'most', 'some', 'such', 'than',
    'then', 'also', 'only', 'over', 'under', 'after', 'before', 'because',
  };

  static const Set<String> _verbBeforeCues = <String>{
    'to', 'will', 'would', 'can', 'could', 'shall', 'should', 'may',
    'might', 'must', 'do', 'does', 'did', 'dont', 'doesnt', 'didnt',
    'cant', 'wont', 'shouldnt', 'wouldnt', 'never', 'always',
  };

  static const Set<String> _nounBeforeCues = <String>{
    'a', 'an', 'the', 'this', 'that', 'these', 'those', 'my', 'your',
    'his', 'her', 'its', 'our', 'their', 'some', 'any', 'many', 'few',
    'several', 'every', 'each', 'no',
  };

  static const Set<String> _adjectiveBeforeCues = <String>{
    'very', 'so', 'too', 'quite', 'really', 'extremely', 'pretty',
    'rather', 'fairly', 'more', 'most', 'less', 'least', 'how',
  };

  static const Set<String> _copulaCues = <String>{
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am',
    'seem', 'seems', 'seemed', 'feel', 'feels', 'felt',
    'look', 'looks', 'looked', 'become', 'becomes', 'became',
  };

  static const Set<String> _musicContextTokens = <String>{
    'piano', 'guitar', 'violin', 'drum', 'drums', 'flute', 'cello',
    'trumpet', 'saxophone', 'instrument', 'instruments', 'music',
    'musical', 'song', 'songs', 'melody', 'band', 'concert', 'orchestra',
    'chord', 'chords', 'note', 'notes', 'radio', 'record',
  };

  static const Set<String> _difficultyContextTokens = <String>{
    'exam', 'exams', 'test', 'tests', 'question', 'questions', 'problem',
    'problems', 'task', 'tasks', 'work', 'job', 'life', 'decision',
    'choice', 'learn', 'learning', 'understand', 'solve', 'find', 'time',
    'language', 'math', 'course', 'class', 'challenge', 'challenging',
  };

  final http.Client _httpClient;
  final bool _ownsClient;

  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    final normalizedWord = word.trim().replaceAll('İ', 'i').toLowerCase();
    final normalizedContext = _normalizeContext(contextSentence);

    final dictAnalysis = await _analyzeWithFreeDictionary(
      word: normalizedWord,
      contextSentence: normalizedContext,
    );

    final lemma = dictAnalysis.lemma;
    final pos = dictAnalysis.partOfSpeech ??
        _inferPartOfSpeechFromContext(normalizedWord, normalizedContext);

    final queryText = _buildContextualQuery(
      lemma: lemma,
      partOfSpeech: pos,
      contextSentence: normalizedContext,
    );

    final rawTranslations = await _translateWithMyMemory(queryText);
    final entries = <MeaningEntry>[];
    final seen = <String>{};

    for (final raw in rawTranslations) {
      final cleaned = TurkishInfinitiveNormalizer.normalize(
        raw,
        isVerb: pos == WordPartOfSpeech.verb,
      );
      if (cleaned.isEmpty || !seen.add(cleaned)) continue;
      // Çok uzun cümle parçalarını sözlük anlamı olarak alma.
      if (cleaned.split(' ').length > 3) continue;

      entries.add(
        MeaningEntry(
          translation: cleaned,
          partOfSpeech: pos,
          isContextual: entries.isEmpty,
        ),
      );
      if (entries.length >= WordMeaning.maxEntries) break;
    }

    if (entries.isEmpty) {
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'Bu kelime için anlam bulunamadı. Tekrar deneyin.',
      );
    }

    return WordMeaning.fromEntries(
      word: normalizedWord,
      entries: entries,
      contextSentence: normalizedContext,
    );
  }

  Future<_DictionaryAnalysis> _analyzeWithFreeDictionary({
    required String word,
    required String? contextSentence,
  }) async {
    final candidates = _buildLemmaCandidates(word);

    for (final candidate in candidates) {
      final entries = await _fetchDictionaryEntries(candidate);
      if (entries == null || entries.isEmpty) continue;

      final pos = _selectBestPartOfSpeech(
        word: word,
        entries: entries,
        contextSentence: contextSentence,
      );

      return _DictionaryAnalysis(
        lemma: candidate,
        partOfSpeech: pos,
      );
    }

    return _DictionaryAnalysis(lemma: word, partOfSpeech: null);
  }

  Future<List<_DictionarySenseGroup>?> _fetchDictionaryEntries(
    String term,
  ) async {
    if (term.contains(' ')) return null;

    final uri = Uri.parse(
      '${ApiConfig.freeDictionaryBaseUrl}/${Uri.encodeComponent(term)}',
    );

    try {
      final response =
          await _httpClient.get(uri).timeout(ApiConfig.requestTimeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! List<Object?>) return null;

      final Map<WordPartOfSpeech, List<String>> grouped =
          <WordPartOfSpeech, List<String>>{};

      for (final entry in decoded) {
        if (entry is! Map<String, Object?>) continue;
        final meanings = entry['meanings'];
        if (meanings is! List<Object?>) continue;

        for (final meaning in meanings) {
          if (meaning is! Map<String, Object?>) continue;
          final pos = WordPartOfSpeech.tryParse(
            meaning['partOfSpeech'] as String?,
          );
          if (pos == null) continue;

          final texts = grouped.putIfAbsent(pos, () => <String>[]);
          final definitions = meaning['definitions'];
          if (definitions is List<Object?>) {
            for (final def in definitions) {
              if (def is! Map<String, Object?>) continue;
              final definitionText = def['definition'];
              if (definitionText is String && definitionText.isNotEmpty) {
                texts.add(definitionText);
              }
              final exampleText = def['example'];
              if (exampleText is String && exampleText.isNotEmpty) {
                texts.add(exampleText);
              }
            }
          }
        }
      }

      if (grouped.isEmpty) return null;

      return grouped.entries
          .map(
            (e) => _DictionarySenseGroup(
              partOfSpeech: e.key,
              texts: e.value,
            ),
          )
          .toList();
    } catch (_) {
      // Sözlük servisi geçici olarak erişilemezse çeviri akışını kesme.
      return null;
    }
  }

  WordPartOfSpeech _selectBestPartOfSpeech({
    required String word,
    required List<_DictionarySenseGroup> entries,
    required String? contextSentence,
  }) {
    if (entries.length == 1) {
      return entries.first.partOfSpeech;
    }

    final contextTokens = _tokenize(contextSentence ?? '');
    final prevToken = _findPreviousToken(word, contextSentence);

    WordPartOfSpeech bestPos = entries.first.partOfSpeech;
    int bestScore = -1;

    for (final group in entries) {
      var score = 0;

      // 1) Söz dizimsel bağlam puanı
      score += _syntaxScore(
        word: word,
        prevToken: prevToken,
        candidate: group.partOfSpeech,
      );

      // 2) Cümle kelimeleri ile sözlük tanım/örnek örtüşme puanı
      if (contextTokens.isNotEmpty) {
        final senseTokens = <String>{};
        for (final text in group.texts.take(6)) {
          senseTokens.addAll(_tokenize(text));
        }

        var overlap = 0;
        for (final token in contextTokens) {
          if (token != word && senseTokens.contains(token)) {
            overlap++;
          }
        }
        score += overlap.clamp(0, 6) * 2;
      }

      if (score > bestScore) {
        bestScore = score;
        bestPos = group.partOfSpeech;
      }
    }

    return bestPos;
  }

  WordPartOfSpeech? _inferPartOfSpeechFromContext(
    String word,
    String? contextSentence,
  ) {
    final prevToken = _findPreviousToken(word, contextSentence);
    final candidates = <WordPartOfSpeech>[
      WordPartOfSpeech.verb,
      WordPartOfSpeech.adjective,
      WordPartOfSpeech.adverb,
      WordPartOfSpeech.noun,
    ];

    WordPartOfSpeech? best;
    var bestScore = 0;

    for (final candidate in candidates) {
      final score = _syntaxScore(
        word: word,
        prevToken: prevToken,
        candidate: candidate,
      );
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  int _syntaxScore({
    required String word,
    required String? prevToken,
    required WordPartOfSpeech candidate,
  }) {
    var score = 0;

    switch (candidate) {
      case WordPartOfSpeech.verb:
        if (prevToken != null && _verbBeforeCues.contains(prevToken)) {
          score += 6;
        }
        if (word.endsWith('ing')) {
          score += prevToken != null && _copulaCues.contains(prevToken) ? 6 : 2;
        } else if (word.endsWith('ed')) {
          score += 3;
        }
      case WordPartOfSpeech.noun:
        if (prevToken != null && _nounBeforeCues.contains(prevToken)) {
          score += 5;
        }
      case WordPartOfSpeech.adjective:
        if (prevToken != null && _adjectiveBeforeCues.contains(prevToken)) {
          score += 6;
        } else if (prevToken != null &&
            _copulaCues.contains(prevToken) &&
            !word.endsWith('ing')) {
          score += 4;
        }
      case WordPartOfSpeech.adverb:
        if (word.endsWith('ly') && word.length > 4) {
          score += 6;
        }
    }

    return score;
  }

  String _buildContextualQuery({
    required String lemma,
    required WordPartOfSpeech? partOfSpeech,
    required String? contextSentence,
  }) {
    final contextTokens = _tokenize(contextSentence ?? '');

    // Yüksek frekanslı çok anlamlı kelimelerde bağlam ipucuyla doğru anlamı yönlendir.
    if (lemma == 'hard' && partOfSpeech == WordPartOfSpeech.adjective) {
      if (contextTokens.any(_difficultyContextTokens.contains)) {
        return 'difficult';
      }
    }

    if (lemma == 'play' && partOfSpeech == WordPartOfSpeech.verb) {
      if (contextTokens.any(_musicContextTokens.contains)) {
        return 'to play instrument';
      }
      return 'to play';
    }

    if (partOfSpeech == WordPartOfSpeech.verb) {
      return 'to $lemma';
    }

    return lemma;
  }

  Future<List<String>> _translateWithMyMemory(String query) async {
    final uri = Uri.parse(ApiConfig.myMemoryBaseUrl).replace(
      queryParameters: <String, String>{
        'q': query,
        'langpair': 'en|tr',
      },
    );

    final http.Response response;
    try {
      response = await _httpClient.get(uri).timeout(ApiConfig.requestTimeout);
    } on TimeoutException {
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'Anlam sorgusu zaman aşımına uğradı. Tekrar deneyin.',
      );
    } on SocketException {
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'İnternet bağlantısı kurulamadı.',
      );
    } on http.ClientException {
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'Ücretsiz çeviri servisine bağlanılamadı.',
      );
    }

    if (response.statusCode == 429) {
      throw const TranslationException(
        type: TranslationErrorType.rateLimited,
        message: 'Ücretsiz çeviri limiti geçici olarak doldu. Biraz sonra tekrar deneyin.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TranslationException(
        type: TranslationErrorType.unknown,
        message: 'Çeviri servisi yanıt vermedi (HTTP ${response.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, Object?>;
      final results = <String>[];

      final responseData = decoded['responseData'] as Map<String, Object?>?;
      final translatedText = responseData?['translatedText'] as String?;

      final cleanedPrimary = _extractCleanMyMemoryText(
        translatedText,
        originalQuery: query,
      );
      if (cleanedPrimary != null) {
        results.add(cleanedPrimary);
      }

      final matches = decoded['matches'];
      if (matches is List<Object?>) {
        for (final match in matches) {
          if (match is! Map<String, Object?>) continue;
          final candidate = _extractCleanMyMemoryText(
            match['translation'] as String?,
            originalQuery: query,
          );
          if (candidate != null) {
            results.add(candidate);
          }
        }
      }

      if (results.isEmpty) {
        throw const FormatException('No usable translation found');
      }

      return results;
    } catch (_) {
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'Anlam yanıtı okunamadı. Lütfen tekrar deneyin.',
      );
    }
  }

  String? _extractCleanMyMemoryText(
    String? raw, {
    required String originalQuery,
  }) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toUpperCase().startsWith('MYMEMORY WARNING')) return null;

    // "to play instrument" -> "enstrüman çalmak" geldiyse yalın fiili al.
    if (originalQuery == 'to play instrument') {
      final lower = trimmed.replaceAll('İ', 'i').toLowerCase();
      if (lower.contains('çalmak')) return 'çalmak';
    }

    return trimmed;
  }

  List<String> _buildLemmaCandidates(String word) {
    final candidates = <String>[word];
    if (word.contains(' ') || word.length <= 3) return candidates;

    if (word.endsWith('ies') && word.length > 4) {
      candidates.add('${word.substring(0, word.length - 3)}y');
    }
    if (word.endsWith('ied') && word.length > 4) {
      candidates.add('${word.substring(0, word.length - 3)}y');
    }
    if (word.endsWith('ing') && word.length > 5) {
      final stem = word.substring(0, word.length - 3);
      candidates.add(stem);
      candidates.add('${stem}e');
      if (stem.length >= 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        candidates.add(stem.substring(0, stem.length - 1));
      }
    }
    if (word.endsWith('ed') && word.length > 4) {
      final stem = word.substring(0, word.length - 2);
      candidates.add(stem);
      candidates.add('${stem}e');
      if (stem.length >= 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        candidates.add(stem.substring(0, stem.length - 1));
      }
    }
    if (word.endsWith('es') && word.length > 4) {
      candidates.add(word.substring(0, word.length - 2));
    }
    if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
      candidates.add(word.substring(0, word.length - 1));
    }

    return candidates.toSet().toList();
  }

  String? _findPreviousToken(String word, String? sentence) {
    if (sentence == null || sentence.isEmpty) return null;
    final words = RegExp(r"[a-zA-Z']+")
        .allMatches(sentence.toLowerCase())
        .map((m) => m.group(0)!.replaceAll("'", ''))
        .toList();

    final index = words.indexOf(word.replaceAll("'", ''));
    if (index <= 0) return null;
    return words[index - 1];
  }

  Set<String> _tokenize(String text) {
    if (text.isEmpty) return const <String>{};
    return RegExp(r'[a-zA-Z]{4,}')
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .where((token) => !_stopWords.contains(token))
        .toSet();
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

class _DictionaryAnalysis {
  const _DictionaryAnalysis({
    required this.lemma,
    required this.partOfSpeech,
  });

  final String lemma;
  final WordPartOfSpeech? partOfSpeech;
}

class _DictionarySenseGroup {
  const _DictionarySenseGroup({
    required this.partOfSpeech,
    required this.texts,
  });

  final WordPartOfSpeech partOfSpeech;
  final List<String> texts;
}
