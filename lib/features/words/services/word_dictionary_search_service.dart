import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../translation/models/word_lexicon_info.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/services/local_dictionary_service.dart';
import '../../translation/services/word_lexicon_service.dart';
import '../../translation/services/word_translation_service.dart';
import '../../translation/utils/turkish_infinitive_normalizer.dart';
import '../models/word_search_detail.dart';

/// Manuel kelime ekleme ekranı için kapsamlı sözlük arama servisi.
///
/// - Kullanıcının doğrulanmış Gemini API anahtarı varsa doğrudan 12–15 farklı
///   Türkçe anlam ve 3 kısa örnek cümle (çevirileriyle) üretir.
/// - API anahtarı yoksa (veya Gemini 10'dan az anlam dönerse) ücretsiz çoklu
///   sözlük kaynaklarını (`translate.googleapis.com` `dt=bd,at,ex` +
///   `dictionaryapi.dev` eşanlamlılar/örnekler) paralel sorgulayarak 10–15
///   farklı Türkçe anlam ve 3 kısa örnek cümle oluşturur.
class WordDictionarySearchService {
  WordDictionarySearchService({
    String? Function()? geminiApiKeyProvider,
    bool Function()? shouldAttemptGeminiProvider,
    http.Client? httpClient,
    LocalDictionaryService? localDictionary,
    WordLexiconService? lexiconService,
  })  : _geminiApiKeyProvider = geminiApiKeyProvider,
        _shouldAttemptGeminiProvider = shouldAttemptGeminiProvider,
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _localDictionary = localDictionary ?? LocalDictionaryService(),
        _lexiconService = lexiconService ?? WordLexiconService.shared;

  static const int _targetMinMeanings = 10;
  static const int _targetMaxMeanings = 15;
  static const int _targetExamplesCount = 3;
  static const Duration _timeout = Duration(seconds: 14);

  static const String _geminiSystemPrompt = '''
You are an English-to-Turkish dictionary assistant for vocabulary learners.
Given an English word or short expression, return:
1. "meanings": 12 to 15 distinct Turkish dictionary meanings/senses ordered from most common to more specific/figurative/collocational usages.
   - Never repeat the same Turkish meaning.
   - For verbs, ALWAYS use the plain Turkish infinitive (mastar) ending in -mak/-mek (e.g. "koşmak", "çalıştırmak", "yönetmek").
   - Keep each "meaning" concise (1 to 3 Turkish words, lowercase dictionary form, no parentheses).
   - Set "partOfSpeech" to strictly one of: "noun", "verb", "adjective", "adverb", or null.
2. "examples": EXACTLY 3 natural, meaningful, real-life English example sentences using the target word or expression (each 10 to 18 words, strictly between 8 and 22 words, in varied everyday contexts), together with a fluent Turkish translation.

Respond ONLY with valid JSON:
{
  "meanings": [{"meaning": "<turkish>", "partOfSpeech": "<noun|verb|adjective|adverb|null>"}],
  "examples": [{"english": "<short english sentence>", "turkish": "<turkish translation>"}]
}
''';

  final String? Function()? _geminiApiKeyProvider;
  final bool Function()? _shouldAttemptGeminiProvider;
  final http.Client _httpClient;
  final bool _ownsClient;
  final LocalDictionaryService _localDictionary;
  final WordLexiconService _lexiconService;
  String? _activeGeminiModel;

  /// Verilen İngilizce kelime için 10–15 farklı anlam ve 3 kısa örnek cümle getirir.
  Future<WordSearchDetail> searchWord(String rawQuery) async {
    final normalizedWord = _normalizeEnglishQuery(rawQuery);
    if (normalizedWord.isEmpty) {
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'Lütfen geçerli bir İngilizce kelime yazın.',
      );
    }

    final collectedMeanings = <MeaningEntry>[];
    final seenMeanings = <String>{};
    final collectedExamples = <WordExampleSentence>[];
    final seenExamples = <String>{};

    void addMeaning(MeaningEntry entry) {
      if (collectedMeanings.length >= _targetMaxMeanings) return;
      final normalized = TurkishInfinitiveNormalizer.normalize(
        entry.translation,
        isVerb: entry.partOfSpeech == WordPartOfSpeech.verb,
      ).trim();
      if (normalized.isEmpty) return;

      final key = normalized.replaceAll('İ', 'i').toLowerCase();
      if (!seenMeanings.add(key)) return;

      collectedMeanings.add(
        MeaningEntry(
          translation: normalized,
          partOfSpeech: entry.partOfSpeech,
          isContextual: false,
        ),
      );
    }

    void addExample(WordExampleSentence example) {
      if (collectedExamples.length >= _targetExamplesCount) return;
      final cleanEn = _cleanSentence(example.english);
      if (cleanEn.isEmpty) return;

      final key = cleanEn.toLowerCase();
      if (!seenExamples.add(key)) return;

      final cleanTr = example.turkish?.trim();
      collectedExamples.add(
        WordExampleSentence(
          english: cleanEn,
          turkish: (cleanTr != null && cleanTr.isNotEmpty) ? cleanTr : null,
        ),
      );
    }

    // 1) Doğrulanmış Gemini API anahtarı varsa önce yüksek kaliteli 12–15 anlam + 3 örnek al.
    final apiKey = _geminiApiKeyProvider?.call()?.trim() ?? '';
    final canUseGemini =
        apiKey.isNotEmpty && (_shouldAttemptGeminiProvider?.call() ?? true);

    if (canUseGemini) {
      final geminiDetail = await _tryFetchFromGemini(
        apiKey: apiKey,
        word: normalizedWord,
      );
      if (geminiDetail != null) {
        for (final m in geminiDetail.meanings) {
          addMeaning(m);
        }
        for (final ex in geminiDetail.examples) {
          addExample(ex);
        }
      }
    }

    TranslationException? onlineError;
    final isSingleWord = !normalizedWord.contains(' ') &&
        RegExp(r'^[a-zA-Z]+$').hasMatch(normalizedWord);
    WordLexiconInfo? lexiconInfo;

    // 2) Anlam sayısı < 10 veya örnek < 3 ise ücretsiz çoklu kaynaklardan tamamla.
    if (collectedMeanings.length < _targetMinMeanings ||
        collectedExamples.length < _targetExamplesCount) {
      try {
        final freeResults = await Future.wait<Object?>(<Future<Object?>>[
          _fetchGoogleBilingualBundle(normalizedWord),
          _fetchFreeDictionaryBundle(normalizedWord),
          if (isSingleWord) _localDictionary.lookup(normalizedWord) else Future<Object?>.value(null),
          if (isSingleWord) _lexiconService.hasKnownEnglishWord(normalizedWord) else Future<Object?>.value(true),
        ]);

        final googleBundle = freeResults[0] as _GoogleDictionaryBundle?;
        final dictBundle = freeResults[1] as _EnglishDictBundle?;
        final earlyLocal = freeResults[2] as LocalDictionaryLookupResult?;
        final knownInLexicon = (freeResults[3] as bool?) ?? false;

        // Tek kelimede yazım hatası / geçersiz kelime kontrolü ("elone" -> "alone"):
        // Gerçek İngilizce sözlüklerin hiçbirinde yoksa veya Google açık yazım
        // düzeltmesi (`dt=qca`) döndüyse uydurma çeviri üretme; "Bunu mu aratmak istediniz?" dön!
        final googleSuggestion = googleBundle?.didYouMean;
        final hasSuggestionFromGoogle = googleSuggestion != null &&
            googleSuggestion.isNotEmpty &&
            googleSuggestion != normalizedWord;
        final hasBilingualDict = googleBundle?.hasBilingualDict ?? false;
        final isValidKnownWord = dictBundle != null ||
            hasBilingualDict ||
            earlyLocal != null ||
            knownInLexicon;

        if (isSingleWord &&
            (!isValidKnownWord ||
                (hasSuggestionFromGoogle &&
                    dictBundle == null &&
                    !hasBilingualDict))) {
          final suggestions = await _collectSpellingSuggestions(
            query: normalizedWord,
            googleSuggestion: googleSuggestion,
          );
          if (suggestions.isNotEmpty || !isValidKnownWord) {
            return WordSearchDetail(
              word: normalizedWord,
              meanings: const <MeaningEntry>[],
              examples: const <WordExampleSentence>[],
              isMisspelled: true,
              suggestions: suggestions,
            );
          }
        }

        if (googleBundle != null) {
          for (final m in googleBundle.meanings) {
            addMeaning(m);
          }
        }

        // Hâlâ 10'dan az anlam varsa İngilizce eşanlamlılar ve sözcük türü varyasyonlarını çevir
        // (yalnızca geçerli olduğu doğrulanan kelimelerde!).
        if (collectedMeanings.length < _targetMinMeanings) {
          final extraTerms = <String>[
            if (dictBundle != null) ...dictBundle.synonyms,
            if (!normalizedWord.contains(' ') && isValidKnownWord) ...<String>[
              'to $normalizedWord',
              'a $normalizedWord',
              'very $normalizedWord',
            ],
            if (dictBundle != null) ...dictBundle.shortDefinitions,
          ];
          final extraMeanings = await _translateBatchTerms(
            terms: extraTerms,
            defaultPos: collectedMeanings.isNotEmpty
                ? collectedMeanings.first.partOfSpeech
                : dictBundle?.primaryPos,
            limit: (_targetMaxMeanings - collectedMeanings.length).clamp(0, 15),
          );
          for (final m in extraMeanings) {
            addMeaning(m);
          }
        }

        // Örnek cümleleri topla (öncelik: 1) Worker AI + D1 önbellek,
        // 2) Tatoeba insan çevirili korpus, 3) Sözlüklerden 8-22 kelimelik tam cümleler).
        if (collectedExamples.length < _targetExamplesCount) {
          final richResults = await Future.wait<List<WordExampleSentence>>(
            <Future<List<WordExampleSentence>>>[
              _fetchWorkerExamples(normalizedWord),
              _fetchTatoebaExamples(normalizedWord),
            ],
          );

          final workerExamples = richResults[0];
          final tatoebaExamples = richResults[1];

          for (final ex in workerExamples) {
            if (_isQualityExampleSentence(ex.english, normalizedWord)) {
              addExample(ex);
            }
          }

          if (collectedExamples.length < _targetExamplesCount &&
              tatoebaExamples.isNotEmpty) {
            final rankedTatoeba = tatoebaExamples
                .where(
                  (ex) => _isQualityExampleSentence(ex.english, normalizedWord),
                )
                .toList()
              ..sort(
                (a, b) => _scoreExampleSentence(b.english)
                    .compareTo(_scoreExampleSentence(a.english)),
              );
            for (final ex in rankedTatoeba) {
              addExample(ex);
            }
          }
        }

        // Hâlâ 3 örneğe ulaşmadıysa sözlük kaynaklarından 8–22 kelimelik
        // tam cümleleri (kısa öbekleri eleyerek) kalite sırasına göre seç.
        final rawEnglishExamples = <String>[];
        if (dictBundle != null) {
          rawEnglishExamples.addAll(dictBundle.examples);
        }
        if (googleBundle != null) {
          rawEnglishExamples.addAll(googleBundle.examples);
        }

        rawEnglishExamples.sort(
          (a, b) => _scoreExampleSentence(b).compareTo(_scoreExampleSentence(a)),
        );
        final chosenEnglish = <String>[];
        final chosenKeys = <String>{
          ...collectedExamples.map((e) => e.english.toLowerCase()),
        };

        for (final candidate in rawEnglishExamples) {
          if (collectedExamples.length + chosenEnglish.length >=
              _targetExamplesCount) {
            break;
          }
          final clean = _cleanSentence(candidate);
          if (!_isQualityExampleSentence(clean, normalizedWord)) continue;
          if (chosenKeys.add(clean.toLowerCase())) {
            chosenEnglish.add(clean);
          }
        }

        // 3 örneğe hâlâ ulaşmadıysa (ör. çevrimdışı) 10–16 kelimelik doğal yedeklerle tamamla.
        final neededExamples = _targetExamplesCount -
            (collectedExamples.length + chosenEnglish.length);
        if (neededExamples > 0) {
          final primaryPos = collectedMeanings.isNotEmpty
              ? collectedMeanings.first.partOfSpeech
              : dictBundle?.primaryPos;
          final fallbackSentences = _buildFallbackShortExamples(
            word: normalizedWord,
            pos: primaryPos,
          );
          for (final sentence in fallbackSentences) {
            if (collectedExamples.length + chosenEnglish.length >=
                _targetExamplesCount) {
              break;
            }
            if (chosenKeys.add(sentence.toLowerCase())) {
              chosenEnglish.add(sentence);
            }
          }
        }

        if (chosenEnglish.isNotEmpty) {
          final translatedExamples =
              await _translateSentencesBatch(chosenEnglish);
          for (var i = 0; i < chosenEnglish.length; i++) {
            final tr =
                i < translatedExamples.length ? translatedExamples[i] : null;
            addExample(
              WordExampleSentence(
                english: chosenEnglish[i],
                turkish: tr,
              ),
            );
          }
        }
      } on TranslationException catch (error) {
        onlineError = error;
      } catch (error) {
        debugPrint(
          '[WordDictionarySearchService] Cevrimici arama hatasi: $error',
        );
      }
    }

    // 3) Yerel sözlük + kök/ek çözümleyici ile çevrimdışı veya eksik anlamları tamamla.
    if (collectedMeanings.length < _targetMinMeanings) {
      try {
        final localResult = await _localDictionary.lookup(normalizedWord);
        if (localResult != null) {
          for (final entry in localResult.meaning.orderedEntries) {
            addMeaning(entry);
          }
          if (collectedExamples.isEmpty) {
            final fallbackExamples = _buildFallbackShortExamples(
              word: localResult.matchedLemma,
              pos: collectedMeanings.isNotEmpty
                  ? collectedMeanings.first.partOfSpeech
                  : null,
            );
            for (final sentence in fallbackExamples) {
              addExample(WordExampleSentence(english: sentence));
            }
          }
        }
      } catch (error) {
        debugPrint(
          '[WordDictionarySearchService] Yerel sozluk arama hatasi: $error',
        );
      }
    }

    if (collectedMeanings.isEmpty) {
      if (isSingleWord) {
        final offlineSuggestions = await _collectSpellingSuggestions(
          query: normalizedWord,
          googleSuggestion: null,
        );
        if (offlineSuggestions.isNotEmpty) {
          return WordSearchDetail(
            word: normalizedWord,
            meanings: const <MeaningEntry>[],
            examples: const <WordExampleSentence>[],
            isMisspelled: true,
            suggestions: offlineSuggestions,
          );
        }
      }
      if (onlineError != null) {
        throw onlineError;
      }
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'Bu kelime için anlam bulunamadı. Farklı bir kelime deneyin.',
      );
    }

    if (isSingleWord) {
      try {
        lexiconInfo = await _lexiconService.lookup(normalizedWord);
      } catch (_) {}
    }

    return WordSearchDetail(
      word: normalizedWord,
      meanings: List<MeaningEntry>.unmodifiable(collectedMeanings),
      examples: List<WordExampleSentence>.unmodifiable(collectedExamples),
      lexiconInfo: lexiconInfo,
    );
  }

  Future<List<String>> _collectSpellingSuggestions({
    required String query,
    required String? googleSuggestion,
  }) async {
    final result = <String>[];
    final seen = <String>{query.trim().toLowerCase()};

    void addCandidate(String? raw) {
      if (raw == null) return;
      final clean = raw.trim().toLowerCase();
      if (clean.length < 2 || clean.length > 26) return;
      if (!RegExp(r'^[a-z]+(?: [a-z]+)?$').hasMatch(clean)) return;
      if (seen.add(clean)) {
        result.add(clean);
      }
    }

    addCandidate(googleSuggestion);

    final parallel = await Future.wait<List<String>>(<Future<List<String>>>[
      _fetchDatamuseSpellingSuggestions(query),
      _lexiconService.findOfflineSpellingSuggestions(query, maxSuggestions: 4),
    ]);

    for (final list in parallel) {
      for (final item in list) {
        addCandidate(item);
        if (result.length >= 4) break;
      }
      if (result.length >= 4) break;
    }

    return List<String>.unmodifiable(result.take(4));
  }

  Future<List<String>> _fetchDatamuseSpellingSuggestions(String query) async {
    try {
      final uri = Uri.parse(
        'https://api.datamuse.com/sug?s=${Uri.encodeQueryComponent(query)}&max=5',
      );
      final response =
          await _httpClient.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return const <String>[];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return const <String>[];
      final out = <String>[];
      for (final item in decoded) {
        if (item is Map && item['word'] is String) {
          out.add(item['word'] as String);
        }
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  String _normalizeEnglishQuery(String raw) {
    final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return '';
    return collapsed.toLowerCase();
  }

  String _cleanSentence(String raw) {
    final strippedTags = raw
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (strippedTags.isEmpty) return '';
    final capitalized =
        strippedTags[0].toUpperCase() + strippedTags.substring(1);
    if (RegExp(r'[.!?]$').hasMatch(capitalized)) {
      return capitalized;
    }
    return '$capitalized.';
  }

  List<String> _buildCandidateGeminiModels() {
    final ordered = <String>[
      if (_activeGeminiModel != null) _activeGeminiModel!,
      ApiConfig.geminiModel,
      ...ApiConfig.geminiFallbackModels,
    ];
    final seen = <String>{};
    return ordered
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty && seen.add(m))
        .toList(growable: false);
  }

  Future<WordSearchDetail?> _tryFetchFromGemini({
    required String apiKey,
    required String word,
  }) async {
    final models = _buildCandidateGeminiModels();

    for (final model in models) {
      final uri = Uri.parse(
        '${ApiConfig.geminiBaseUrl}/$model:generateContent',
      );
      final generationConfig = <String, Object?>{
        'temperature': 0.25,
        'maxOutputTokens': 1536,
        'responseMimeType': 'application/json',
        if (model.startsWith('gemini-2.5'))
          'thinkingConfig': <String, Object?>{'thinkingBudget': 0},
      };

      final body = jsonEncode(<String, Object?>{
        'systemInstruction': <String, Object?>{
          'parts': <Map<String, String>>[
            <String, String>{'text': _geminiSystemPrompt},
          ],
        },
        'contents': <Map<String, Object?>>[
          <String, Object?>{
            'role': 'user',
            'parts': <Map<String, String>>[
              <String, String>{'text': 'Target English word: "$word"'},
            ],
          },
        ],
        'generationConfig': generationConfig,
      });

      try {
        final response = await _httpClient
            .post(
              uri,
              headers: <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
                'x-goog-api-key': apiKey,
              },
              body: body,
            )
            .timeout(_timeout);

        if (response.statusCode == 404) {
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }

        final parsed = _parseGeminiDetailResponse(word, response.bodyBytes);
        if (parsed != null && parsed.meanings.isNotEmpty) {
          _activeGeminiModel = model;
          return parsed;
        }
        return null;
      } catch (error) {
        debugPrint('[WordDictionarySearchService] Gemini hatasi ($model): $error');
        return null;
      }
    }

    return null;
  }

  WordSearchDetail? _parseGeminiDetailResponse(
    String word,
    List<int> bodyBytes,
  ) {
    try {
      final root = jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
      if (root is! Map) return null;

      final candidates = root['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final content = (candidates.first as Map?)?['content'];
      final parts = (content as Map?)?['parts'];
      if (parts is! List || parts.isEmpty) return null;

      String rawJsonText = '';
      for (final part in parts) {
        if (part is Map && part['thought'] != true && part['text'] is String) {
          rawJsonText += part['text'] as String;
        }
      }
      rawJsonText = rawJsonText
          .trim()
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
      if (rawJsonText.isEmpty) return null;

      final payload = jsonDecode(rawJsonText);
      if (payload is! Map) return null;

      final meanings = <MeaningEntry>[];
      final rawMeanings = payload['meanings'];
      if (rawMeanings is List) {
        for (final item in rawMeanings) {
          if (item is! Map) continue;
          final text = (item['meaning'] as String? ?? '').trim();
          if (text.isEmpty) continue;
          final pos = WordPartOfSpeech.tryParse(item['partOfSpeech'] as String?);
          meanings.add(
            MeaningEntry(
              translation: text,
              partOfSpeech: pos,
            ),
          );
        }
      }

      final examples = <WordExampleSentence>[];
      final rawExamples = payload['examples'];
      if (rawExamples is List) {
        for (final item in rawExamples) {
          if (item is! Map) continue;
          final en = (item['english'] as String? ?? '').trim();
          final tr = (item['turkish'] as String? ?? '').trim();
          if (en.isEmpty) continue;
          examples.add(
            WordExampleSentence(
              english: en,
              turkish: tr.isNotEmpty ? tr : null,
            ),
          );
        }
      }

      return WordSearchDetail(
        word: word,
        meanings: meanings,
        examples: examples,
      );
    } catch (error) {
      debugPrint('[WordDictionarySearchService] Gemini parse hatasi: $error');
      return null;
    }
  }

  Future<_GoogleDictionaryBundle?> _fetchGoogleBilingualBundle(
    String word,
  ) async {
    try {
      final queryParts = <String>[
        'client=gtx',
        'sl=en',
        'tl=tr',
        'dt=t',
        'dt=bd',
        'dt=at',
        'dt=ex',
        'dt=qca',
        'q=${Uri.encodeQueryComponent(word)}',
      ];
      final uri = Uri.parse(
        '${ApiConfig.contextualTranslateBaseUrl}?${queryParts.join('&')}',
      );
      final response = await _httpClient.get(uri).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! List) return null;

      final meanings = <MeaningEntry>[];

      // 1) Ana çeviri (root[0])
      if (decoded.isNotEmpty && decoded[0] is List) {
        final buffer = StringBuffer();
        for (final seg in decoded[0] as List) {
          if (seg is List && seg.isNotEmpty && seg[0] is String) {
            buffer.write(seg[0]);
          }
        }
        final direct = buffer.toString().trim();
        if (direct.isNotEmpty) {
          meanings.add(MeaningEntry(translation: direct));
        }
      }

      // 2) İki dilli sözlük bölümü (root[1] -> dt=bd) — genelde 10-25+ anlam içerir!
      var hasBilingualDict = false;
      if (decoded.length > 1 && decoded[1] is List) {
        for (final group in decoded[1] as List) {
          if (group is! List || group.isEmpty) continue;
          hasBilingualDict = true;
          final pos = WordPartOfSpeech.tryParse(group[0] as String?);

          // Önce detaylı liste (group[2])
          final detailed = group.length > 2 ? group[2] : null;
          if (detailed is List && detailed.isNotEmpty) {
            for (final entry in detailed) {
              if (entry is List && entry.isNotEmpty && entry[0] is String) {
                final tr = (entry[0] as String).trim();
                if (tr.isNotEmpty) {
                  meanings.add(
                    MeaningEntry(translation: tr, partOfSpeech: pos),
                  );
                }
              }
            }
          } else if (group.length > 1 && group[1] is List) {
            for (final item in group[1] as List) {
              if (item is String && item.trim().isNotEmpty) {
                meanings.add(
                  MeaningEntry(translation: item.trim(), partOfSpeech: pos),
                );
              }
            }
          }
        }
      }

      // 3) Alternatif çeviriler (root[5] -> dt=at)
      if (decoded.length > 5 && decoded[5] is List) {
        for (final altGroup in decoded[5] as List) {
          if (altGroup is List && altGroup.length > 2 && altGroup[2] is List) {
            for (final alt in altGroup[2] as List) {
              if (alt is List && alt.isNotEmpty && alt[0] is String) {
                final tr = (alt[0] as String).trim();
                if (tr.isNotEmpty) {
                  meanings.add(MeaningEntry(translation: tr));
                }
              }
            }
          }
        }
      }

      // 4) Örnek cümleler (root[13] -> dt=ex)
      final examples = <String>[];
      if (decoded.length > 13 && decoded[13] is List) {
        final exRoot = decoded[13] as List;
        if (exRoot.isNotEmpty && exRoot[0] is List) {
          for (final exItem in exRoot[0] as List) {
            if (exItem is List && exItem.isNotEmpty && exItem[0] is String) {
              final text = (exItem[0] as String).trim();
              if (text.isNotEmpty) {
                examples.add(text);
              }
            }
          }
        }
      }

      // 5) Yazım düzeltme önerisi (root[7] -> dt=qca, örn. "elone" -> "alone")
      String? didYouMean;
      if (decoded.length > 7 && decoded[7] is List) {
        final spellBlock = decoded[7] as List;
        if (spellBlock.length > 1 && spellBlock[1] is String) {
          final cleaned = (spellBlock[1] as String)
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim()
              .toLowerCase();
          if (cleaned.isNotEmpty) {
            didYouMean = cleaned;
          }
        } else if (spellBlock.isNotEmpty && spellBlock[0] is String) {
          final cleaned = (spellBlock[0] as String)
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim()
              .toLowerCase();
          if (cleaned.isNotEmpty) {
            didYouMean = cleaned;
          }
        }
      }

      return _GoogleDictionaryBundle(
        meanings: meanings,
        examples: examples,
        hasBilingualDict: hasBilingualDict,
        didYouMean: didYouMean,
      );
    } on SocketException {
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'İnternet bağlantısı kurulamadı.',
      );
    } on TimeoutException {
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'Sözlük sorgusu zaman aşımına uğradı. Tekrar deneyin.',
      );
    } catch (error) {
      debugPrint('[WordDictionarySearchService] Google sozluk hatasi: $error');
      return null;
    }
  }

  Future<_EnglishDictBundle?> _fetchFreeDictionaryBundle(String word) async {
    if (word.contains(' ')) return null;
    try {
      final uri = Uri.parse(
        '${ApiConfig.freeDictionaryBaseUrl}/${Uri.encodeComponent(word)}',
      );
      final response = await _httpClient.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! List) return null;

      final examples = <String>[];
      final synonyms = <String>[];
      final shortDefinitions = <String>[];
      WordPartOfSpeech? primaryPos;

      for (final entry in decoded) {
        if (entry is! Map) continue;
        final meanings = entry['meanings'];
        if (meanings is! List) continue;

        for (final meaning in meanings) {
          if (meaning is! Map) continue;
          final pos = WordPartOfSpeech.tryParse(meaning['partOfSpeech'] as String?);
          primaryPos ??= pos;

          final rawSynonyms = meaning['synonyms'];
          if (rawSynonyms is List) {
            for (final syn in rawSynonyms) {
              if (syn is String && syn.trim().isNotEmpty) {
                synonyms.add(syn.trim());
              }
            }
          }

          final definitions = meaning['definitions'];
          if (definitions is List) {
            for (final def in definitions) {
              if (def is! Map) continue;
              final ex = def['example'];
              if (ex is String && ex.trim().isNotEmpty) {
                examples.add(ex.trim());
              }
              final defText = def['definition'];
              if (defText is String &&
                  defText.trim().isNotEmpty &&
                  defText.trim().length <= 70) {
                shortDefinitions.add(defText.trim());
              }
              final defSyns = def['synonyms'];
              if (defSyns is List) {
                for (final syn in defSyns) {
                  if (syn is String && syn.trim().isNotEmpty) {
                    synonyms.add(syn.trim());
                  }
                }
              }
            }
          }
        }
      }

      return _EnglishDictBundle(
        primaryPos: primaryPos,
        examples: examples,
        synonyms: synonyms,
        shortDefinitions: shortDefinitions,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<MeaningEntry>> _translateBatchTerms({
    required List<String> terms,
    required WordPartOfSpeech? defaultPos,
    required int limit,
  }) async {
    if (terms.isEmpty || limit <= 0) return const <MeaningEntry>[];

    final uniqueTerms = <String>[];
    final seen = <String>{};
    for (final term in terms) {
      final clean = term.trim();
      if (clean.isEmpty) continue;
      if (seen.add(clean.toLowerCase())) {
        uniqueTerms.add(clean);
        if (uniqueTerms.length >= 12) break;
      }
    }
    if (uniqueTerms.isEmpty) return const <MeaningEntry>[];

    final translatedLines = await _translateSentencesBatch(uniqueTerms);
    final results = <MeaningEntry>[];
    for (var i = 0; i < translatedLines.length; i++) {
      final tr = translatedLines[i]?.trim() ?? '';
      if (tr.isEmpty) continue;
      final source = uniqueTerms[i].toLowerCase();
      final inferredPos =
          source.startsWith('to ') ? WordPartOfSpeech.verb : defaultPos;
      results.add(
        MeaningEntry(
          translation: tr,
          partOfSpeech: inferredPos,
        ),
      );
      if (results.length >= limit) break;
    }
    return results;
  }

  Future<List<String?>> _translateSentencesBatch(List<String> sentences) async {
    if (sentences.isEmpty) return const <String?>[];
    try {
      final joined = sentences.join('\n');
      final queryParts = <String>[
        'client=gtx',
        'sl=en',
        'tl=tr',
        'dt=t',
        'q=${Uri.encodeQueryComponent(joined)}',
      ];
      final uri = Uri.parse(
        '${ApiConfig.contextualTranslateBaseUrl}?${queryParts.join('&')}',
      );
      final response = await _httpClient.get(uri).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return List<String?>.filled(sentences.length, null);
      }

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! List || decoded.isEmpty || decoded[0] is! List) {
        return List<String?>.filled(sentences.length, null);
      }

      final buffer = StringBuffer();
      for (final seg in decoded[0] as List) {
        if (seg is List && seg.isNotEmpty && seg[0] is String) {
          buffer.write(seg[0]);
        }
      }
      final lines = buffer
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .toList(growable: false);

      return List<String?>.generate(
        sentences.length,
        (index) => index < lines.length && lines[index].isNotEmpty
            ? lines[index]
            : null,
      );
    } catch (_) {
      return List<String?>.filled(sentences.length, null);
    }
  }

  /// Cloudflare Worker AI + D1 önbellek üzerinden hedef kelime/ifade için
  /// 3 adet 8–22 kelimelik doğal İngilizce–Türkçe örnek cümle getirir.
  Future<List<WordExampleSentence>> _fetchWorkerExamples(String word) async {
    try {
      final uri = Uri.parse(ApiConfig.wordExamplesWorkerUrl);
      final response = await _httpClient
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, Object?>{'word': word}),
          )
          .timeout(const Duration(seconds: 7));

      if (response.statusCode != 200) return const <WordExampleSentence>[];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const <WordExampleSentence>[];
      final rawList = decoded['examples'];
      if (rawList is! List<dynamic>) return const <WordExampleSentence>[];

      final results = <WordExampleSentence>[];
      for (final item in rawList) {
        if (item is! Map<String, dynamic>) continue;
        final en = _cleanSentence((item['english'] ?? '').toString());
        final tr = (item['turkish'] ?? '').toString().trim();
        if (en.isEmpty) continue;
        results.add(
          WordExampleSentence(
            english: en,
            turkish: tr.isNotEmpty ? tr : null,
          ),
        );
      }
      return results;
    } catch (_) {
      return const <WordExampleSentence>[];
    }
  }

  /// Tatoeba açık korpusundan insan çevirili İngilizce–Türkçe örnek cümleler çeker.
  Future<List<WordExampleSentence>> _fetchTatoebaExamples(String word) async {
    try {
      final queryValue = word.contains(' ') ? '"$word"' : word;
      final uri = Uri.parse(ApiConfig.tatoebaSearchBaseUrl).replace(
        queryParameters: <String, String>{
          'from': 'eng',
          'to': 'tur',
          'query': queryValue,
          'orphans': 'no',
          'unapproved': 'no',
          'sort': 'relevance',
        },
      );
      final response = await _httpClient.get(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'User-Agent': 'LineReader/1.0',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return const <WordExampleSentence>[];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const <WordExampleSentence>[];
      final rawResults = decoded['results'];
      if (rawResults is! List<dynamic>) return const <WordExampleSentence>[];

      final examples = <WordExampleSentence>[];
      for (final item in rawResults) {
        if (item is! Map<String, dynamic>) continue;
        final en = _cleanSentence((item['text'] ?? '').toString());
        if (en.isEmpty) continue;

        String? tr;
        final translations = item['translations'];
        if (translations is List<dynamic>) {
          for (final group in translations) {
            if (group is! List<dynamic>) continue;
            for (final trEntry in group) {
              if (trEntry is Map<String, dynamic> &&
                  trEntry['lang'] == 'tur' &&
                  trEntry['text'] != null) {
                final candidateTr = trEntry['text'].toString().trim();
                if (candidateTr.isNotEmpty) {
                  tr = candidateTr;
                  break;
                }
              }
            }
            if (tr != null) break;
          }
        }

        if (tr != null && tr.isNotEmpty) {
          examples.add(WordExampleSentence(english: en, turkish: tr));
        }
        if (examples.length >= 8) break;
      }
      return examples;
    } catch (_) {
      return const <WordExampleSentence>[];
    }
  }

  static int _countWords(String sentence) {
    return sentence
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .length;
  }

  /// Kısa öbekleri ("air transport" gibi) eleyip yalnızca anlamlı,
  /// 7–26 kelimelik gerçek cümleleri kabul eder.
  static bool _isQualityExampleSentence(String sentence, String targetWord) {
    final clean = sentence.trim();
    if (clean.length < 30 || clean.length > 210) return false;
    final wordCount = _countWords(clean);
    if (wordCount < 7 || wordCount > 26) return false;

    final lowerSentence = clean.toLowerCase();
    final lowerTarget = targetWord.trim().toLowerCase();
    if (lowerTarget.isNotEmpty) {
      if (lowerTarget.contains(' ')) {
        // Çok kelimeli ifadelerde ifadenin kendisi veya anlamlı kelimelerinin tamamı geçmeli.
        if (!lowerSentence.contains(lowerTarget)) {
          final parts = lowerTarget
              .split(RegExp(r'\s+'))
              .where((p) => p.length >= 3)
              .toList();
          if (parts.isNotEmpty &&
              !parts.every((part) => lowerSentence.contains(part))) {
            return false;
          }
        }
      } else if (lowerTarget.length >= 4) {
        final stem = lowerTarget.length > 5
            ? lowerTarget.substring(0, lowerTarget.length - 1)
            : lowerTarget;
        if (!lowerSentence.contains(lowerTarget) &&
            !lowerSentence.contains(stem)) {
          return false;
        }
      }
    }
    return true;
  }

  /// 8–22 kelime aralığını (özellikle 10–18 kelime bandını) en yüksek puanla öne çıkarır.
  static int _scoreExampleSentence(String sentence) {
    final clean = sentence.trim();
    final words = _countWords(clean);
    if (words < 7 || words > 26) return -1000;

    var score = 100;
    // 10–18 kelime arası en ideal aralık (8–22 arası güçlü).
    if (words >= 10 && words <= 18) {
      score += 40;
    } else if (words >= 8 && words <= 22) {
      score += 20;
    } else {
      score -= 10;
    }
    // Tam cümle noktalama işareti bonusu.
    if (RegExp(r'[.!?]$').hasMatch(clean)) {
      score += 10;
    }
    // Büyük harfle başlayan düzgün cümle bonusu.
    if (clean.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(clean)) {
      score += 5;
    }
    return score;
  }

  List<String> _buildFallbackShortExamples({
    required String word,
    WordPartOfSpeech? pos,
  }) {
    return switch (pos) {
      WordPartOfSpeech.verb => <String>[
          'Before making a final decision, the team took extra time to $word every detail carefully.',
          'With regular practice and clear feedback, most learners quickly learn how to $word with confidence.',
          'During the workshop, our instructor showed us a practical way to $word complex situations effectively.',
        ],
      WordPartOfSpeech.adjective => <String>[
          'After reviewing the new proposal together, everyone agreed that the plan looked surprisingly $word.',
          'She explained why choosing a more $word approach would save the entire team valuable time.',
          'Even under tight deadlines, staying $word helped them handle every unexpected challenge without stress.',
        ],
      WordPartOfSpeech.adverb => <String>[
          'Despite the busy schedule, the team responded $word and solved the customer\'s issue before noon.',
          'He walked through the presentation $word so that every member of the audience could follow.',
          'Because they planned each stage $word, the whole project finished ahead of the original deadline.',
        ],
      _ => <String>[
          'Modern businesses rely heavily on $word to stay connected with international partners every single day.',
          'In recent years, major improvements in $word have completely changed how people plan their daily lives.',
          'The report highlights how investing in $word can create faster, safer, and more reliable services.',
        ],
    };
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}

class _GoogleDictionaryBundle {
  const _GoogleDictionaryBundle({
    required this.meanings,
    required this.examples,
    this.hasBilingualDict = false,
    this.didYouMean,
  });

  final List<MeaningEntry> meanings;
  final List<String> examples;
  final bool hasBilingualDict;
  final String? didYouMean;
}

class _EnglishDictBundle {
  const _EnglishDictBundle({
    required this.primaryPos,
    required this.examples,
    required this.synonyms,
    required this.shortDefinitions,
  });

  final WordPartOfSpeech? primaryPos;
  final List<String> examples;
  final List<String> synonyms;
  final List<String> shortDefinitions;
}
