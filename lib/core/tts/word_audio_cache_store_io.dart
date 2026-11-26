import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'word_audio_cache_store_stub.dart';

WordAudioDiskStore createWordAudioDiskStore({required int maxBytes}) {
  return _IoWordAudioDiskStore(maxBytes: maxBytes);
}

class _CacheEntryMeta {
  _CacheEntryMeta({
    required this.fileName,
    required this.sizeBytes,
    required this.lastAccessedMs,
  });

  final String fileName;
  final int sizeBytes;
  int lastAccessedMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'f': fileName,
        's': sizeBytes,
        't': lastAccessedMs,
      };

  static _CacheEntryMeta? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final fileName = raw['f']?.toString();
    final sizeBytes = raw['s'];
    final lastAccessedMs = raw['t'];
    if (fileName == null ||
        fileName.isEmpty ||
        sizeBytes is! num ||
        lastAccessedMs is! num) {
      return null;
    }
    return _CacheEntryMeta(
      fileName: fileName,
      sizeBytes: sizeBytes.toInt(),
      lastAccessedMs: lastAccessedMs.toInt(),
    );
  }
}

/// Mobil ve masaüstü platformlarda `maxBytes` (varsayılan 12 MB) sınırını
/// aşmadan çalışan kalıcı LRU (en az/en eski kullanılanı otomatik silen)
/// ses dosyası önbelleği.
class _IoWordAudioDiskStore implements WordAudioDiskStore {
  _IoWordAudioDiskStore({required this.maxBytes});

  static const String _cacheDirName = 'tts_audio_cache';
  static const String _indexFileName = 'index.json';

  final int maxBytes;

  Directory? _cacheDir;
  Map<String, _CacheEntryMeta>? _entries;
  Future<void>? _initFuture;
  int _totalBytes = 0;

  Future<bool> _ensureInitialized() async {
    if (_entries != null && _cacheDir != null) return true;
    final pending = _initFuture;
    if (pending != null) {
      await pending;
      return _entries != null && _cacheDir != null;
    }

    final future = _initialize();
    _initFuture = future;
    await future;
    return _entries != null && _cacheDir != null;
  }

  Future<void> _initialize() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, _cacheDirName));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;

      final loaded = <String, _CacheEntryMeta>{};
      var total = 0;

      final indexFile = File(p.join(dir.path, _indexFileName));
      if (await indexFile.exists()) {
        try {
          final rawText = await indexFile.readAsString();
          final decoded = jsonDecode(rawText);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final meta = _CacheEntryMeta.fromJson(entry.value);
              if (meta == null) continue;
              final audioFile = File(p.join(dir.path, meta.fileName));
              if (await audioFile.exists()) {
                loaded[entry.key.toString()] = meta;
                total += meta.sizeBytes;
              }
            }
          }
        } catch (error) {
          debugPrint('[WordAudioCache] Indeks okuma hatasi, sifirlaniyor: $error');
        }
      }

      _entries = loaded;
      _totalBytes = total;

      // Önceki sürümden veya bozuk durumdan limit aşılmışsa hemen temizle.
      if (_totalBytes > maxBytes) {
        await _evictIfNeeded();
        await _persistIndex();
      }
    } catch (error) {
      debugPrint('[WordAudioCache] Disk onbellegi baslatilamadi: $error');
      _entries = <String, _CacheEntryMeta>{};
      _totalBytes = 0;
    }
  }

  @override
  Future<Uint8List?> read(String cacheKey) async {
    if (!await _ensureInitialized()) return null;
    final dir = _cacheDir;
    final entries = _entries;
    if (dir == null || entries == null) return null;

    final meta = entries[cacheKey];
    if (meta == null) return null;

    try {
      final file = File(p.join(dir.path, meta.fileName));
      if (!await file.exists()) {
        entries.remove(cacheKey);
        _totalBytes = (_totalBytes - meta.sizeBytes).clamp(0, maxBytes * 4);
        await _persistIndex();
        return null;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        entries.remove(cacheKey);
        _totalBytes = (_totalBytes - meta.sizeBytes).clamp(0, maxBytes * 4);
        await _safeDeleteFile(file);
        await _persistIndex();
        return null;
      }

      meta.lastAccessedMs = DateTime.now().millisecondsSinceEpoch;
      // İndeksi her okumada diske yazmak yerine sessizce güncelle.
      _persistIndex();
      return bytes;
    } catch (error) {
      debugPrint('[WordAudioCache] Okuma hatasi ($cacheKey): $error');
      return null;
    }
  }

  @override
  Future<void> write(String cacheKey, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.lengthInBytes > maxBytes) return;
    if (!await _ensureInitialized()) return;

    final dir = _cacheDir;
    final entries = _entries;
    if (dir == null || entries == null) return;

    try {
      final existing = entries.remove(cacheKey);
      if (existing != null) {
        _totalBytes = (_totalBytes - existing.sizeBytes).clamp(0, maxBytes * 4);
        await _safeDeleteFile(File(p.join(dir.path, existing.fileName)));
      }

      final fileName = _buildSafeFileName(cacheKey);
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);

      final size = bytes.lengthInBytes;
      entries[cacheKey] = _CacheEntryMeta(
        fileName: fileName,
        sizeBytes: size,
        lastAccessedMs: DateTime.now().millisecondsSinceEpoch,
      );
      _totalBytes += size;

      await _evictIfNeeded();
      await _persistIndex();
    } catch (error) {
      debugPrint('[WordAudioCache] Yazma hatasi ($cacheKey): $error');
    }
  }

  @override
  Future<void> clear() async {
    if (!await _ensureInitialized()) return;
    final dir = _cacheDir;
    final entries = _entries;
    if (dir == null || entries == null) return;

    try {
      for (final meta in entries.values) {
        await _safeDeleteFile(File(p.join(dir.path, meta.fileName)));
      }
      entries.clear();
      _totalBytes = 0;
      await _persistIndex();
    } catch (error) {
      debugPrint('[WordAudioCache] Temizleme hatasi: $error');
    }
  }

  Future<void> _evictIfNeeded() async {
    final dir = _cacheDir;
    final entries = _entries;
    if (dir == null || entries == null) return;
    if (_totalBytes <= maxBytes) return;

    final sorted = entries.entries.toList()
      ..sort(
        (a, b) => a.value.lastAccessedMs.compareTo(b.value.lastAccessedMs),
      );

    for (final entry in sorted) {
      if (_totalBytes <= maxBytes) break;
      entries.remove(entry.key);
      _totalBytes = (_totalBytes - entry.value.sizeBytes).clamp(0, maxBytes * 4);
      await _safeDeleteFile(File(p.join(dir.path, entry.value.fileName)));
    }
  }

  Future<void> _persistIndex() async {
    final dir = _cacheDir;
    final entries = _entries;
    if (dir == null || entries == null) return;

    try {
      final indexFile = File(p.join(dir.path, _indexFileName));
      final payload = <String, Object?>{
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      };
      await indexFile.writeAsString(jsonEncode(payload), flush: true);
    } catch (error) {
      debugPrint('[WordAudioCache] Indeks kaydetme hatasi: $error');
    }
  }

  Future<void> _safeDeleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static String _buildSafeFileName(String cacheKey) {
    final sanitized = cacheKey
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final prefix = sanitized.length > 40 ? sanitized.substring(0, 40) : sanitized;
    final hash = _fnv1a32(cacheKey).toRadixString(16).padLeft(8, '0');
    return '${prefix.isEmpty ? "w" : prefix}_$hash.mp3';
  }

  static int _fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
