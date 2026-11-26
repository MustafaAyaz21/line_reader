import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../settings/ipa_accent_controller.dart';
import 'word_audio_cache_service.dart';

class PronunciationAudioResult {
  const PronunciationAudioResult({
    required this.bytes,
    this.mimeType = 'audio/mpeg',
  });

  final Uint8List bytes;
  final String mimeType;
}

/// Yapay zekâ kullanmadan açık kaynak gerçek insan telaffuzlarını (US / UK)
/// çeken ve 12 MB üst limitli LRU önbellekte saklayan ses servisi.
///
/// Öncelik sırası:
/// 1) Cihazdaki RAM + 12 MB limitli kalıcı disk önbelleği (0 ms, %100 offline).
/// 2) Cloudflare uç noktası (`/tts?word=...&accent=us|uk`) — aktif olduğunda
///    tüm sesler doğrudan Cloudflare üzerinden servis edilir.
/// 3) Ücretsiz açık kaynak sözlük (`dictionaryapi.dev`) gerçek insan US/UK
///    MP3 kayıtları (Cloudflare `/tts` henüz aktif değilse veya kelime yoksa).
class PronunciationAudioService {
  PronunciationAudioService({
    http.Client? httpClient,
    WordAudioCacheService? cacheService,
    List<String>? cloudflareTtsEndpoints,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _cacheService = cacheService ?? WordAudioCacheService(),
        _cloudflareTtsEndpoints =
            cloudflareTtsEndpoints ?? _defaultCloudflareTtsEndpoints();

  static const Duration _requestTimeout = Duration(seconds: 5);
  static const int _minValidAudioBytes = 256;
  static const int _maxValidAudioBytes = 512 * 1024;
  static const int _maxNegativeCacheEntries = 200;

  final http.Client _httpClient;
  final bool _ownsClient;
  final WordAudioCacheService _cacheService;
  final List<String> _cloudflareTtsEndpoints;

  final Map<String, Future<PronunciationAudioResult?>> _inFlight =
      <String, Future<PronunciationAudioResult?>>{};
  final Set<String> _missingKeys = <String>{};

  /// Cloudflare `/tts` uç noktası 404/405/501 döndürürse aynı oturumda tekrar
  /// beklememek için pasif işaretlenir; uç nokta yayına alındığında otomatik çalışır.
  final Set<String> _disabledCloudflareEndpoints = <String>{};

  static List<String> _defaultCloudflareTtsEndpoints() {
    final endpoints = <String>[];
    final primary = ApiConfig.browserAiTranslateEndpoint.trim();
    if (primary.startsWith('http')) {
      endpoints.add('${primary.replaceAll(RegExp(r'/+$'), '')}/tts');
    }
    final fallback = ApiConfig.browserAiFallbackEndpoint.trim();
    if (fallback.startsWith('http')) {
      final normalized = '${fallback.replaceAll(RegExp(r'/+$'), '')}/tts';
      if (!endpoints.contains(normalized)) {
        endpoints.add(normalized);
      }
    }
    return endpoints;
  }

  /// Verilen metnin tek/kısa kelime telaffuz kaydı için uygun olup olmadığını
  /// kontrol eder ve temizlenmiş anahtarı döner. Cümleler için `null` döner.
  static String? normalizeWordForAudio(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'''^[\s.,!?;:"'()\[\]{}“”‘’\-–—]+'''), '')
        .replaceAll(RegExp(r'''[\s.,!?;:"'()\[\]{}“”‘’\-–—]+$'''), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    if (cleaned.isEmpty || cleaned.length > 40) return null;
    if (cleaned.contains('\n') || cleaned.contains('\r')) return null;

    // En fazla 2 kelimelik ifadeler için ses dosyası ara; uzun cümleler TTS'e gider.
    final words = cleaned.split(' ');
    if (words.length > 2) return null;
    if (!RegExp(r"^[a-z][a-z'\-\s]*$").hasMatch(cleaned)) return null;
    return cleaned;
  }

  /// Yalnızca RAM önbelleğinde varsa anında (senkron) döner.
  PronunciationAudioResult? getCachedFromMemorySync({
    required String word,
    required IpaAccent accent,
  }) {
    final normalized = normalizeWordForAudio(word);
    if (normalized == null) return null;
    final bytes = _cacheService.getFromMemorySync(
      word: normalized,
      accentCode: accent.storageValue,
    );
    if (bytes == null || bytes.isEmpty) return null;
    return PronunciationAudioResult(bytes: bytes);
  }

  /// Verilen kelime + aksan için önce 12 MB LRU önbelleğe, yoksa Cloudflare ve
  /// ücretsiz açık kaynak insan telaffuz kayıtlarına bakar.
  Future<PronunciationAudioResult?> fetchWordAudio({
    required String word,
    required IpaAccent accent,
  }) async {
    final normalized = normalizeWordForAudio(word);
    if (normalized == null) return null;

    final key = WordAudioCacheService.buildKey(
      word: normalized,
      accentCode: accent.storageValue,
    );

    // 1) RAM veya 12 MB limitli kalıcı disk önbelleği.
    final cached = await _cacheService.get(
      word: normalized,
      accentCode: accent.storageValue,
    );
    if (cached != null && cached.isNotEmpty) {
      return PronunciationAudioResult(bytes: cached);
    }

    if (_missingKeys.contains(key)) {
      return null;
    }

    final existingFuture = _inFlight[key];
    if (existingFuture != null) {
      return existingFuture;
    }

    final future = _fetchAndCache(
      normalizedWord: normalized,
      accent: accent,
      cacheKey: key,
    );
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<PronunciationAudioResult?> _fetchAndCache({
    required String normalizedWord,
    required IpaAccent accent,
    required String cacheKey,
  }) async {
    // 2) Cloudflare Worker / R2 / Edge Cache uç noktası.
    final cfAudio = await _fetchFromCloudflare(
      word: normalizedWord,
      accent: accent,
    );
    if (cfAudio != null) {
      await _cacheService.put(
        word: normalizedWord,
        accentCode: accent.storageValue,
        bytes: cfAudio.bytes,
      );
      return cfAudio;
    }

    // 3) Ücretsiz açık kaynak gerçek insan telaffuzu (dictionaryapi.dev).
    final dictAudio = await _fetchFromFreeDictionary(
      word: normalizedWord,
      accent: accent,
    );
    if (dictAudio != null) {
      await _cacheService.put(
        word: normalizedWord,
        accentCode: accent.storageValue,
        bytes: dictAudio.bytes,
      );
      return dictAudio;
    }

    _rememberMissing(cacheKey);
    return null;
  }

  Future<PronunciationAudioResult?> _fetchFromCloudflare({
    required String word,
    required IpaAccent accent,
  }) async {
    for (final baseUrl in _cloudflareTtsEndpoints) {
      if (_disabledCloudflareEndpoints.contains(baseUrl)) continue;

      final uri = Uri.parse(baseUrl).replace(
        queryParameters: <String, String>{
          'word': word,
          'accent': accent.storageValue,
        },
      );

      try {
        final response = await _httpClient
            .get(
              uri,
              headers: const <String, String>{
                'Accept': 'audio/mpeg, audio/*;q=0.9',
              },
            )
            .timeout(_requestTimeout);

        if (response.statusCode == 404 ||
            response.statusCode == 405 ||
            response.statusCode == 501) {
          // Uç nokta henüz tanımlı değilse veya kelime yoksa gereksiz tekrar etme:
          // Yalnızca HTML/JSON "route not found" ise endpoint'i oturumluk kapat.
          final contentType =
              (response.headers['content-type'] ?? '').toLowerCase();
          final bodyLower = response.body.toLowerCase();
          if (response.statusCode != 404 ||
              bodyLower.contains('not found') ||
              contentType.contains('text/html') ||
              contentType.contains('text/plain')) {
            _disabledCloudflareEndpoints.add(baseUrl);
          }
          continue;
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final contentType =
              (response.headers['content-type'] ?? '').toLowerCase();
          final bytes = response.bodyBytes;
          if (_isValidAudioResponse(bytes: bytes, contentType: contentType)) {
            return PronunciationAudioResult(
              bytes: bytes,
              mimeType: _normalizeMimeType(contentType),
            );
          }
        }
      } on TimeoutException {
        debugPrint('[PronunciationAudio] Cloudflare zaman asimi ($baseUrl)');
      } catch (error) {
        debugPrint('[PronunciationAudio] Cloudflare hatasi ($baseUrl): $error');
      }
    }
    return null;
  }

  Future<PronunciationAudioResult?> _fetchFromFreeDictionary({
    required String word,
    required IpaAccent accent,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.freeDictionaryBaseUrl}/${Uri.encodeComponent(word)}',
    );

    http.Response response;
    try {
      response = await _httpClient
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
            },
          )
          .timeout(_requestTimeout);
    } catch (error) {
      debugPrint('[PronunciationAudio] Sozluk istegi hatasi ($word): $error');
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final candidateUrls = _extractRankedAudioUrls(
      response.body,
      preferredAccent: accent,
    );
    if (candidateUrls.isEmpty) return null;

    for (final audioUrl in candidateUrls.take(3)) {
      final downloaded = await _downloadAudioUrl(audioUrl);
      if (downloaded != null) {
        return downloaded;
      }
    }
    return null;
  }

  Future<PronunciationAudioResult?> _downloadAudioUrl(String rawUrl) async {
    final normalizedUrl =
        rawUrl.startsWith('//') ? 'https:$rawUrl' : rawUrl.trim();
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme) return null;

    try {
      final response = await _httpClient
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'audio/mpeg, audio/*;q=0.9',
            },
          )
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final contentType =
          (response.headers['content-type'] ?? '').toLowerCase();
      final bytes = response.bodyBytes;
      if (_isValidAudioResponse(bytes: bytes, contentType: contentType)) {
        return PronunciationAudioResult(
          bytes: bytes,
          mimeType: _normalizeMimeType(contentType, fallbackUrl: normalizedUrl),
        );
      }
    } catch (error) {
      debugPrint('[PronunciationAudio] Ses indirme hatasi ($uri): $error');
    }
    return null;
  }

  List<String> _extractRankedAudioUrls(
    String responseBody, {
    required IpaAccent preferredAccent,
  }) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! List) return const <String>[];

      final scored = <({String url, int score})>[];
      final seen = <String>{};

      for (final entry in decoded) {
        if (entry is! Map) continue;
        final phonetics = entry['phonetics'];
        if (phonetics is! List) continue;

        for (final item in phonetics) {
          if (item is! Map) continue;
          final rawAudio = item['audio']?.toString().trim();
          if (rawAudio == null || rawAudio.isEmpty) continue;

          final normalized =
              rawAudio.startsWith('//') ? 'https:$rawAudio' : rawAudio;
          if (!normalized.startsWith('http') || !seen.add(normalized)) {
            continue;
          }

          final score = _scoreAudioUrl(
            normalized,
            preferredAccent: preferredAccent,
          );
          scored.add((url: normalized, score: score));
        }
      }

      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored.map((e) => e.url).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  static int _scoreAudioUrl(
    String url, {
    required IpaAccent preferredAccent,
  }) {
    final lower = url.toLowerCase();
    var score = 0;

    final isUs = lower.contains('-us.') ||
        lower.contains('_us.') ||
        lower.contains('-us-') ||
        lower.contains('/us/') ||
        lower.contains('en-us');
    final isUk = lower.contains('-uk.') ||
        lower.contains('_uk.') ||
        lower.contains('-uk-') ||
        lower.contains('/uk/') ||
        lower.contains('-gb.') ||
        lower.contains('_gb.') ||
        lower.contains('en-gb');
    final isAu = lower.contains('-au.') ||
        lower.contains('_au.') ||
        lower.contains('/au/');

    if (preferredAccent == IpaAccent.us) {
      if (isUs) {
        score += 100;
      } else if (isUk) {
        score += 55;
      } else if (!isAu) {
        score += 40;
      } else {
        score += 20;
      }
    } else {
      if (isUk) {
        score += 100;
      } else if (isUs) {
        score += 55;
      } else if (!isAu) {
        score += 40;
      } else {
        score += 20;
      }
    }

    if (lower.endsWith('.mp3')) {
      score += 12;
    } else if (lower.endsWith('.m4a') || lower.endsWith('.wav')) {
      score += 6;
    } else if (lower.endsWith('.ogg')) {
      score += 2;
    }

    return score;
  }

  static bool _isValidAudioResponse({
    required Uint8List bytes,
    required String contentType,
  }) {
    if (bytes.lengthInBytes < _minValidAudioBytes ||
        bytes.lengthInBytes > _maxValidAudioBytes) {
      return false;
    }
    if (contentType.startsWith('audio/') ||
        contentType.contains('octet-stream')) {
      return true;
    }
    // MP3 (ID3 veya frame sync 0xFF 0xFB/0xF3/0xF2) / WAV (RIFF) / OGG (OggS)
    if (bytes.lengthInBytes >= 4) {
      final b0 = bytes[0];
      final b1 = bytes[1];
      final b2 = bytes[2];
      final b3 = bytes[3];
      final isId3 = b0 == 0x49 && b1 == 0x44 && b2 == 0x33;
      final isMp3Frame = b0 == 0xFF && (b1 & 0xE0) == 0xE0;
      final isWav = b0 == 0x52 && b1 == 0x49 && b2 == 0x46 && b3 == 0x46;
      final isOgg = b0 == 0x4F && b1 == 0x67 && b2 == 0x67 && b3 == 0x53;
      return isId3 || isMp3Frame || isWav || isOgg;
    }
    return false;
  }

  static String _normalizeMimeType(String header, {String? fallbackUrl}) {
    if (header.contains('mpeg') || header.contains('mp3')) {
      return 'audio/mpeg';
    }
    if (header.contains('wav')) return 'audio/wav';
    if (header.contains('ogg')) return 'audio/ogg';
    if (header.contains('mp4') || header.contains('m4a')) return 'audio/mp4';

    final lowerUrl = (fallbackUrl ?? '').toLowerCase();
    if (lowerUrl.endsWith('.wav')) return 'audio/wav';
    if (lowerUrl.endsWith('.ogg')) return 'audio/ogg';
    if (lowerUrl.endsWith('.m4a')) return 'audio/mp4';
    return 'audio/mpeg';
  }

  void _rememberMissing(String key) {
    if (_missingKeys.length >= _maxNegativeCacheEntries) {
      _missingKeys.remove(_missingKeys.first);
    }
    _missingKeys.add(key);
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
