import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'wav_encoder.dart';

/// Kayıtlı Gemini API anahtarı varken `responseModalities: ["AUDIO"]` ile
/// doğal İngilizce telaffuz üreten ses servisi.
///
/// Herhangi bir HTTP/ağ/model/kota hatasında istisna fırlatmak yerine hatayı
/// `debugPrint` ile loglayıp `null` döner; böylece `TtsService` sessizce
/// cihazın yerleşik `flutter_tts` motoruna düşer.
class GeminiAudioService {
  GeminiAudioService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const int _maxCacheEntries = 40;

  final http.Client _httpClient;
  final bool _ownsClient;
  final Map<String, Uint8List> _audioCache = <String, Uint8List>{};

  String? _activeTtsModel;

  List<String> _candidateModels() {
    final ordered = <String>[
      if (_activeTtsModel != null) _activeTtsModel!,
      ApiConfig.geminiTtsModel,
      ...ApiConfig.geminiTtsFallbackModels,
    ];
    final seen = <String>{};
    final result = <String>[];
    for (final m in ordered) {
      if (m.isNotEmpty && seen.add(m)) {
        result.add(m);
      }
    }
    return result;
  }

  /// Verilen metin için oynatılabilir WAV/ses baytları üretir.
  /// Başarısız olursa `null` döner (çağıran taraf `flutter_tts` yedeğine geçer).
  Future<Uint8List?> synthesize({
    required String apiKey,
    required String text,
    required bool isSentence,
  }) async {
    final cleanKey = apiKey.trim();
    final cleanText = text.trim();
    if (cleanKey.isEmpty || cleanText.isEmpty) return null;

    final cacheKey = '${isSentence ? "s" : "w"}|${cleanText.toLowerCase()}';
    final cached = _audioCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final models = _candidateModels();
    for (var i = 0; i < models.length; i++) {
      final model = models[i];
      final outcome = await _requestAudio(
        apiKey: cleanKey,
        model: model,
        text: cleanText,
        isSentence: isSentence,
      );

      if (outcome.audioBytes != null) {
        _activeTtsModel = model;
        _storeCache(cacheKey, outcome.audioBytes!);
        return outcome.audioBytes;
      }

      if (outcome.shouldTryNextModel && i < models.length - 1) {
        if (_activeTtsModel == model) {
          _activeTtsModel = null;
        }
        debugPrint(
          '[GeminiAudioService] $model ses uretimi desteklemiyor/bulunamadi, '
          'sonraki model deneniyor: ${models[i + 1]}',
        );
        continue;
      }

      return null;
    }

    return null;
  }

  Future<_AudioRequestOutcome> _requestAudio({
    required String apiKey,
    required String model,
    required String text,
    required bool isSentence,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.geminiBaseUrl}/$model:generateContent',
    );

    final prompt = isSentence
        ? 'Read the following English sentence clearly and naturally: $text'
        : 'Pronounce the following English word clearly in standard American English: $text';

    final requestBody = jsonEncode(<String, Object?>{
      'contents': <Map<String, Object?>>[
        <String, Object?>{
          'role': 'user',
          'parts': <Map<String, String>>[
            <String, String>{'text': prompt},
          ],
        },
      ],
      'generationConfig': <String, Object?>{
        'responseModalities': <String>['AUDIO'],
        'speechConfig': <String, Object?>{
          'voiceConfig': <String, Object?>{
            'prebuiltVoiceConfig': <String, String>{
              'voiceName': ApiConfig.geminiTtsVoiceName,
            },
          },
        },
      },
    });

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: requestBody,
          )
          .timeout(ApiConfig.requestTimeout);
    } on TimeoutException catch (error) {
      debugPrint('[GeminiAudioService] Zaman asimi ($model): $error');
      return const _AudioRequestOutcome();
    } on SocketException catch (error) {
      debugPrint('[GeminiAudioService] Ag hatasi: $error');
      return const _AudioRequestOutcome();
    } on http.ClientException catch (error) {
      debugPrint('[GeminiAudioService] Istemci hatasi: $error');
      return const _AudioRequestOutcome();
    }

    if (response.statusCode == 404) {
      debugPrint(
        '[GeminiAudioService] HTTP 404 ($model): ${response.body}',
      );
      return const _AudioRequestOutcome(shouldTryNextModel: true);
    }

    if (response.statusCode == 400) {
      final bodyLower = response.body.toLowerCase();
      debugPrint('[GeminiAudioService] HTTP 400 ($model): ${response.body}');
      // Model AUDIO modality desteklemiyorsa sonraki modeli dene; anahtar geçersizse dur.
      final isInvalidKey =
          bodyLower.contains('api_key_invalid') || bodyLower.contains('api key');
      return _AudioRequestOutcome(shouldTryNextModel: !isInvalidKey);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[GeminiAudioService] HTTP ${response.statusCode} ($model): '
        '${response.body}',
      );
      return const _AudioRequestOutcome();
    }

    final audioBytes = _extractAudioBytes(response.body, model: model);
    if (audioBytes == null || audioBytes.isEmpty) {
      return const _AudioRequestOutcome(shouldTryNextModel: true);
    }

    return _AudioRequestOutcome(audioBytes: audioBytes);
  }

  Uint8List? _extractAudioBytes(String responseBody, {required String model}) {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, Object?>;
      final candidates = decoded['candidates'] as List<Object?>?;
      if (candidates == null || candidates.isEmpty) {
        debugPrint('[GeminiAudioService] Bos candidates ($model)');
        return null;
      }

      final firstCandidate = candidates.first as Map<String, Object?>;
      final content = firstCandidate['content'] as Map<String, Object?>?;
      final parts = content?['parts'] as List<Object?>?;
      if (parts == null || parts.isEmpty) {
        debugPrint('[GeminiAudioService] Bos parts ($model)');
        return null;
      }

      for (final part in parts) {
        if (part is! Map<String, Object?>) continue;
        final inlineData = part['inlineData'] ?? part['inline_data'];
        if (inlineData is! Map<String, Object?>) continue;

        final base64Data = inlineData['data'] as String?;
        if (base64Data == null || base64Data.isEmpty) continue;

        final mimeType =
            (inlineData['mimeType'] ?? inlineData['mime_type']) as String? ??
                'audio/L16;codec=pcm;rate=24000';

        final rawBytes = base64Decode(base64Data);
        if (rawBytes.isEmpty) continue;

        return WavEncoder.ensurePlayableAudio(
          bytes: rawBytes,
          mimeType: mimeType,
        );
      }

      debugPrint('[GeminiAudioService] Yanitta inlineData ses verisi yok ($model)');
      return null;
    } catch (error) {
      debugPrint('[GeminiAudioService] Ses ayristirma hatasi ($model): $error');
      return null;
    }
  }

  void _storeCache(String key, Uint8List bytes) {
    if (_audioCache.length >= _maxCacheEntries) {
      _audioCache.remove(_audioCache.keys.first);
    }
    _audioCache[key] = bytes;
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}

class _AudioRequestOutcome {
  const _AudioRequestOutcome({
    this.audioBytes,
    this.shouldTryNextModel = false,
  });

  final Uint8List? audioBytes;
  final bool shouldTryNextModel;
}
