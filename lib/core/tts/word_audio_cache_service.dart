import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'word_audio_cache_store_stub.dart' show WordAudioDiskStore;
import 'word_audio_cache_store_stub.dart'
    if (dart.library.io) 'word_audio_cache_store_io.dart' as store_factory;

/// Kelime telaffuz MP3 dosyalarını cihazda en fazla [maxDiskBytes] (varsayılan
/// 12 MB) yer kaplayacak şekilde saklayan iki katmanlı (RAM + Disk) LRU
/// önbellek servisi.
///
/// Limit dolduğunda en eski dinlenen kayıtlar otomatik olarak silinir; böylece
/// uygulama telefonda asla gereksiz yer kaplamaz ve tekrar dinlenen kelimeler
/// çevrimdışı / anında çalar.
class WordAudioCacheService {
  WordAudioCacheService({
    this.maxDiskBytes = defaultMaxDiskBytes,
    this.maxMemoryBytes = defaultMaxMemoryBytes,
    WordAudioDiskStore? diskStore,
  }) : _diskStore = diskStore ??
            store_factory.createWordAudioDiskStore(maxBytes: maxDiskBytes);

  /// Cihaz diskindeki üst sınır: 12 MB (~2.000–3.000 kelime telaffuzu).
  static const int defaultMaxDiskBytes = 12 * 1024 * 1024;

  /// Aktif oturum RAM sınırı: Web'de 12 MB, mobilde 2 MB.
  static const int defaultMaxMemoryBytes =
      kIsWeb ? 12 * 1024 * 1024 : 2 * 1024 * 1024;

  final int maxDiskBytes;
  final int maxMemoryBytes;
  final WordAudioDiskStore _diskStore;

  final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();
  int _memoryBytes = 0;

  static String buildKey({
    required String word,
    required String accentCode,
  }) {
    final normalizedWord = word.trim().toLowerCase();
    final normalizedAccent = accentCode.trim().toLowerCase();
    return '$normalizedAccent|$normalizedWord';
  }

  /// Yalnızca RAM'de varsa anında (senkron) döner.
  Uint8List? getFromMemorySync({
    required String word,
    required String accentCode,
  }) {
    final key = buildKey(word: word, accentCode: accentCode);
    final hit = _memoryCache.remove(key);
    if (hit == null) return null;
    // LRU: son kullanılanı sona taşı.
    _memoryCache[key] = hit;
    return hit;
  }

  /// Önce RAM'e, yoksa cihaz disk önbelleğine bakar.
  Future<Uint8List?> get({
    required String word,
    required String accentCode,
  }) async {
    final key = buildKey(word: word, accentCode: accentCode);
    final memHit = _memoryCache.remove(key);
    if (memHit != null) {
      _memoryCache[key] = memHit;
      return memHit;
    }

    final diskHit = await _diskStore.read(key);
    if (diskHit != null && diskHit.isNotEmpty) {
      _putMemory(key, diskHit);
      return diskHit;
    }
    return null;
  }

  /// Ses baytlarını hem RAM'e hem de 12 MB limitli disk önbelleğine yazar.
  Future<void> put({
    required String word,
    required String accentCode,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) return;
    final key = buildKey(word: word, accentCode: accentCode);
    _putMemory(key, bytes);
    await _diskStore.write(key, bytes);
  }

  Future<void> clear() async {
    _memoryCache.clear();
    _memoryBytes = 0;
    await _diskStore.clear();
  }

  void _putMemory(String key, Uint8List bytes) {
    if (bytes.lengthInBytes > maxMemoryBytes) return;

    final previous = _memoryCache.remove(key);
    if (previous != null) {
      _memoryBytes -= previous.lengthInBytes;
    }

    _memoryCache[key] = bytes;
    _memoryBytes += bytes.lengthInBytes;

    while (_memoryBytes > maxMemoryBytes && _memoryCache.isNotEmpty) {
      final oldestKey = _memoryCache.keys.first;
      final removed = _memoryCache.remove(oldestKey);
      if (removed != null) {
        _memoryBytes -= removed.lengthInBytes;
      }
    }
  }
}
