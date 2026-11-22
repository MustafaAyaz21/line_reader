import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../models/word_meaning.dart';
import '../utils/english_morphology_resolver.dart';

/// Yerel sözlük kaynağından dönen tek bir kelime kaydı.
class LocalDictionaryEntry {
  const LocalDictionaryEntry({
    required this.word,
    required this.meanings,
    required this.sourceId,
  });

  final String word;
  final List<MeaningEntry> meanings;
  final String sourceId;
}

/// Kök/ek çözümlemesi dahil yerel sözlük aramasının sonucu.
class LocalDictionaryLookupResult {
  const LocalDictionaryLookupResult({
    required this.queryWord,
    required this.matchedLemma,
    required this.meaning,
    required this.sourceId,
  });

  final String queryWord;
  final String matchedLemma;
  final WordMeaning meaning;
  final String sourceId;
}

/// Genişletilebilir yerel sözlük kaynağı arayüzü.
/// İleride harici bir sözlük dosyası (JSON, SQLite, TSV vb.) eklendiğinde
/// yalnızca bu arayüzü uygulayan bir kaynak kaydetmek yeterlidir.
abstract interface class LocalDictionarySource {
  String get sourceId;

  Future<LocalDictionaryEntry?> findExact(String normalizedWord);
}

/// İleride harici bir JSON sözlük dosyasını (asset veya yerel dosya)
/// tek satırda sisteme takmak için hazır modüler kaynak sınıfı.
///
/// Desteklenen JSON biçimleri:
/// - `{"word": "anlam"}` veya `{"word": ["anlam 1", "anlam 2"]}`
/// - `{"word": [{"translation": "anlam", "partOfSpeech": "verb"}]}`
class ExternalJsonDictionarySource implements LocalDictionarySource {
  ExternalJsonDictionarySource({
    required this.sourceId,
    required Future<String?> Function() loadRawJson,
  }) : _loadRawJson = loadRawJson;

  @override
  final String sourceId;

  final Future<String?> Function() _loadRawJson;
  Map<String, List<MeaningEntry>>? _loadedEntries;
  bool _hasAttemptedLoad = false;

  Future<Map<String, List<MeaningEntry>>> _ensureLoaded() async {
    final cached = _loadedEntries;
    if (cached != null) return cached;
    if (_hasAttemptedLoad) return const <String, List<MeaningEntry>>{};
    _hasAttemptedLoad = true;

    try {
      final raw = await _loadRawJson();
      if (raw == null || raw.trim().isEmpty) {
        _loadedEntries = const <String, List<MeaningEntry>>{};
        return _loadedEntries!;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _loadedEntries = const <String, List<MeaningEntry>>{};
        return _loadedEntries!;
      }

      final map = <String, List<MeaningEntry>>{};
      for (final entry in decoded.entries) {
        final key = EnglishMorphologyResolver.normalize(entry.key.toString());
        if (key.isEmpty) continue;
        final meanings = _parseDynamicMeanings(entry.value);
        if (meanings.isNotEmpty) {
          map[key] = List<MeaningEntry>.unmodifiable(meanings);
        }
      }
      _loadedEntries = map;
      return map;
    } catch (error) {
      debugPrint(
        '[ExternalJsonDictionarySource:$sourceId] Yukleme hatasi: $error',
      );
      _loadedEntries = const <String, List<MeaningEntry>>{};
      return _loadedEntries!;
    }
  }

  static List<MeaningEntry> _parseDynamicMeanings(Object? rawValue) {
    if (rawValue is String) {
      final trimmed = rawValue.trim();
      if (trimmed.isEmpty) return const <MeaningEntry>[];
      return <MeaningEntry>[MeaningEntry(translation: trimmed)];
    }

    if (rawValue is List) {
      final list = <MeaningEntry>[];
      for (final item in rawValue) {
        if (item is String && item.trim().isNotEmpty) {
          list.add(MeaningEntry(translation: item.trim()));
        } else if (item is Map) {
          final parsed = MeaningEntry.fromJson(Map<String, Object?>.from(item));
          if (parsed.translation.isNotEmpty) {
            list.add(parsed);
          }
        }
      }
      return list;
    }

    return const <MeaningEntry>[];
  }

  @override
  Future<LocalDictionaryEntry?> findExact(String normalizedWord) async {
    final map = await _ensureLoaded();
    final meanings = map[normalizedWord];
    if (meanings == null || meanings.isEmpty) return null;
    return LocalDictionaryEntry(
      word: normalizedWord,
      meanings: meanings,
      sourceId: sourceId,
    );
  }
}

/// Uygulamanın mevcut SQLite `translation_cache` tablosunu yerel sözlük
/// kaynağı olarak kullanır; kullanıcı okudukça çevrimdışı sözlük büyür.
class SqliteTranslationCacheDictionarySource implements LocalDictionarySource {
  SqliteTranslationCacheDictionarySource(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  String get sourceId => 'sqlite_translation_cache';

  @override
  Future<LocalDictionaryEntry?> findExact(String normalizedWord) async {
    try {
      final db = await _appDatabase.database;
      await _appDatabase.ensureTranslationCacheTable(db);

      final rows = await db.query(
        AppDatabase.translationCacheTable,
        where: 'LOWER(word) = ?',
        whereArgs: <Object>[normalizedWord],
        orderBy: 'updated_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final rawMeaningsJson = row['meanings_json'] as String?;
      final parsedEntries = <MeaningEntry>[];

      if (rawMeaningsJson != null && rawMeaningsJson.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawMeaningsJson);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final entry = MeaningEntry.fromJson(
                  Map<String, Object?>.from(item),
                );
                if (entry.translation.isNotEmpty) {
                  parsedEntries.add(
                    MeaningEntry(
                      translation: entry.translation,
                      partOfSpeech: entry.partOfSpeech,
                      isContextual: false,
                    ),
                  );
                }
              }
            }
          }
        } catch (_) {}
      }

      if (parsedEntries.isEmpty) {
        final fallbackTranslation = (row['translation'] as String? ?? '').trim();
        if (fallbackTranslation.isNotEmpty) {
          parsedEntries.add(
            MeaningEntry(
              translation: fallbackTranslation,
              partOfSpeech: WordPartOfSpeech.tryParse(
                row['part_of_speech'] as String?,
              ),
            ),
          );
        }
      }

      if (parsedEntries.isEmpty) return null;
      return LocalDictionaryEntry(
        word: normalizedWord,
        meanings: List<MeaningEntry>.unmodifiable(parsedEntries),
        sourceId: sourceId,
      );
    } catch (error) {
      debugPrint(
        '[SqliteTranslationCacheDictionarySource] Arama hatasi: $error',
      );
      return null;
    }
  }
}

/// Uygulama boyutunu şişirmeden en sık kullanılan temel İngilizce kelimeleri
/// sunan hafif yerleşik çekirdek sözlük (~200+ yüksek frekanslı kelime).
class BuiltInCoreDictionarySource implements LocalDictionarySource {
  const BuiltInCoreDictionarySource();

  @override
  String get sourceId => 'builtin_core_dict';

  @override
  Future<LocalDictionaryEntry?> findExact(String normalizedWord) async {
    final entries = _coreWords[normalizedWord];
    if (entries == null || entries.isEmpty) return null;
    return LocalDictionaryEntry(
      word: normalizedWord,
      meanings: entries,
      sourceId: sourceId,
    );
  }

  static const Map<String, List<MeaningEntry>> _coreWords =
      <String, List<MeaningEntry>>{
    'about': <MeaningEntry>[
      MeaningEntry(translation: 'hakkında'),
      MeaningEntry(translation: 'yaklaşık', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'able': <MeaningEntry>[
      MeaningEntry(translation: 'yapabilen', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'yetenekli', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'accept': <MeaningEntry>[
      MeaningEntry(translation: 'kabul etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'onaylamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'achieve': <MeaningEntry>[
      MeaningEntry(translation: 'başarmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'elde etmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'across': <MeaningEntry>[
      MeaningEntry(translation: 'karşısında'),
      MeaningEntry(translation: 'boyunca'),
    ],
    'act': <MeaningEntry>[
      MeaningEntry(translation: 'davranmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'hareket etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'eylem', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'active': <MeaningEntry>[
      MeaningEntry(translation: 'etkin', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'hareketli', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'add': <MeaningEntry>[
      MeaningEntry(translation: 'eklemek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'toplamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'agree': <MeaningEntry>[
      MeaningEntry(translation: 'katılmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'anlaşmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'allow': <MeaningEntry>[
      MeaningEntry(translation: 'izin vermek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'olanak tanımak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'always': <MeaningEntry>[
      MeaningEntry(translation: 'her zaman', partOfSpeech: WordPartOfSpeech.adverb),
      MeaningEntry(translation: 'daima', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'ancient': <MeaningEntry>[
      MeaningEntry(translation: 'antik', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'çok eski', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'answer': <MeaningEntry>[
      MeaningEntry(translation: 'cevap', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yanıtlamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'appear': <MeaningEntry>[
      MeaningEntry(translation: 'görünmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'ortaya çıkmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'area': <MeaningEntry>[
      MeaningEntry(translation: 'alan', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'bölge', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'arrive': <MeaningEntry>[
      MeaningEntry(translation: 'varmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'ulaşmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'ask': <MeaningEntry>[
      MeaningEntry(translation: 'sormak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'rica etmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'attention': <MeaningEntry>[
      MeaningEntry(translation: 'dikkat', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'ilgi', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'avoid': <MeaningEntry>[
      MeaningEntry(translation: 'kaçınmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'uzak durmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'bad': <MeaningEntry>[
      MeaningEntry(translation: 'kötü', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'olumsuz', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'balance': <MeaningEntry>[
      MeaningEntry(translation: 'denge', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'dengelemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'basic': <MeaningEntry>[
      MeaningEntry(translation: 'temel', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'basit', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'be': <MeaningEntry>[
      MeaningEntry(translation: 'olmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'bulunmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'become': <MeaningEntry>[
      MeaningEntry(translation: 'olmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'haline gelmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'begin': <MeaningEntry>[
      MeaningEntry(translation: 'başlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'başlatmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'behavior': <MeaningEntry>[
      MeaningEntry(translation: 'davranış', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'tutum', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'believe': <MeaningEntry>[
      MeaningEntry(translation: 'inanmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'düşünmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'benefit': <MeaningEntry>[
      MeaningEntry(translation: 'fayda', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yararlanmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'big': <MeaningEntry>[
      MeaningEntry(translation: 'büyük', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'önemli', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'book': <MeaningEntry>[
      MeaningEntry(translation: 'kitap', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'rezerve etmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'break': <MeaningEntry>[
      MeaningEntry(translation: 'kırmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'mola', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'bozmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'bring': <MeaningEntry>[
      MeaningEntry(translation: 'getirmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'beraberinde getirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'build': <MeaningEntry>[
      MeaningEntry(translation: 'inşa etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'oluşturmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'buy': <MeaningEntry>[
      MeaningEntry(translation: 'satın almak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'call': <MeaningEntry>[
      MeaningEntry(translation: 'aramak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'çağırmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'adlandırmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'calm': <MeaningEntry>[
      MeaningEntry(translation: 'sakin', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'sakinleştirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'care': <MeaningEntry>[
      MeaningEntry(translation: 'önemsemek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'bakım', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'carry': <MeaningEntry>[
      MeaningEntry(translation: 'taşımak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'catch': <MeaningEntry>[
      MeaningEntry(translation: 'yakalamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yetişmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'cause': <MeaningEntry>[
      MeaningEntry(translation: 'sebep olmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'neden', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'celebrate': <MeaningEntry>[
      MeaningEntry(translation: 'kutlamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'change': <MeaningEntry>[
      MeaningEntry(translation: 'değiştirmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'değişim', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'child': <MeaningEntry>[
      MeaningEntry(translation: 'çocuk', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'choose': <MeaningEntry>[
      MeaningEntry(translation: 'seçmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'tercih etmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'city': <MeaningEntry>[
      MeaningEntry(translation: 'şehir', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'kent', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'clear': <MeaningEntry>[
      MeaningEntry(translation: 'açık', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'net', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'temizlemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'close': <MeaningEntry>[
      MeaningEntry(translation: 'yakın', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'kapatmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yakından', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'collect': <MeaningEntry>[
      MeaningEntry(translation: 'toplamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'biriktirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'come': <MeaningEntry>[
      MeaningEntry(translation: 'gelmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'kaynaklanmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'common': <MeaningEntry>[
      MeaningEntry(translation: 'yaygın', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'ortak', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'community': <MeaningEntry>[
      MeaningEntry(translation: 'topluluk', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'toplum', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'compare': <MeaningEntry>[
      MeaningEntry(translation: 'karşılaştırmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'conclude': <MeaningEntry>[
      MeaningEntry(translation: 'sonuca varmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sonlandırmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'confuse': <MeaningEntry>[
      MeaningEntry(translation: 'kafasını karıştırmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'connect': <MeaningEntry>[
      MeaningEntry(translation: 'bağlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'ilişkilendirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'consider': <MeaningEntry>[
      MeaningEntry(translation: 'düşünmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'göz önünde bulundurmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'continue': <MeaningEntry>[
      MeaningEntry(translation: 'devam etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sürdürmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'control': <MeaningEntry>[
      MeaningEntry(translation: 'kontrol etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'denetim', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'create': <MeaningEntry>[
      MeaningEntry(translation: 'oluşturmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yaratmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'culture': <MeaningEntry>[
      MeaningEntry(translation: 'kültür', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'cultural': <MeaningEntry>[
      MeaningEntry(translation: 'kültürel', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'custom': <MeaningEntry>[
      MeaningEntry(translation: 'gelenek', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'görenek', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'özel yapım', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'daily': <MeaningEntry>[
      MeaningEntry(translation: 'günlük', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'her gün', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'decide': <MeaningEntry>[
      MeaningEntry(translation: 'karar vermek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'belirlemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'deep': <MeaningEntry>[
      MeaningEntry(translation: 'derin', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'yoğun', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'define': <MeaningEntry>[
      MeaningEntry(translation: 'tanımlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'belirlemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'describe': <MeaningEntry>[
      MeaningEntry(translation: 'tanımlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'betimlemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'develop': <MeaningEntry>[
      MeaningEntry(translation: 'geliştirmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'gelişmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'different': <MeaningEntry>[
      MeaningEntry(translation: 'farklı', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'değişik', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'difficult': <MeaningEntry>[
      MeaningEntry(translation: 'zor', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'güç', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'discover': <MeaningEntry>[
      MeaningEntry(translation: 'keşfetmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'discuss': <MeaningEntry>[
      MeaningEntry(translation: 'tartışmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'görüşmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'do': <MeaningEntry>[
      MeaningEntry(translation: 'yapmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'draw': <MeaningEntry>[
      MeaningEntry(translation: 'çizmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'çekmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'drive': <MeaningEntry>[
      MeaningEntry(translation: 'sürmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yönlendirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'early': <MeaningEntry>[
      MeaningEntry(translation: 'erken', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'easy': <MeaningEntry>[
      MeaningEntry(translation: 'kolay', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'rahat', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'eat': <MeaningEntry>[
      MeaningEntry(translation: 'yemek yemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'effect': <MeaningEntry>[
      MeaningEntry(translation: 'etki', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'sonuç', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'effort': <MeaningEntry>[
      MeaningEntry(translation: 'çaba', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'gayret', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'energy': <MeaningEntry>[
      MeaningEntry(translation: 'enerji', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'enjoy': <MeaningEntry>[
      MeaningEntry(translation: 'keyif almak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'hoşlanmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'enough': <MeaningEntry>[
      MeaningEntry(translation: 'yeterli', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'yeterince', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'environment': <MeaningEntry>[
      MeaningEntry(translation: 'çevre', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'ortam', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'event': <MeaningEntry>[
      MeaningEntry(translation: 'olay', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'etkinlik', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'example': <MeaningEntry>[
      MeaningEntry(translation: 'örnek', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'experience': <MeaningEntry>[
      MeaningEntry(translation: 'deneyim', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yaşamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'explain': <MeaningEntry>[
      MeaningEntry(translation: 'açıklamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'izah etmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'explore': <MeaningEntry>[
      MeaningEntry(translation: 'keşfetmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'araştırmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'express': <MeaningEntry>[
      MeaningEntry(translation: 'ifade etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'dile getirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'fact': <MeaningEntry>[
      MeaningEntry(translation: 'gerçek', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'olgu', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'fall': <MeaningEntry>[
      MeaningEntry(translation: 'düşmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sonbahar', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'family': <MeaningEntry>[
      MeaningEntry(translation: 'aile', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'fast': <MeaningEntry>[
      MeaningEntry(translation: 'hızlı', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'çabuk', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'feel': <MeaningEntry>[
      MeaningEntry(translation: 'hissetmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'duyumsamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'find': <MeaningEntry>[
      MeaningEntry(translation: 'bulmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'keşfetmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'focus': <MeaningEntry>[
      MeaningEntry(translation: 'odaklanmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'odak', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'follow': <MeaningEntry>[
      MeaningEntry(translation: 'takip etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'uymak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'food': <MeaningEntry>[
      MeaningEntry(translation: 'yiyecek', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yemek', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'forget': <MeaningEntry>[
      MeaningEntry(translation: 'unutmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'friend': <MeaningEntry>[
      MeaningEntry(translation: 'arkadaş', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'dost', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'future': <MeaningEntry>[
      MeaningEntry(translation: 'gelecek', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'get': <MeaningEntry>[
      MeaningEntry(translation: 'almak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'elde etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'olmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'give': <MeaningEntry>[
      MeaningEntry(translation: 'vermek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sunmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'go': <MeaningEntry>[
      MeaningEntry(translation: 'gitmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'ilerlemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'good': <MeaningEntry>[
      MeaningEntry(translation: 'iyi', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'güzel', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'great': <MeaningEntry>[
      MeaningEntry(translation: 'harika', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'büyük', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'grow': <MeaningEntry>[
      MeaningEntry(translation: 'büyümek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yetiştirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'habit': <MeaningEntry>[
      MeaningEntry(translation: 'alışkanlık', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'happen': <MeaningEntry>[
      MeaningEntry(translation: 'olmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'meydana gelmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'happy': <MeaningEntry>[
      MeaningEntry(translation: 'mutlu', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'have': <MeaningEntry>[
      MeaningEntry(translation: 'sahip olmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'health': <MeaningEntry>[
      MeaningEntry(translation: 'sağlık', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'hear': <MeaningEntry>[
      MeaningEntry(translation: 'duymak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'işitmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'help': <MeaningEntry>[
      MeaningEntry(translation: 'yardım etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yardım', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'history': <MeaningEntry>[
      MeaningEntry(translation: 'tarih', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'geçmiş', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'hold': <MeaningEntry>[
      MeaningEntry(translation: 'tutmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'düzenlemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'home': <MeaningEntry>[
      MeaningEntry(translation: 'ev', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yuva', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'hope': <MeaningEntry>[
      MeaningEntry(translation: 'ummak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'umut', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'house': <MeaningEntry>[
      MeaningEntry(translation: 'ev', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'human': <MeaningEntry>[
      MeaningEntry(translation: 'insan', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'insani', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'idea': <MeaningEntry>[
      MeaningEntry(translation: 'fikir', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'düşünce', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'important': <MeaningEntry>[
      MeaningEntry(translation: 'önemli', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'improve': <MeaningEntry>[
      MeaningEntry(translation: 'geliştirmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'iyileştirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'include': <MeaningEntry>[
      MeaningEntry(translation: 'içermek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'dahil etmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'increase': <MeaningEntry>[
      MeaningEntry(translation: 'artmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'artırmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'artış', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'inform': <MeaningEntry>[
      MeaningEntry(translation: 'bilgilendirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'inspire': <MeaningEntry>[
      MeaningEntry(translation: 'ilham vermek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'interest': <MeaningEntry>[
      MeaningEntry(translation: 'ilgi', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'ilgisini çekmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'keep': <MeaningEntry>[
      MeaningEntry(translation: 'tutmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'saklamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sürdürmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'kind': <MeaningEntry>[
      MeaningEntry(translation: 'nazik', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'tür', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'know': <MeaningEntry>[
      MeaningEntry(translation: 'bilmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'tanımak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'language': <MeaningEntry>[
      MeaningEntry(translation: 'dil', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'large': <MeaningEntry>[
      MeaningEntry(translation: 'büyük', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'geniş', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'lead': <MeaningEntry>[
      MeaningEntry(translation: 'yol göstermek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yol açmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'learn': <MeaningEntry>[
      MeaningEntry(translation: 'öğrenmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'leave': <MeaningEntry>[
      MeaningEntry(translation: 'ayrılmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'bırakmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'life': <MeaningEntry>[
      MeaningEntry(translation: 'hayat', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yaşam', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'light': <MeaningEntry>[
      MeaningEntry(translation: 'ışık', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'hafif', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'yakmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'like': <MeaningEntry>[
      MeaningEntry(translation: 'sevmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'gibi'),
    ],
    'listen': <MeaningEntry>[
      MeaningEntry(translation: 'dinlemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'little': <MeaningEntry>[
      MeaningEntry(translation: 'küçük', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'az', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'live': <MeaningEntry>[
      MeaningEntry(translation: 'yaşamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'canlı', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'local': <MeaningEntry>[
      MeaningEntry(translation: 'yerel', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'long': <MeaningEntry>[
      MeaningEntry(translation: 'uzun', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'look': <MeaningEntry>[
      MeaningEntry(translation: 'bakmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'görünmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'bakış', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'lose': <MeaningEntry>[
      MeaningEntry(translation: 'kaybetmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'love': <MeaningEntry>[
      MeaningEntry(translation: 'sevmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sevgi', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'make': <MeaningEntry>[
      MeaningEntry(translation: 'yapmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'oluşturmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'neden olmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'man': <MeaningEntry>[
      MeaningEntry(translation: 'adam', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'erkek', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'manage': <MeaningEntry>[
      MeaningEntry(translation: 'yönetmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'başarmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'mean': <MeaningEntry>[
      MeaningEntry(translation: 'anlamına gelmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'kastetmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'meet': <MeaningEntry>[
      MeaningEntry(translation: 'buluşmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'tanışmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'karşılamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'memory': <MeaningEntry>[
      MeaningEntry(translation: 'hafıza', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'anı', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'mind': <MeaningEntry>[
      MeaningEntry(translation: 'zihin', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'akıl', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'aldırmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'modern': <MeaningEntry>[
      MeaningEntry(translation: 'modern', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'çağdaş', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'moment': <MeaningEntry>[
      MeaningEntry(translation: 'an', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'money': <MeaningEntry>[
      MeaningEntry(translation: 'para', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'morning': <MeaningEntry>[
      MeaningEntry(translation: 'sabah', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'move': <MeaningEntry>[
      MeaningEntry(translation: 'hareket etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'taşınmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'much': <MeaningEntry>[
      MeaningEntry(translation: 'çok', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'nature': <MeaningEntry>[
      MeaningEntry(translation: 'doğa', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'tabiat', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'need': <MeaningEntry>[
      MeaningEntry(translation: 'ihtiyaç duymak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'gereksinim', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'new': <MeaningEntry>[
      MeaningEntry(translation: 'yeni', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'notice': <MeaningEntry>[
      MeaningEntry(translation: 'fark etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'duyuru', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'often': <MeaningEntry>[
      MeaningEntry(translation: 'sık sık', partOfSpeech: WordPartOfSpeech.adverb),
      MeaningEntry(translation: 'çoğunlukla', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'old': <MeaningEntry>[
      MeaningEntry(translation: 'eski', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'yaşlı', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'open': <MeaningEntry>[
      MeaningEntry(translation: 'açmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'açık', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'order': <MeaningEntry>[
      MeaningEntry(translation: 'düzen', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'sipariş vermek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'part': <MeaningEntry>[
      MeaningEntry(translation: 'parça', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'bölüm', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'pay': <MeaningEntry>[
      MeaningEntry(translation: 'ödemek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'vermek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'peace': <MeaningEntry>[
      MeaningEntry(translation: 'barış', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'huzur', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'permit': <MeaningEntry>[
      MeaningEntry(translation: 'izin vermek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'izin', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'person': <MeaningEntry>[
      MeaningEntry(translation: 'kişi', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'insan', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'place': <MeaningEntry>[
      MeaningEntry(translation: 'yer', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yerleştirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'plan': <MeaningEntry>[
      MeaningEntry(translation: 'planlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'plan', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'play': <MeaningEntry>[
      MeaningEntry(translation: 'oynamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'çalmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'point': <MeaningEntry>[
      MeaningEntry(translation: 'nokta', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'işaret etmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'possible': <MeaningEntry>[
      MeaningEntry(translation: 'mümkün', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'olası', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'power': <MeaningEntry>[
      MeaningEntry(translation: 'güç', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'enerji', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'practical': <MeaningEntry>[
      MeaningEntry(translation: 'pratik', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'uygulanabilir', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'practice': <MeaningEntry>[
      MeaningEntry(translation: 'uygulama', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'alıştırma yapmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'prepare': <MeaningEntry>[
      MeaningEntry(translation: 'hazırlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'hazırlanmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'problem': <MeaningEntry>[
      MeaningEntry(translation: 'sorun', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'problem', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'protect': <MeaningEntry>[
      MeaningEntry(translation: 'korumak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'provide': <MeaningEntry>[
      MeaningEntry(translation: 'sağlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sunmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'public': <MeaningEntry>[
      MeaningEntry(translation: 'halka açık', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'kamu', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'question': <MeaningEntry>[
      MeaningEntry(translation: 'soru', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'sorgulamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'quick': <MeaningEntry>[
      MeaningEntry(translation: 'hızlı', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'çabuk', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'quiet': <MeaningEntry>[
      MeaningEntry(translation: 'sessiz', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'sakin', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'read': <MeaningEntry>[
      MeaningEntry(translation: 'okumak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'real': <MeaningEntry>[
      MeaningEntry(translation: 'gerçek', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'reason': <MeaningEntry>[
      MeaningEntry(translation: 'sebep', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'neden', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'remember': <MeaningEntry>[
      MeaningEntry(translation: 'hatırlamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'respect': <MeaningEntry>[
      MeaningEntry(translation: 'saygı', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'saygı duymak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'result': <MeaningEntry>[
      MeaningEntry(translation: 'sonuç', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'sonuçlanmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'rule': <MeaningEntry>[
      MeaningEntry(translation: 'kural', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yönetmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'run': <MeaningEntry>[
      MeaningEntry(translation: 'koşmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'çalıştırmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yönetmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'safe': <MeaningEntry>[
      MeaningEntry(translation: 'güvenli', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'say': <MeaningEntry>[
      MeaningEntry(translation: 'söylemek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'demek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'science': <MeaningEntry>[
      MeaningEntry(translation: 'bilim', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'see': <MeaningEntry>[
      MeaningEntry(translation: 'görmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'anlamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'seem': <MeaningEntry>[
      MeaningEntry(translation: 'görünmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'gibi görünmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'send': <MeaningEntry>[
      MeaningEntry(translation: 'göndermek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'sense': <MeaningEntry>[
      MeaningEntry(translation: 'anlam', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'duyu', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'mantık', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'share': <MeaningEntry>[
      MeaningEntry(translation: 'paylaşmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'pay', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'show': <MeaningEntry>[
      MeaningEntry(translation: 'göstermek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'gösteri', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'simple': <MeaningEntry>[
      MeaningEntry(translation: 'basit', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'sade', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'sit': <MeaningEntry>[
      MeaningEntry(translation: 'oturmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'sleep': <MeaningEntry>[
      MeaningEntry(translation: 'uyumak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'uyku', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'slow': <MeaningEntry>[
      MeaningEntry(translation: 'yavaş', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'small': <MeaningEntry>[
      MeaningEntry(translation: 'küçük', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'social': <MeaningEntry>[
      MeaningEntry(translation: 'sosyal', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'toplumsal', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'solve': <MeaningEntry>[
      MeaningEntry(translation: 'çözmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'space': <MeaningEntry>[
      MeaningEntry(translation: 'alan', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'boşluk', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'uzay', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'speak': <MeaningEntry>[
      MeaningEntry(translation: 'konuşmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'spend': <MeaningEntry>[
      MeaningEntry(translation: 'harcamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'vakit geçirmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'stand': <MeaningEntry>[
      MeaningEntry(translation: 'ayakta durmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'katlanmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'start': <MeaningEntry>[
      MeaningEntry(translation: 'başlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'başlangıç', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'stay': <MeaningEntry>[
      MeaningEntry(translation: 'kalmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'stop': <MeaningEntry>[
      MeaningEntry(translation: 'durmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'durdurmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'story': <MeaningEntry>[
      MeaningEntry(translation: 'hikaye', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'öykü', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'strange': <MeaningEntry>[
      MeaningEntry(translation: 'garip', partOfSpeech: WordPartOfSpeech.adjective),
      MeaningEntry(translation: 'tuhaf', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'street': <MeaningEntry>[
      MeaningEntry(translation: 'sokak', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'cadde', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'strong': <MeaningEntry>[
      MeaningEntry(translation: 'güçlü', partOfSpeech: WordPartOfSpeech.adjective),
    ],
    'study': <MeaningEntry>[
      MeaningEntry(translation: 'çalışmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'incelemek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'araştırma', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'success': <MeaningEntry>[
      MeaningEntry(translation: 'başarı', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'support': <MeaningEntry>[
      MeaningEntry(translation: 'desteklemek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'destek', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'system': <MeaningEntry>[
      MeaningEntry(translation: 'sistem', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'düzen', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'take': <MeaningEntry>[
      MeaningEntry(translation: 'almak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'götürmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sürmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'talk': <MeaningEntry>[
      MeaningEntry(translation: 'konuşmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sohbet', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'teach': <MeaningEntry>[
      MeaningEntry(translation: 'öğretmek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'tell': <MeaningEntry>[
      MeaningEntry(translation: 'anlatmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'söylemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'think': <MeaningEntry>[
      MeaningEntry(translation: 'düşünmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sanmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'time': <MeaningEntry>[
      MeaningEntry(translation: 'zaman', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'vakit', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'kez', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'today': <MeaningEntry>[
      MeaningEntry(translation: 'bugün', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'together': <MeaningEntry>[
      MeaningEntry(translation: 'birlikte', partOfSpeech: WordPartOfSpeech.adverb),
      MeaningEntry(translation: 'beraber', partOfSpeech: WordPartOfSpeech.adverb),
    ],
    'tradition': <MeaningEntry>[
      MeaningEntry(translation: 'gelenek', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'travel': <MeaningEntry>[
      MeaningEntry(translation: 'seyahat etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yolculuk', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'try': <MeaningEntry>[
      MeaningEntry(translation: 'denemek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'çabalamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'turn': <MeaningEntry>[
      MeaningEntry(translation: 'dönmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'çevirmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'sıra', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'understand': <MeaningEntry>[
      MeaningEntry(translation: 'anlamak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'kavramak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'use': <MeaningEntry>[
      MeaningEntry(translation: 'kullanmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'kullanım', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'value': <MeaningEntry>[
      MeaningEntry(translation: 'değer', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'değer vermek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'visit': <MeaningEntry>[
      MeaningEntry(translation: 'ziyaret etmek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'ziyaret', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'wait': <MeaningEntry>[
      MeaningEntry(translation: 'beklemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'walk': <MeaningEntry>[
      MeaningEntry(translation: 'yürümek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'yürüyüş', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'want': <MeaningEntry>[
      MeaningEntry(translation: 'istemek', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'watch': <MeaningEntry>[
      MeaningEntry(translation: 'izlemek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'saat', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'water': <MeaningEntry>[
      MeaningEntry(translation: 'su', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'sulamak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'way': <MeaningEntry>[
      MeaningEntry(translation: 'yol', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'yöntem', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'biçim', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'wear': <MeaningEntry>[
      MeaningEntry(translation: 'giymek', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'takmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'win': <MeaningEntry>[
      MeaningEntry(translation: 'kazanmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'woman': <MeaningEntry>[
      MeaningEntry(translation: 'kadın', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'word': <MeaningEntry>[
      MeaningEntry(translation: 'kelime', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'sözcük', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'work': <MeaningEntry>[
      MeaningEntry(translation: 'çalışmak', partOfSpeech: WordPartOfSpeech.verb),
      MeaningEntry(translation: 'iş', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'işe yaramak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'world': <MeaningEntry>[
      MeaningEntry(translation: 'dünya', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'write': <MeaningEntry>[
      MeaningEntry(translation: 'yazmak', partOfSpeech: WordPartOfSpeech.verb),
    ],
    'year': <MeaningEntry>[
      MeaningEntry(translation: 'yıl', partOfSpeech: WordPartOfSpeech.noun),
      MeaningEntry(translation: 'sene', partOfSpeech: WordPartOfSpeech.noun),
    ],
    'young': <MeaningEntry>[
      MeaningEntry(translation: 'genç', partOfSpeech: WordPartOfSpeech.adjective),
    ],
  };
}

/// Kök/ek çözümleyici ile birden fazla yerel sözlük kaynağını koordine eden
/// hafif ve genişletilebilir yerel sözlük servisi.
class LocalDictionaryService {
  LocalDictionaryService({
    List<LocalDictionarySource>? sources,
  }) : _sources = List<LocalDictionarySource>.from(
          sources ??
              <LocalDictionarySource>[
                SqliteTranslationCacheDictionarySource(AppDatabase.instance),
                const BuiltInCoreDictionarySource(),
              ],
        );

  final List<LocalDictionarySource> _sources;

  /// İleride harici bir sözlük dosyası eklendiğinde öncelikli olarak kaydedilebilir.
  void registerSource(LocalDictionarySource source, {bool highPriority = false}) {
    if (highPriority) {
      _sources.insert(0, source);
    } else {
      _sources.add(source);
    }
  }

  /// Kelimenin kendisini ve `EnglishMorphologyResolver` kök adaylarını sırayla
  /// yerel sözlük kaynaklarında arar.
  Future<LocalDictionaryLookupResult?> lookup(
    String rawWord, {
    String? contextSentence,
  }) async {
    final candidates = EnglishMorphologyResolver.resolveCandidates(rawWord);
    if (candidates.isEmpty) return null;

    final displayWord = candidates.first;

    // Önce tüm kaynaklarda tam kelime, ardından kök/ek adaylarını sırayla ara.
    for (final candidate in candidates) {
      for (final source in _sources) {
        final entry = await source.findExact(candidate);
        if (entry != null && entry.meanings.isNotEmpty) {
          return LocalDictionaryLookupResult(
            queryWord: displayWord,
            matchedLemma: candidate,
            sourceId: entry.sourceId,
            meaning: WordMeaning.fromEntries(
              word: displayWord,
              entries: entry.meanings,
              contextSentence: contextSentence,
            ),
          );
        }
      }
    }

    return null;
  }
}
