import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../translation/models/word_meaning.dart';
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
  })  : _geminiApiKeyProvider = geminiApiKeyProvider,
        _shouldAttemptGeminiProvider = shouldAttemptGeminiProvider,
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

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
2. "examples": EXACTLY 3 short, clear, natural everyday English example sentences using the target word (each 5 to 12 words), together with a natural Turkish translation.

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

    // 2) Anlam sayısı < 10 veya örnek < 3 ise ücretsiz çoklu kaynaklardan tamamla.
    if (collectedMeanings.length < _targetMinMeanings ||
        collectedExamples.length < _targetExamplesCount) {
      final freeResults = await Future.wait<Object?>(<Future<Object?>>[
        _fetchGoogleBilingualBundle(normalizedWord),
        _fetchFreeDictionaryBundle(normalizedWord),
      ]);

      final googleBundle = freeResults[0] as _GoogleDictionaryBundle?;
      final dictBundle = freeResults[1] as _EnglishDictBundle?;

      if (googleBundle != null) {
        for (final m in googleBundle.meanings) {
          addMeaning(m);
        }
      }

      // Hâlâ 10'dan az anlam varsa İngilizce eşanlamlılar ve sözcük türü varyasyonlarını çevir.
      if (collectedMeanings.length < _targetMinMeanings) {
        final extraTerms = <String>[
          if (dictBundle != null) ...dictBundle.synonyms,
          if (!normalizedWord.contains(' ')) ...<String>[
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

      // Örnek cümleleri topla (önce gerçek sözlük örnekleri, kısa ve net olanlar).
      final rawEnglishExamples = <String>[];
      if (dictBundle != null) {
        rawEnglishExamples.addAll(dictBundle.examples);
      }
      if (googleBundle != null) {
        rawEnglishExamples.addAll(googleBundle.examples);
      }

      rawEnglishExamples.sort((a, b) => a.length.compareTo(b.length));
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
        if (clean.length < 14 || clean.length > 130) continue;
        if (chosenKeys.add(clean.toLowerCase())) {
          chosenEnglish.add(clean);
        }
      }

      // 3 örneğe ulaşmadıysa kelimenin türüne uygun kısa doğal cümlelerle tamamla.
      final neededExamples =
          _targetExamplesCount - (collectedExamples.length + chosenEnglish.length);
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
        final translatedExamples = await _translateSentencesBatch(chosenEnglish);
        for (var i = 0; i < chosenEnglish.length; i++) {
          final tr = i < translatedExamples.length ? translatedExamples[i] : null;
          addExample(
            WordExampleSentence(
              english: chosenEnglish[i],
              turkish: tr,
            ),
          );
        }
      }
    }

    if (collectedMeanings.isEmpty) {
      throw const TranslationException(
        type: TranslationErrorType.invalidResponse,
        message: 'Bu kelime için anlam bulunamadı. Farklı bir kelime deneyin.',
      );
    }

    return WordSearchDetail(
      word: normalizedWord,
      meanings: List<MeaningEntry>.unmodifiable(collectedMeanings),
      examples: List<WordExampleSentence>.unmodifiable(collectedExamples),
    );
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
      if (decoded.length > 1 && decoded[1] is List) {
        for (final group in decoded[1] as List) {
          if (group is! List || group.isEmpty) continue;
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

      return _GoogleDictionaryBundle(meanings: meanings, examples: examples);
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

  List<String> _buildFallbackShortExamples({
    required String word,
    WordPartOfSpeech? pos,
  }) {
    return switch (pos) {
      WordPartOfSpeech.verb => <String>[
          'We need to $word carefully today.',
          'She can $word very well in practice.',
          'Try to $word this step by step.',
        ],
      WordPartOfSpeech.adjective => <String>[
          'This task looks very $word to me.',
          'It was a really $word decision.',
          'The result became more $word over time.',
        ],
      WordPartOfSpeech.adverb => <String>[
          'He answered the question $word.',
          'They finished the project $word.',
          'Please speak $word during the meeting.',
        ],
      WordPartOfSpeech.noun || null => <String>[
          'We talked about $word in class today.',
          'Understanding $word takes a little practice.',
          'This article gives a clear view of $word.',
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
  });

  final List<MeaningEntry> meanings;
  final List<String> examples;
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
