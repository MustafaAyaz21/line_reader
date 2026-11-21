import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/word_meaning.dart';
import '../utils/turkish_infinitive_normalizer.dart';
import 'word_translation_service.dart';

/// Hiçbir API anahtarı veya ücretli abonelik gerektirmeyen, tamamen ücretsiz
/// bağlam duyarlı çeviri ve iki dilli sözlük servisi.
///
/// Çalışma mantığı:
/// 1. Kelimenin (ve gerekirse kökünün) iki dilli sözlük girdilerini sözcük türüne
///    (`noun`, `verb`, `adjective`, `adverb`) göre mastar/sözlük başlığı halinde alır.
/// 2. Bağlam cümlesini Türkçeye çevirerek cümlede gerçekten kullanılan anlamı
///    Türkçe kök/gövde eşleştirmesi ve söz dizimi puanlamasıyla seçer.
///    (Örn. "She plays the piano" -> "çalmak (verb)", "This exam is hard" -> "zor (adjective)").
/// 3. Fiiller her zaman sözlük mastar (`-mak/-mek`) biçiminde döndürülür.
class ContextualFreeTranslationService implements WordTranslationService {
  ContextualFreeTranslationService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const Set<String> _englishStopWords = <String>{
    'this', 'that', 'these', 'those', 'with', 'from', 'into', 'about',
    'there', 'their', 'they', 'them', 'were', 'have', 'been', 'will',
    'would', 'could', 'should', 'what', 'when', 'where', 'which', 'while',
    'your', 'ours', 'just', 'very', 'more', 'most', 'some', 'such', 'than',
    'then', 'also', 'only', 'over', 'under', 'after', 'before', 'because',
  };

  /// Cümlede başka kelimeden (örn. "very" -> "çok") gelebilecek genel işlev
  /// kelimeleri için yanlış pozitif eşleşme puanını düşük tut.
  static const Set<String> _commonTurkishFunctionWords = <String>{
    'çok', 'bir', 'bu', 'şu', 'o', 've', 'ile', 'için', 'daha', 'en',
    'da', 'de', 'ki', 'mi', 'mı', 'mu', 'mü', 'ne', 'ama', 'fakat',
  };

  static const Set<String> _verbBeforeCues = <String>{
    'to', 'will', 'would', 'can', 'could', 'shall', 'should', 'may',
    'might', 'must', 'do', 'does', 'did', 'dont', 'doesnt', 'didnt',
    'cant', 'wont', 'shouldnt', 'wouldnt', 'never', 'always',
    'i', 'you', 'he', 'she', 'it', 'we', 'they',
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

  static const List<String> _shortVerbSuffixes = <String>[
    'iyor', 'ıyor', 'uyor', 'üyor',
    'ecek', 'acak',
    'mekte', 'makta',
    'meli', 'malı',
    'miş', 'mış', 'muş', 'müş',
    'di', 'dı', 'du', 'dü', 'ti', 'tı', 'tu', 'tü',
    'er', 'ar', 'ir', 'ır', 'ur', 'ür',
    'en', 'an', 'ip', 'ıp', 'up', 'üp',
    'erek', 'arak', 'mek', 'mak',
  ];

  final http.Client _httpClient;
  final bool _ownsClient;

  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    final normalizedWord = word.trim().replaceAll('İ', 'i').toLowerCase();
    final normalizedContext = _normalizeContext(contextSentence);

    // İki dilli sözlük sorgusu ile bağlam cümlesi çevirisini paralel çalıştır.
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _fetchBilingualEntriesWithLemmaFallback(normalizedWord),
      normalizedContext != null
          ? _fetchSentenceTranslation(normalizedContext)
          : Future<String?>.value(null),
    ]);

    final dictionaryResult = results[0] as _BilingualLookupResult;
    final translatedSentence = results[1] as String?;

    if (dictionaryResult.candidates.isNotEmpty) {
      final best = _pickBestCandidate(
        word: normalizedWord,
        candidates: dictionaryResult.candidates,
        contextSentence: normalizedContext,
        translatedSentence: translatedSentence,
      );

      final entries = _buildRankedEntries(
        primary: best,
        allCandidates: dictionaryResult.candidates,
      );

      if (entries.isNotEmpty) {
        return WordMeaning.fromEntries(
          word: normalizedWord,
          entries: entries,
          contextSentence: normalizedContext,
        );
      }
    }

    // Sözlük listesi boşsa (ör. nadir kelime veya deyimsel ifade) doğrudan çeviri al.
    final inferredPos = _inferPosFromSyntax(normalizedWord, normalizedContext);
    final query = inferredPos == WordPartOfSpeech.verb
        ? 'to ${dictionaryResult.lemma}'
        : normalizedWord;
    final directTranslation = await _fetchDirectTranslation(query);
    final cleanedDirect = TurkishInfinitiveNormalizer.normalize(
      directTranslation,
      isVerb: inferredPos == WordPartOfSpeech.verb,
    );

    if (cleanedDirect.isEmpty) {
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'Bu kelime için anlam bulunamadı.',
      );
    }

    return WordMeaning.fromEntries(
      word: normalizedWord,
      entries: <MeaningEntry>[
        MeaningEntry(
          translation: cleanedDirect,
          partOfSpeech: inferredPos,
          isContextual: true,
        ),
      ],
      contextSentence: normalizedContext,
    );
  }

  Future<_BilingualLookupResult> _fetchBilingualEntriesWithLemmaFallback(
    String word,
  ) async {
    final candidates = _buildLemmaCandidates(word);
    String bestLemma = word;

    for (final term in candidates) {
      final response = await _requestTranslateEndpoint(
        query: term,
        includeDictionary: true,
      );
      final parsed = _parseBilingualCandidates(response);
      if (parsed.isNotEmpty) {
        bestLemma = term;
        return _BilingualLookupResult(lemma: bestLemma, candidates: parsed);
      }
    }

    return _BilingualLookupResult(
      lemma: bestLemma,
      candidates: const <_DictionaryCandidate>[],
    );
  }

  Future<String?> _fetchSentenceTranslation(String sentence) async {
    try {
      final response = await _requestTranslateEndpoint(
        query: sentence,
        includeDictionary: false,
      );
      return _extractTranslatedText(response);
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchDirectTranslation(String query) async {
    final response = await _requestTranslateEndpoint(
      query: query,
      includeDictionary: false,
    );
    return _extractTranslatedText(response) ?? '';
  }

  Future<List<Object?>> _requestTranslateEndpoint({
    required String query,
    required bool includeDictionary,
  }) async {
    final queryParts = <String>[
      'client=gtx',
      'sl=en',
      'tl=tr',
      'dt=t',
      if (includeDictionary) 'dt=bd',
      'q=${Uri.encodeQueryComponent(query)}',
    ];
    final uri = Uri.parse(
      '${ApiConfig.contextualTranslateBaseUrl}?${queryParts.join('&')}',
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
        message: 'Çeviri servisi geçici olarak yoğun. Tekrar deneyin.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TranslationException(
        type: TranslationErrorType.unknown,
        message: 'Çeviri servisi yanıt vermedi (HTTP ${response.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List<Object?>) {
        throw const FormatException('Unexpected root JSON');
      }
      return decoded;
    } catch (_) {
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'Çeviri yanıtı ayrıştırılamadı.',
      );
    }
  }

  String? _extractTranslatedText(List<Object?> root) {
    if (root.isEmpty) return null;
    final segments = root[0];
    if (segments is! List<Object?>) return null;

    final buffer = StringBuffer();
    for (final segment in segments) {
      if (segment is List<Object?> && segment.isNotEmpty) {
        final piece = segment[0];
        if (piece is String) {
          buffer.write(piece);
        }
      }
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }

  List<_DictionaryCandidate> _parseBilingualCandidates(List<Object?> root) {
    if (root.length < 2) return const <_DictionaryCandidate>[];
    final dictSection = root[1];
    if (dictSection is! List<Object?>) return const <_DictionaryCandidate>[];

    final results = <_DictionaryCandidate>[];

    for (final group in dictSection) {
      if (group is! List<Object?> || group.isEmpty) continue;
      final pos = WordPartOfSpeech.tryParse(group[0] as String?);
      if (pos == null) continue;

      final detailedEntries = group.length > 2 ? group[2] : null;
      if (detailedEntries is List<Object?> && detailedEntries.isNotEmpty) {
        var rank = 0;
        for (final entry in detailedEntries) {
          if (entry is! List<Object?> || entry.isEmpty) continue;
          final turkishTerm = entry[0];
          if (turkishTerm is! String || turkishTerm.trim().isEmpty) continue;

          final reverseGlosses = <String>[];
          if (entry.length > 1 && entry[1] is List<Object?>) {
            for (final gloss in entry[1] as List<Object?>) {
              if (gloss is String && gloss.isNotEmpty) {
                reverseGlosses.add(gloss.toLowerCase());
              }
            }
          }

          results.add(
            _DictionaryCandidate(
              turkishTerm: turkishTerm.trim(),
              partOfSpeech: pos,
              reverseGlosses: reverseGlosses,
              rank: rank,
            ),
          );
          rank++;
        }
        continue;
      }

      // Ayrıntılı liste yoksa temel terim listesini kullan.
      final simpleTerms = group.length > 1 ? group[1] : null;
      if (simpleTerms is List<Object?>) {
        var rank = 0;
        for (final term in simpleTerms) {
          if (term is String && term.trim().isNotEmpty) {
            results.add(
              _DictionaryCandidate(
                turkishTerm: term.trim(),
                partOfSpeech: pos,
                reverseGlosses: const <String>[],
                rank: rank,
              ),
            );
            rank++;
          }
        }
      }
    }

    return results;
  }

  _DictionaryCandidate _pickBestCandidate({
    required String word,
    required List<_DictionaryCandidate> candidates,
    required String? contextSentence,
    required String? translatedSentence,
  }) {
    final prevToken = _findPreviousToken(word, contextSentence);
    final contextTokens = _tokenizeEnglish(contextSentence ?? '');
    final turkishSentenceTokens = _tokenizeTurkish(translatedSentence ?? '');

    _DictionaryCandidate best = candidates.first;
    double bestScore = -1000;

    for (final candidate in candidates) {
      double score = 0;

      // 1) En güçlü bağlam sinyali: çevrilmiş cümlede bu anlamın kökü geçiyor mu?
      if (turkishSentenceTokens.isNotEmpty &&
          _matchesTranslatedSentence(candidate, turkishSentenceTokens)) {
        final lowerTerm =
            candidate.turkishTerm.replaceAll('İ', 'i').toLowerCase();
        score += _commonTurkishFunctionWords.contains(lowerTerm) ? 2.0 : 14.0;
      }

      // 2) Cümle içindeki söz dizimine göre sözcük türü puanı
      score += _syntaxScore(
        word: word,
        prevToken: prevToken,
        candidate: candidate.partOfSpeech,
      );

      // 3) Ters İngilizce anlam ipuçlarıyla bağlam cümlesi örtüşmesi
      if (contextTokens.isNotEmpty && candidate.reverseGlosses.isNotEmpty) {
        var overlap = 0;
        for (final gloss in candidate.reverseGlosses) {
          for (final token in _tokenizeEnglish(gloss)) {
            if (token != word && contextTokens.contains(token)) {
              overlap++;
            }
          }
        }
        score += overlap.clamp(0, 4) * 2.0;
      }

      // 4) Sözlük kullanım sıklığı sırası (eşitlik bozucu)
      score += (6 - candidate.rank).clamp(0, 6) * 0.45;

      // Kısa ve yalın sözlük karşılıklarını uzun ifadelere tercih et.
      if (!candidate.turkishTerm.contains(' ')) {
        score += 0.6;
      }

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best;
  }

  /// 1. sıraya bağlamdaki anlamı yerleştirir; 2, 3 ve 4. sıralara sözlükteki
  /// en sık kullanılan diğer tekrarsız anlamları ekler.
  List<MeaningEntry> _buildRankedEntries({
    required _DictionaryCandidate primary,
    required List<_DictionaryCandidate> allCandidates,
  }) {
    final primaryTranslation = TurkishInfinitiveNormalizer.normalize(
      primary.turkishTerm,
      isVerb: primary.partOfSpeech == WordPartOfSpeech.verb,
    );
    if (primaryTranslation.isEmpty) {
      return const <MeaningEntry>[];
    }

    final entries = <MeaningEntry>[
      MeaningEntry(
        translation: primaryTranslation,
        partOfSpeech: primary.partOfSpeech,
        isContextual: true,
      ),
    ];
    final seen = <String>{primaryTranslation};

    // Diğer adayları sıklık sırasına göre sırala (aynı sırada kısa/yalın karşılık öncelikli).
    final others = allCandidates.where((c) => !identical(c, primary)).toList()
      ..sort((a, b) {
        final rankCompare = a.rank.compareTo(b.rank);
        if (rankCompare != 0) return rankCompare;
        final aMulti = a.turkishTerm.contains(' ') ? 1 : 0;
        final bMulti = b.turkishTerm.contains(' ') ? 1 : 0;
        return aMulti.compareTo(bMulti);
      });

    for (final candidate in others) {
      if (entries.length >= WordMeaning.maxEntries) break;
      final normalized = TurkishInfinitiveNormalizer.normalize(
        candidate.turkishTerm,
        isVerb: candidate.partOfSpeech == WordPartOfSpeech.verb,
      );
      if (normalized.isEmpty || !seen.add(normalized)) continue;

      entries.add(
        MeaningEntry(
          translation: normalized,
          partOfSpeech: candidate.partOfSpeech,
          isContextual: false,
        ),
      );
    }

    return entries;
  }

  bool _matchesTranslatedSentence(
    _DictionaryCandidate candidate,
    List<String> sentenceTokens,
  ) {
    final normalized = TurkishInfinitiveNormalizer.normalize(
      candidate.turkishTerm,
      isVerb: candidate.partOfSpeech == WordPartOfSpeech.verb,
    );
    if (normalized.isEmpty) return false;

    final parts = normalized.split(' ');
    final keyTerm = parts.last;
    final stems = _buildTurkishStems(
      keyTerm,
      isVerb: candidate.partOfSpeech == WordPartOfSpeech.verb,
    );

    for (final stem in stems) {
      for (final token in sentenceTokens) {
        if (token == stem) return true;
        if (stem.length >= 3 && token.startsWith(stem)) {
          return true;
        }
        if (stem.length == 2 &&
            candidate.partOfSpeech == WordPartOfSpeech.verb &&
            token.startsWith(stem)) {
          final remainder = token.substring(stem.length);
          if (_shortVerbSuffixes.any(remainder.startsWith)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  List<String> _buildTurkishStems(String term, {required bool isVerb}) {
    final stems = <String>{term};
    var base = term;

    if (isVerb && (term.endsWith('mak') || term.endsWith('mek')) && term.length > 4) {
      base = term.substring(0, term.length - 3);
      stems.add(base);

      // Ünlü daralması (oynamak -> oyna -> oyn[uyor], beklemek -> bekle -> bekl[iyor])
      if (base.length >= 4 && (base.endsWith('a') || base.endsWith('e'))) {
        stems.add(base.substring(0, base.length - 1));
      }
    }

    // Ünsüz yumuşaması (gitmek -> gid[iyor], kitap -> kitab[ı], ağaç -> ağac[ı])
    if (base.length >= 2) {
      final softened = _softenFinalConsonant(base);
      if (softened != null) {
        stems.add(softened);
      }
    }

    return stems.toList();
  }

  String? _softenFinalConsonant(String stem) {
    final last = stem[stem.length - 1];
    final prefix = stem.substring(0, stem.length - 1);
    return switch (last) {
      't' => '${prefix}d',
      'p' => '${prefix}b',
      'ç' => '${prefix}c',
      'k' => '${prefix}ğ',
      _ => null,
    };
  }

  WordPartOfSpeech? _inferPosFromSyntax(String word, String? contextSentence) {
    final prevToken = _findPreviousToken(word, contextSentence);
    final candidates = <WordPartOfSpeech>[
      WordPartOfSpeech.verb,
      WordPartOfSpeech.adjective,
      WordPartOfSpeech.adverb,
      WordPartOfSpeech.noun,
    ];

    WordPartOfSpeech? best;
    double bestScore = 0;

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

  double _syntaxScore({
    required String word,
    required String? prevToken,
    required WordPartOfSpeech candidate,
  }) {
    double score = 0;

    switch (candidate) {
      case WordPartOfSpeech.verb:
        if (prevToken != null && _verbBeforeCues.contains(prevToken)) {
          score += 6;
        }
        if (word.endsWith('ing')) {
          score += prevToken != null && _copulaCues.contains(prevToken) ? 8 : 3;
        } else if (word.endsWith('ed')) {
          score += 4;
        }
      case WordPartOfSpeech.noun:
        if (prevToken != null && _nounBeforeCues.contains(prevToken)) {
          score += 6;
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
      case WordPartOfSpeech.phrase:
      case WordPartOfSpeech.idiom:
      case WordPartOfSpeech.preposition:
      case WordPartOfSpeech.conjunction:
        break;
    }

    return score;
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

  Set<String> _tokenizeEnglish(String text) {
    if (text.isEmpty) return const <String>{};
    return RegExp(r'[a-zA-Z]{4,}')
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .where((token) => !_englishStopWords.contains(token))
        .toSet();
  }

  List<String> _tokenizeTurkish(String text) {
    if (text.isEmpty) return const <String>[];
    final normalized = text.replaceAll('İ', 'i').toLowerCase();
    return RegExp(r'[\p{L}\p{M}]+', unicode: true)
        .allMatches(normalized)
        .map((m) => m.group(0)!)
        .toList();
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

class _BilingualLookupResult {
  const _BilingualLookupResult({
    required this.lemma,
    required this.candidates,
  });

  final String lemma;
  final List<_DictionaryCandidate> candidates;
}

class _DictionaryCandidate {
  const _DictionaryCandidate({
    required this.turkishTerm,
    required this.partOfSpeech,
    required this.reverseGlosses,
    required this.rank,
  });

  final String turkishTerm;
  final WordPartOfSpeech partOfSpeech;
  final List<String> reverseGlosses;
  final int rank;
}
