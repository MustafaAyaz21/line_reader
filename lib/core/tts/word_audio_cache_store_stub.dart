import 'dart:typed_data';

/// Platforma özgü kalıcı disk önbelleği arayüzü (Web için no-op stub).
abstract class WordAudioDiskStore {
  Future<Uint8List?> read(String cacheKey);

  Future<void> write(String cacheKey, Uint8List bytes);

  Future<void> clear();
}

WordAudioDiskStore createWordAudioDiskStore({required int maxBytes}) {
  return const _NoopWordAudioDiskStore();
}

class _NoopWordAudioDiskStore implements WordAudioDiskStore {
  const _NoopWordAudioDiskStore();

  @override
  Future<Uint8List?> read(String cacheKey) async => null;

  @override
  Future<void> write(String cacheKey, Uint8List bytes) async {}

  @override
  Future<void> clear() async {}
}
