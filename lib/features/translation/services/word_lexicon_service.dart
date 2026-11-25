import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/word_lexicon_info.dart';
import '../utils/english_morphology_resolver.dart';

/// Doğrulanmış Amerikan (US) / İngiliz (UK) IPA okunuşlarını ve eş/zıt anlamlı
/// kelimeleri sağlayan, çevrimdışı paket + otomatik büyüyen SQLite önbellek +
/// çevrimiçi sözlük zenginleştirmeli ortak servis.
///
/// - Asla uydurma/tahmini IPA üretmez; yalnızca doğrulanmış kaynaklardan (`ipa-dict`
///   çevrimdışı paketi veya `dictionaryapi.dev`) gelen gerçek IPA'ları döner.
/// - İnternetten aranan her kelimenin IPA, eş ve zıt anlamları SQLite içindeki
///   `word_lexicon_cache` tablosuna kalıcı olarak kaydedilir; böylece uygulamanın
///   çevrimdışı sözlüğü kullandıkça kendini otomatik tamamlar.
class WordLexiconService {
  WordLexiconService({
    http.Client? httpClient,
    AppDatabase? appDatabase,
    bool enableOnlineEnrichment = true,
    Map<String, WordLexiconInfo>? testBundledEntries,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _appDatabase = appDatabase,
        _enableOnlineEnrichment = enableOnlineEnrichment,
        _testBundledEntries = testBundledEntries;

  /// Uygulama genelinde paylaşılan ortak sözlük örneği.
  static final WordLexiconService shared = WordLexiconService();

  static const String _assetPath = 'assets/lexicon_core.json.gz';
  static const String _cacheTable = 'word_lexicon_cache';
  static const Duration _timeout = Duration(seconds: 7);

  final http.Client _httpClient;
  final bool _ownsClient;
  final AppDatabase? _appDatabase;
  final bool _enableOnlineEnrichment;
  final Map<String, WordLexiconInfo>? _testBundledEntries;

  Map<String, WordLexiconInfo>? _bundledCache;
  Future<void>? _assetLoadFuture;
  bool _dbTableReady = false;
  final Map<String, WordLexiconInfo> _memoryCache = <String, WordLexiconInfo>{};

  Future<void> _ensureBundledLoaded() {
    if (_bundledCache != null) return Future<void>.value();
    final existing = _assetLoadFuture;
    if (existing != null) return existing;

    final future = _loadBundledAsset();
    _assetLoadFuture = future;
    return future;
  }

  Future<void> _loadBundledAsset() async {
    final testEntries = _testBundledEntries;
    if (testEntries != null) {
      _bundledCache = Map<String, WordLexiconInfo>.from(testEntries);
      return;
    }

    try {
      final byteData = await rootBundle.load(_assetPath);
      final compressed = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final rawBytes = gzip.decode(compressed);
      final decoded = jsonDecode(utf8.decode(rawBytes));
      if (decoded is! Map) {
        _bundledCache = <String, WordLexiconInfo>{};
        return;
      }

      final map = <String, WordLexiconInfo>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        final value = entry.value;
        if (key.isEmpty || value is! Map) continue;
        final ipaUs = _normalizeIpa(value['u']?.toString());
        final ipaUk = _normalizeIpa(value['k']?.toString());
        final syn = _parseTermList(value['s'], excludeWord: key, maxCount: 6);
        final ant = _parseTermList(value['a'], excludeWord: key, maxCount: 5);
        if (ipaUs != null || ipaUk != null || syn.isNotEmpty || ant.isNotEmpty) {
          map[key] = WordLexiconInfo(
            word: key,
            ipaUs: ipaUs,
            ipaUk: ipaUk,
            synonyms: syn,
            antonyms: ant,
          );
        }
      }
      _bundledCache = map;
    } catch (error) {
      debugPrint('[WordLexiconService] Offline paket yuklenemedi: $error');
      _bundledCache = <String, WordLexiconInfo>{};
    }
  }

  Future<Database?> _getDbSafely() async {
    try {
      final db = await (_appDatabase ?? AppDatabase.instance).database;
      if (!_dbTableReady) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_cacheTable (
            word TEXT PRIMARY KEY,
            ipa_us TEXT,
            ipa_uk TEXT,
            definition TEXT,
            examples_json TEXT,
            synonyms_json TEXT,
            antonyms_json TEXT,
            updated_at INTEGER NOT NULL
          )
        ''');
        _dbTableReady = true;
      }
      return db;
    } catch (_) {
      return null;
    }
  }

  Future<WordLexiconInfo?> _readFromDb(String normalizedWord) async {
    final db = await _getDbSafely();
    if (db == null) return null;
    try {
      final rows = await db.query(
        _cacheTable,
        where: 'word = ?',
        whereArgs: <Object>[normalizedWord],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      return WordLexiconInfo(
        word: normalizedWord,
        ipaUs: _normalizeIpa(row['ipa_us'] as String?),
        ipaUk: _normalizeIpa(row['ipa_uk'] as String?),
        definition: row['definition'] as String?,
        examples: _decodeJsonTerms(
          row['examples_json'] as String?,
          excludeWord: '',
          maxCount: 3,
        ),
        synonyms: _decodeJsonTerms(
          row['synonyms_json'] as String?,
          excludeWord: normalizedWord,
          maxCount: 6,
        ),
        antonyms: _decodeJsonTerms(
          row['antonyms_json'] as String?,
          excludeWord: normalizedWord,
          maxCount: 5,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToDb(WordLexiconInfo info) async {
    if (info.isEmpty) return;
    final db = await _getDbSafely();
    if (db == null) return;
    try {
      await db.insert(
        _cacheTable,
        <String, Object?>{
          'word': info.word,
          'ipa_us': info.ipaUs,
          'ipa_uk': info.ipaUk,
          'definition': info.definition,
          'examples_json': jsonEncode(info.examples),
          'synonyms_json': jsonEncode(info.synonyms),
          'antonyms_json': jsonEncode(info.antonyms),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  /// Verilen kelimenin gömülü offline sözlükte veya SQLite önbelleğinde
  /// bulunup bulunmadığını kontrol eder (yazım hatası doğrulamasında kullanılır).
  Future<bool> hasKnownEnglishWord(String rawWord) async {
    final normalized = EnglishMorphologyResolver.normalize(rawWord);
    if (normalized.isEmpty || normalized.contains(' ')) return false;
    await _ensureBundledLoaded();
    final bundled = _bundledCache ?? const <String, WordLexiconInfo>{};
    for (final candidate in EnglishMorphologyResolver.resolveCandidates(
      normalized,
    )) {
      if (bundled.containsKey(candidate)) return true;
    }
    return false;
  }

  /// Yanlış yazılmış bir kelime için offline sözlükteki en yakın doğru
  /// İngilizce kelime önerilerini Levenshtein mesafesiyle bulur.
  Future<List<String>> findOfflineSpellingSuggestions(
    String rawWord, {
    int maxSuggestions = 4,
  }) async {
    final query = EnglishMorphologyResolver.normalize(rawWord);
    if (query.length < 2 || query.contains(' ')) return const <String>[];

    await _ensureBundledLoaded();
    final bundled = _bundledCache;
    if (bundled == null || bundled.isEmpty) return const <String>[];

    final maxDist = query.length <= 4 ? 1 : 2;
    final scored = <({String word, int dist, int lenDiff, bool sameFirst})>[];

    for (final candidate in bundled.keys) {
      if (candidate == query) continue;
      final lenDiff = (candidate.length - query.length).abs();
      if (lenDiff > maxDist) continue;
      final dist = _levenshtein(query, candidate, maxDist);
      if (dist <= maxDist) {
        scored.add((
          word: candidate,
          dist: dist,
          lenDiff: lenDiff,
          sameFirst: candidate[0] == query[0],
        ));
      }
    }

    scored.sort((a, b) {
      final d = a.dist.compareTo(b.dist);
      if (d != 0) return d;
      if (a.sameFirst != b.sameFirst) return a.sameFirst ? -1 : 1;
      final l = a.lenDiff.compareTo(b.lenDiff);
      if (l != 0) return l;
      return a.word.compareTo(b.word);
    });

    return scored.take(maxSuggestions).map((e) => e.word).toList(growable: false);
  }

  /// Verilen İngilizce kelime için US/UK IPA + Eş/Zıt Anlamları döndürür.
  ///
  /// 1) Bellek + Gömülü offline paket (~8.000 kelime, 0 ms)
  /// 2) Yerel SQLite `word_lexicon_cache` (daha önce internetten zenginleştirilenler)
  /// 3) Eksik alan varsa çevrimiçi doğrulanmış sözlük (`dictionaryapi.dev` +
  ///    `api.datamuse.com`) üzerinden tamamlayıp SQLite'a kalıcı yazar.
  Future<WordLexiconInfo?> lookup(
    String rawWord, {
    bool allowOnline = true,
  }) async {
    final normalized = EnglishMorphologyResolver.normalize(rawWord);
    if (normalized.isEmpty || normalized.contains(' ')) return null;

    final inMemory = _memoryCache[normalized];
    if (inMemory != null &&
        inMemory.hasBothIpas &&
        inMemory.synonyms.isNotEmpty &&
        inMemory.antonyms.isNotEmpty) {
      return inMemory;
    }

    await _ensureBundledLoaded();
    final bundled = _bundledCache ?? const <String, WordLexiconInfo>{};
    final candidates = EnglishMorphologyResolver.resolveCandidates(normalized);

    WordLexiconInfo? resolved;
    for (final candidate in candidates) {
      final hit = bundled[candidate];
      if (hit != null) {
        resolved = WordLexiconInfo(
          word: normalized,
          ipaUs: hit.ipaUs,
          ipaUk: hit.ipaUk,
          synonyms: hit.synonyms,
          antonyms: hit.antonyms,
        );
        break;
      }
    }

    final dbCached = await _readFromDb(normalized);
    if (dbCached != null) {
      resolved = resolved == null ? dbCached : resolved.mergeWith(dbCached);
    }

    final needsOnline = _enableOnlineEnrichment &&
        allowOnline &&
        (resolved == null ||
            !resolved.hasBothIpas ||
            resolved.synonyms.isEmpty ||
            resolved.antonyms.isEmpty);

    if (needsOnline) {
      final online = await _fetchOnlineLexicon(
        normalized,
        needIpa: resolved == null || !resolved.hasBothIpas,
        needSynonyms: resolved == null || resolved.synonyms.isEmpty,
        needAntonyms: resolved == null || resolved.antonyms.isEmpty,
      );
      if (online != null && !online.isEmpty) {
        final merged = resolved == null ? online : resolved.mergeWith(online);
        resolved = merged;
        await _saveToDb(merged);
      }
    }

    if (resolved != null && !resolved.isEmpty) {
      _memoryCache[normalized] = resolved;
      return resolved;
    }
    return null;
  }

  Future<WordLexiconInfo?> _fetchOnlineLexicon(
    String word, {
    required bool needIpa,
    required bool needSynonyms,
    required bool needAntonyms,
  }) async {
    String? ipaUs;
    String? ipaUk;
    String? wiktUs;
    String? wiktUk;
    final synonyms = <String>[];
    final antonyms = <String>[];

    final tasks = <Future<void>>[];

    if (needIpa || needSynonyms || needAntonyms) {
      tasks.add(() async {
        final dict = await _fetchFromDictionaryApi(word);
        if (dict == null) return;
        ipaUs ??= dict.ipaUs;
        ipaUk ??= dict.ipaUk;
        synonyms.addAll(dict.synonyms);
        antonyms.addAll(dict.antonyms);
      }());
    }

    if (needIpa) {
      tasks.add(() async {
        final wikt = await _fetchFromWiktionaryIpa(word);
        if (wikt == null) return;
        wiktUs = wikt.ipaUs;
        wiktUk = wikt.ipaUk;
      }());
    }

    if (needSynonyms) {
      tasks.add(() async {
        final datamuseSyn = await _fetchFromDatamuse(word, relParam: 'rel_syn', max: 5);
        synonyms.addAll(datamuseSyn);
      }());
    }

    if (needAntonyms) {
      tasks.add(() async {
        final datamuseAnt = await _fetchFromDatamuse(word, relParam: 'rel_ant', max: 4);
        antonyms.addAll(datamuseAnt);
      }());
    }

    await Future.wait<void>(tasks);

    // Wiktionary'de açık aksan etiketli US/UK IPA varsa eksik aksanları tamamla.
    ipaUs ??= wiktUs;
    ipaUk ??= wiktUk;
    if (ipaUs != null && ipaUk == null && wiktUk != null) {
      ipaUk = wiktUk;
    }
    if (ipaUk != null && ipaUs == null && wiktUs != null) {
      ipaUs = wiktUs;
    }

    final cleanSyn = _parseTermList(synonyms, excludeWord: word, maxCount: 6);
    final cleanAnt = _parseTermList(antonyms, excludeWord: word, maxCount: 5);

    if (ipaUs == null && ipaUk == null && cleanSyn.isEmpty && cleanAnt.isEmpty) {
      return null;
    }
    return WordLexiconInfo(
      word: word,
      ipaUs: ipaUs,
      ipaUk: ipaUk,
      synonyms: cleanSyn,
      antonyms: cleanAnt,
    );
  }

  Future<WordLexiconInfo?> _fetchFromDictionaryApi(String word) async {
    try {
      final uri = Uri.parse(
        'https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(word)}',
      );
      final response = await _httpClient.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List || decoded.isEmpty) return null;

      String? ipaUs;
      String? ipaUk;
      String? fallbackIpa;
      String? definition;
      final examples = <String>[];
      final synonyms = <String>[];
      final antonyms = <String>[];

      for (final entry in decoded) {
        if (entry is! Map) continue;
        final topPhonetic = _normalizeIpa(entry['phonetic']?.toString());
        if (topPhonetic != null && fallbackIpa == null) {
          fallbackIpa = topPhonetic;
        }

        final phonetics = entry['phonetics'];
        if (phonetics is List) {
          for (final item in phonetics) {
            if (item is! Map) continue;
            final text = _normalizeIpa(item['text']?.toString());
            if (text == null) continue;
            final audio = (item['audio']?.toString() ?? '').toLowerCase();
            if (audio.contains('-us.') || audio.contains('/us/')) {
              ipaUs ??= text;
            } else if (audio.contains('-uk.') ||
                audio.contains('-gb.') ||
                audio.contains('/uk/')) {
              ipaUk ??= text;
            } else {
              fallbackIpa ??= text;
            }
          }
        }

        final meanings = entry['meanings'];
        if (meanings is List) {
          for (final m in meanings) {
            if (m is! Map) continue;
            if (m['synonyms'] is List) {
              for (final s in m['synonyms'] as List) {
                if (s is String) synonyms.add(s);
              }
            }
            if (m['antonyms'] is List) {
              for (final a in m['antonyms'] as List) {
                if (a is String) antonyms.add(a);
              }
            }
            final defs = m['definitions'];
            if (defs is List) {
              for (final d in defs) {
                if (d is! Map) continue;
                if (definition == null && d['definition'] is String) {
                  final rawDef = (d['definition'] as String).trim();
                  if (rawDef.isNotEmpty) definition = rawDef;
                }
                if (d['example'] is String) {
                  final rawEx = (d['example'] as String).trim();
                  if (rawEx.isNotEmpty && !examples.contains(rawEx)) {
                    examples.add(rawEx);
                  }
                }
                if (d['synonyms'] is List) {
                  for (final s in d['synonyms'] as List) {
                    if (s is String) synonyms.add(s);
                  }
                }
                if (d['antonyms'] is List) {
                  for (final a in d['antonyms'] as List) {
                    if (a is String) antonyms.add(a);
                  }
                }
              }
            }
          }
        }
      }

      // Bölge etiketi yoksa ve tek doğrulanmış IPA geldiyse ikisinden eksik olana ata.
      if (ipaUs == null && ipaUk == null && fallbackIpa != null) {
        ipaUs = fallbackIpa;
      }

      return WordLexiconInfo(
        word: word,
        ipaUs: ipaUs,
        ipaUk: ipaUk,
        definition: definition,
        examples: examples.take(3).toList(growable: false),
        synonyms: _parseTermList(synonyms, excludeWord: word, maxCount: 6),
        antonyms: _parseTermList(antonyms, excludeWord: word, maxCount: 5),
      );
    } catch (_) {
      return null;
    }
  }

  /// İngilizce Wiktionary üzerinden doğrulanmış US (`GA`/`US`) ve UK (`RP`/`UK`)
  /// IPA okunuşlarını çeker. Eksik kalan aksanı tamamlayarak iki aksanın da
  /// birlikte görünmesini sağlar.
  Future<({String? ipaUs, String? ipaUk})?> _fetchFromWiktionaryIpa(
    String word,
  ) async {
    try {
      final uri = Uri.parse('https://en.wiktionary.org/w/api.php').replace(
        queryParameters: <String, String>{
          'action': 'parse',
          'page': word,
          'prop': 'wikitext',
          'format': 'json',
          'redirects': '1',
        },
      );
      final response = await _httpClient.get(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'User-Agent': 'LineReader/1.0',
        },
      ).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final parseObj = decoded['parse'];
      if (parseObj is! Map) return null;
      final wikitextObj = parseObj['wikitext'];
      final wikitext = wikitextObj is Map
          ? (wikitextObj['*']?.toString() ?? '')
          : (wikitextObj?.toString() ?? '');
      if (wikitext.isEmpty) return null;

      // Yalnızca `==English==` bölümünü incele (diğer dillerin IPA'sı karışmasın).
      final enStart = wikitext.indexOf('==English==');
      final enSection = enStart >= 0 ? wikitext.substring(enStart) : wikitext;
      final nextLangMatch =
          RegExp(r'\n==[^=\n]+==\s*\n').firstMatch(enSection.substring(11));
      final scoped = nextLangMatch != null
          ? enSection.substring(0, 11 + nextLangMatch.start)
          : enSection;

      String? ipaUs;
      String? ipaUk;
      String? sharedIpa;

      final ipaTemplateRe = RegExp(r'\{\{IPA\|en\|([^}]+)\}\}');
      final accentRe = RegExp(r'\{\{(?:a|accent)\|([^}]+)\}\}');

      for (final line in scoped.split('\n')) {
        final ipaMatch = ipaTemplateRe.firstMatch(line);
        if (ipaMatch == null) continue;

        final rawParams = ipaMatch.group(1) ?? '';
        String? extractedIpa;
        for (final part in rawParams.split('|')) {
          final trimmed = part.trim();
          if (trimmed.isEmpty || trimmed.contains('=')) continue;
          if (trimmed.startsWith('/') || trimmed.startsWith('[')) {
            extractedIpa = _normalizeIpa(trimmed);
            if (extractedIpa != null) break;
          }
        }
        if (extractedIpa == null) continue;

        final accentMatch = accentRe.firstMatch(line);
        if (accentMatch == null) {
          sharedIpa ??= extractedIpa;
          continue;
        }

        final tags = (accentMatch.group(1) ?? '')
            .split('|')
            .map((t) => t.trim().toLowerCase())
            .toSet();

        final isUs = tags.contains('us') ||
            tags.contains('ga') ||
            tags.contains('genam') ||
            tags.contains('general american') ||
            tags.contains('north america');
        final isUk = tags.contains('uk') ||
            tags.contains('rp') ||
            tags.contains('received pronunciation') ||
            tags.contains('britain') ||
            tags.contains('gb');

        if (isUs) ipaUs ??= extractedIpa;
        if (isUk) ipaUk ??= extractedIpa;
        if (!isUs && !isUk) {
          sharedIpa ??= extractedIpa;
        }
        if (ipaUs != null && ipaUk != null) break;
      }

      if (sharedIpa != null) {
        ipaUs ??= sharedIpa;
        ipaUk ??= sharedIpa;
      }

      if (ipaUs == null && ipaUk == null) return null;
      return (ipaUs: ipaUs, ipaUk: ipaUk);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _fetchFromDatamuse(
    String word, {
    required String relParam,
    required int max,
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.datamuse.com/words?$relParam=${Uri.encodeQueryComponent(word)}&max=$max',
      );
      final response = await _httpClient.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const <String>[];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return const <String>[];
      final result = <String>[];
      for (final item in decoded) {
        if (item is Map && item['word'] is String) {
          result.add(item['word'] as String);
        }
      }
      return result;
    } catch (_) {
      return const <String>[];
    }
  }

  static String? _normalizeIpa(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.length < 3) return null;
    if ((trimmed.startsWith('/') && trimmed.endsWith('/')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      return trimmed;
    }
    return '/$trimmed/';
  }

  static List<String> _parseTermList(
    Object? raw, {
    required String excludeWord,
    required int maxCount,
  }) {
    if (raw is! List) return const <String>[];
    final result = <String>[];
    final seen = <String>{excludeWord.trim().toLowerCase()};
    for (final item in raw) {
      final clean = (item?.toString() ?? '').trim().toLowerCase();
      if (clean.length < 2 || clean.length > 24) continue;
      if (!RegExp(r'^[a-z][a-z -]*$').hasMatch(clean)) continue;
      if (seen.add(clean)) {
        result.add(clean);
        if (result.length >= maxCount) break;
      }
    }
    return List<String>.unmodifiable(result);
  }

  static List<String> _decodeJsonTerms(
    String? rawJson, {
    required String excludeWord,
    required int maxCount,
  }) {
    if (rawJson == null || rawJson.trim().isEmpty) return const <String>[];
    try {
      return _parseTermList(
        jsonDecode(rawJson),
        excludeWord: excludeWord,
        maxCount: maxCount,
      );
    } catch (_) {
      return const <String>[];
    }
  }

  static int _levenshtein(String a, String b, int maxLimit) {
    final m = a.length;
    final n = b.length;
    if ((m - n).abs() > maxLimit) return maxLimit + 1;
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      var minRow = curr[0];
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        final val = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
        curr[j] = val;
        if (val < minRow) minRow = val;
      }
      if (minRow > maxLimit) return maxLimit + 1;
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
