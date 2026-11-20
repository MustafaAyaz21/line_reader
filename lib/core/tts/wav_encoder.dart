import 'dart:typed_data';

/// Gemini API'den dönen ham PCM (`audio/L16;codec=pcm;rate=24000`) ses verisini
/// Android/iOS medya oynatıcılarının doğrudan çalabileceği standart WAV biçimine
/// sarar.
abstract final class WavEncoder {
  static const int defaultSampleRate = 24000;

  /// MIME türü ham PCM ise 44 baytlık RIFF/WAVE başlığı ekler; zaten WAV/MP3
  /// gibi kapsayıcı biçimindeyse veriyi olduğu gibi döner.
  static Uint8List ensurePlayableAudio({
    required Uint8List bytes,
    required String mimeType,
  }) {
    final lower = mimeType.toLowerCase();
    final isRawPcm = lower.contains('pcm') || lower.contains('l16');
    if (!isRawPcm) {
      return bytes;
    }

    final sampleRate = _extractSampleRate(lower) ?? defaultSampleRate;
    return wrapPcm16(bytes, sampleRate: sampleRate, channels: 1);
  }

  static int? _extractSampleRate(String mimeType) {
    final match = RegExp(r'rate=(\d+)').firstMatch(mimeType);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static Uint8List wrapPcm16(
    Uint8List pcmBytes, {
    int sampleRate = defaultSampleRate,
    int channels = 1,
  }) {
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final int blockAlign = channels * (bitsPerSample ~/ 8);
    final int dataLength = pcmBytes.lengthInBytes;
    final int fileSizeMinus8 = 36 + dataLength;

    final header = ByteData(44);
    // "RIFF"
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, fileSizeMinus8, Endian.little);
    // "WAVE"
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    // "fmt "
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little); // PCM alt parça boyutu
    header.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // "data"
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataLength, Endian.little);

    final wav = Uint8List(44 + dataLength);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataLength, pcmBytes);
    return wav;
  }
}
