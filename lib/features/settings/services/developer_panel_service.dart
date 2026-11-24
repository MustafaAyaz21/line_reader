import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';

/// Geliştirici Paneli kullanıcı yetki kaydı.
class DevEntitlementUser {
  const DevEntitlementUser({
    required this.email,
    required this.source,
    this.isUnlimited = true,
    this.hasSpecialThemes = false,
    this.displayName,
    this.authProvider,
    this.codeUsed,
    this.grantedAt,
  });

  final String email;
  final String source;
  final bool isUnlimited;
  final bool hasSpecialThemes;
  final String? displayName;
  final String? authProvider;
  final String? codeUsed;
  final String? grantedAt;

  bool get isDeveloper =>
      isUnlimited && source.trim().toLowerCase() == 'admin';

  bool get effectiveSpecialThemes => hasSpecialThemes || isDeveloper;

  String? get authProviderLabel {
    final p = (authProvider ?? '').trim().toLowerCase();
    if (p.isEmpty) return null;
    if (p == 'google+password') return 'Google + E-posta';
    if (p.contains('google')) return 'Google';
    if (p.contains('password') || p.contains('email')) return 'E-posta';
    return authProvider;
  }

  factory DevEntitlementUser.fromJson(Map<String, dynamic> json) {
    final rawUnlimited = json['is_unlimited'];
    final isUnlimited = rawUnlimited == null
        ? true
        : (rawUnlimited == true || rawUnlimited == 1 || rawUnlimited == '1');
    final rawSpecial = json['has_special_themes'];
    final hasSpecial =
        rawSpecial == true || rawSpecial == 1 || rawSpecial == '1';
    return DevEntitlementUser(
      email: (json['email'] ?? '').toString().trim(),
      source: (json['source'] ?? 'manual').toString().trim(),
      isUnlimited: isUnlimited,
      hasSpecialThemes: hasSpecial,
      displayName: json['display_name']?.toString().trim(),
      authProvider: json['auth_provider']?.toString().trim(),
      codeUsed: json['code_used']?.toString(),
      grantedAt: json['granted_at']?.toString(),
    );
  }
}

/// Geliştirici Paneli aktivasyon kodu kaydı.
class DevAccessCode {
  const DevAccessCode({
    required this.code,
    required this.maxUses,
    required this.usedCount,
    required this.isActive,
    this.note,
    this.createdAt,
  });

  final String code;
  final int maxUses;
  final int usedCount;
  final bool isActive;
  final String? note;
  final String? createdAt;

  factory DevAccessCode.fromJson(Map<String, dynamic> json) {
    final activeRaw = json['is_active'];
    final active = activeRaw == true || activeRaw == 1 || activeRaw == '1';
    return DevAccessCode(
      code: (json['code'] ?? '').toString().trim(),
      maxUses: int.tryParse((json['max_uses'] ?? '1').toString()) ?? 1,
      usedCount: int.tryParse((json['used_count'] ?? '0').toString()) ?? 0,
      isActive: active,
      note: json['note']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

/// Sunucu işlem sonucu.
class DevActionResult {
  const DevActionResult({
    required this.ok,
    required this.message,
  });

  final bool ok;
  final String message;
}

/// Mobil Geliştirici Paneli makale özet kaydı.
class DevArticleSummary {
  const DevArticleSummary({
    required this.id,
    required this.level,
    required this.title,
    required this.isHidden,
    required this.hasAudio,
    this.hasRelations = true,
    this.hasDescription = true,
    this.publishedAt,
    this.audioUrl,
  });

  final String id;
  final String level;
  final String title;
  final bool isHidden;
  final bool hasAudio;
  final bool hasRelations;
  final bool hasDescription;
  final DateTime? publishedAt;
  final String? audioUrl;

  List<String> get missingLabels => <String>[
        if (!hasAudio) 'Ses yok',
        if (!hasRelations) 'Eş/zıt yok',
        if (!hasDescription) 'Açıklama yok',
      ];

  bool get hasMissingFields => !hasAudio || !hasRelations || !hasDescription;

  factory DevArticleSummary.fromJson(Map<String, dynamic> json) {
    final rawPublished = json['published_at']?.toString();
    return DevArticleSummary(
      id: (json['id'] ?? '').toString().trim(),
      level: (json['level'] ?? 'B1').toString().trim().toUpperCase(),
      title: (json['title'] ?? '').toString().trim(),
      isHidden: json['is_hidden'] == true,
      hasAudio: json['has_audio'] == true,
      hasRelations: json.containsKey('has_relations')
          ? json['has_relations'] == true
          : true,
      hasDescription: json.containsKey('has_description')
          ? json['has_description'] == true
          : true,
      publishedAt:
          rawPublished != null ? DateTime.tryParse(rawPublished)?.toLocal() : null,
      audioUrl: json['audio_url']?.toString(),
    );
  }
}

/// Gemini tarafından üretilen ve yayına hazır makale taslağı.
class DevGeneratedArticle {
  const DevGeneratedArticle({
    required this.id,
    required this.level,
    required this.title,
    required this.content,
    required this.wordMeanings,
    required this.sentenceTranslations,
    required this.wordRelations,
    this.description,
    this.category,
    this.author,
    this.audioUrl,
    this.audioVoice,
    this.audioDurationSec,
    this.audioSegments = const <Map<String, dynamic>>[],
    this.isHidden = false,
  });

  final String id;
  final String level;
  final String title;
  final String content;
  final Map<String, dynamic> wordMeanings;
  final Map<String, dynamic> sentenceTranslations;
  final Map<String, dynamic> wordRelations;
  final String? description;
  final String? category;
  final String? author;
  final String? audioUrl;
  final String? audioVoice;
  final int? audioDurationSec;
  final List<Map<String, dynamic>> audioSegments;
  final bool isHidden;

  bool get hasAudio => audioUrl != null && audioUrl!.trim().isNotEmpty;

  DevGeneratedArticle copyWith({
    String? title,
    String? content,
    String? description,
    String? category,
    String? author,
    String? audioUrl,
    String? audioVoice,
    int? audioDurationSec,
    List<Map<String, dynamic>>? audioSegments,
    bool? isHidden,
  }) {
    return DevGeneratedArticle(
      id: id,
      level: level,
      title: title ?? this.title,
      content: content ?? this.content,
      wordMeanings: wordMeanings,
      sentenceTranslations: sentenceTranslations,
      wordRelations: wordRelations,
      description: description ?? this.description,
      category: category ?? this.category,
      author: author ?? this.author,
      audioUrl: audioUrl ?? this.audioUrl,
      audioVoice: audioVoice ?? this.audioVoice,
      audioDurationSec: audioDurationSec ?? this.audioDurationSec,
      audioSegments: audioSegments ?? this.audioSegments,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'level': level,
        'title': title,
        'content': content,
        if (description != null && description!.trim().isNotEmpty)
          'description': description,
        if (category != null && category!.trim().isNotEmpty)
          'category': category,
        if (author != null && author!.trim().isNotEmpty) 'author': author,
        'word_meanings': wordMeanings,
        'sentence_translations': sentenceTranslations,
        'word_relations': wordRelations,
        if (audioUrl != null && audioUrl!.trim().isNotEmpty)
          'audio_url': audioUrl,
        if (audioVoice != null && audioVoice!.trim().isNotEmpty)
          'audio_voice': audioVoice,
        if (audioDurationSec != null) 'audio_duration_sec': audioDurationSec,
        if (audioSegments.isNotEmpty) 'audio_segments': audioSegments,
        'is_hidden': isHidden,
      };

  factory DevGeneratedArticle.fromJson(Map<String, dynamic> json) {
    return DevGeneratedArticle(
      id: (json['id'] ?? '').toString().trim(),
      level: (json['level'] ?? 'B1').toString().trim().toUpperCase(),
      title: (json['title'] ?? '').toString().trim(),
      content: (json['content'] ?? '').toString().trim(),
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      author: json['author']?.toString(),
      wordMeanings: json['word_meanings'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(
              json['word_meanings'] as Map<String, dynamic>,
            )
          : <String, dynamic>{},
      sentenceTranslations:
          json['sentence_translations'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(
                  json['sentence_translations'] as Map<String, dynamic>,
                )
              : <String, dynamic>{},
      wordRelations: json['word_relations'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(
              json['word_relations'] as Map<String, dynamic>,
            )
          : <String, dynamic>{},
      audioUrl: json['audio_url']?.toString(),
      audioVoice: json['audio_voice']?.toString(),
      audioDurationSec: json['audio_duration_sec'] is num
          ? (json['audio_duration_sec'] as num).round()
          : null,
      isHidden: json['is_hidden'] == true,
    );
  }
}

/// Podcast AI ses üretim yanıtı.
class DevAudioResult {
  const DevAudioResult({
    required this.audioUrl,
    required this.audioVoice,
    required this.audioDurationSec,
    required this.message,
    this.audioSegments = const <Map<String, dynamic>>[],
  });

  final String audioUrl;
  final String audioVoice;
  final int audioDurationSec;
  final String message;
  final List<Map<String, dynamic>> audioSegments;
}

/// Mobil Geliştirici Paneli için sunucu istemcisi.
///
/// APK içinde hiçbir gizli anahtar tutulmaz; her istek kullanıcının imzalı
/// Firebase ID Token'ı ile gider ve Cloudflare Worker D1'de `source='admin'`
/// doğrulaması yapar.
class DeveloperPanelService {
  DeveloperPanelService({
    http.Client? httpClient,
    String? baseUrl,
    String? fallbackBaseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _baseUrl = (baseUrl ?? ApiConfig.browserAiTranslateEndpoint)
            .replaceAll(RegExp(r'/+$'), ''),
        _fallbackBaseUrl = (fallbackBaseUrl ?? ApiConfig.browserAiFallbackEndpoint)
            .replaceAll(RegExp(r'/+$'), '');

  final http.Client _httpClient;
  final bool _ownsClient;
  final String _baseUrl;
  final String _fallbackBaseUrl;
  String? _preferredBaseUrl;

  static const Duration _timeout = Duration(seconds: 25);

  Map<String, String> _headers(String idToken) => <String, String>{
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      };

  List<String> _orderedBaseUrls() {
    final ordered = <String>[];
    if (_preferredBaseUrl != null && _preferredBaseUrl!.isNotEmpty) {
      ordered.add(_preferredBaseUrl!);
    }
    if (!ordered.contains(_baseUrl)) ordered.add(_baseUrl);
    if (_fallbackBaseUrl.isNotEmpty && !ordered.contains(_fallbackBaseUrl)) {
      ordered.add(_fallbackBaseUrl);
    }
    if (_fallbackBaseUrl.isNotEmpty &&
        ApiConfig.browserAiSecondaryFallbackEndpoint.isNotEmpty &&
        !ordered.contains(ApiConfig.browserAiSecondaryFallbackEndpoint)) {
      ordered.add(ApiConfig.browserAiSecondaryFallbackEndpoint);
    }
    return ordered;
  }

  /// Birincil `workers.dev` adresine mobil veride ulaşılamazsa otomatik olarak
  /// `line-reader.pages.dev/api` yedek proxy adresine geçer.
  Future<http.Response> _request(
    String method,
    String path, {
    required String idToken,
    Object? jsonBody,
    Duration timeout = _timeout,
  }) async {
    final bases = _orderedBaseUrls();
    Object? lastError;

    for (var i = 0; i < bases.length; i++) {
      final base = bases[i];
      final isFirstWithFallback = i == 0 && bases.length > 1;
      final attemptTimeout = isFirstWithFallback && timeout.inSeconds <= 25
          ? const Duration(seconds: 8)
          : timeout;
      try {
        final uri = Uri.parse('$base$path');
        final req = http.Request(method, uri)..headers.addAll(_headers(idToken));
        if (jsonBody != null) {
          req.body = jsonEncode(jsonBody);
        }
        final streamed = await _httpClient.send(req).timeout(attemptTimeout);
        final res = await http.Response.fromStream(streamed);
        final hasMore = i < bases.length - 1;
        final isProxyOrGatewayError = res.statusCode == 502 ||
            res.statusCode == 503 ||
            res.statusCode == 504 ||
            (res.statusCode == 404 && !res.body.trimLeft().startsWith('{'));
        if (isProxyOrGatewayError && hasMore) {
          lastError = 'HTTP ${res.statusCode} ($base)';
          continue;
        }
        _preferredBaseUrl = base;
        return res;
      } catch (err) {
        lastError = err;
      }
    }

    throw Exception(
      'Sunucuya bağlanılamadı: ${lastError ?? "Ağ hatası"}',
    );
  }

  Future<List<DevEntitlementUser>> fetchUsers(String idToken) async {
    final res = await _request('GET', '/dev/users', idToken: idToken);
    final data = _decodeJsonMap(res.body);
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['message']?.toString() ??
            'Kullanıcı listesi alınamadı (HTTP ${res.statusCode}).',
      );
    }
    final raw = data['users'];
    if (raw is! List<dynamic>) return const <DevEntitlementUser>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(DevEntitlementUser.fromJson)
        .where((u) => u.email.isNotEmpty)
        .toList(growable: false);
  }

  Future<DevActionResult> grantPremium(String idToken, String email) async {
    final res = await _request(
      'POST',
      '/dev/users',
      idToken: idToken,
      jsonBody: <String, Object?>{'email': email.trim()},
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Premium yetkisi verildi.'
              : 'İşlem başarısız (HTTP ${res.statusCode}).'),
    );
  }

  Future<DevActionResult> setSpecialThemes(
    String idToken,
    String email, {
    required bool enabled,
  }) async {
    final res = await _request(
      'POST',
      '/dev/users',
      idToken: idToken,
      jsonBody: <String, Object?>{
        'email': email.trim(),
        'action': 'set_special_themes',
        'has_special_themes': enabled,
      },
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? (enabled
                  ? 'Özel temalar yetkisi verildi.'
                  : 'Özel temalar yetkisi kaldırıldı.')
              : 'İşlem başarısız (HTTP ${res.statusCode}).'),
    );
  }

  Future<DevActionResult> revokePremium(String idToken, String email) async {
    final res = await _request(
      'DELETE',
      '/dev/users',
      idToken: idToken,
      jsonBody: <String, Object?>{'email': email.trim()},
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Yetki kaldırıldı.'
              : 'İşlem başarısız (HTTP ${res.statusCode}).'),
    );
  }

  Future<List<DevAccessCode>> fetchCodes(String idToken) async {
    final res = await _request('GET', '/dev/codes', idToken: idToken);
    final data = _decodeJsonMap(res.body);
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['message']?.toString() ??
            'Aktivasyon kodları alınamadı (HTTP ${res.statusCode}).',
      );
    }
    final raw = data['codes'];
    if (raw is! List<dynamic>) return const <DevAccessCode>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(DevAccessCode.fromJson)
        .where((c) => c.code.isNotEmpty)
        .toList(growable: false);
  }

  Future<DevActionResult> createCode(
    String idToken, {
    required String code,
    required int maxUses,
    String note = '',
  }) async {
    final res = await _request(
      'POST',
      '/dev/codes',
      idToken: idToken,
      jsonBody: <String, Object?>{
        'code': code.trim().toUpperCase(),
        'max_uses': maxUses,
        'note': note.trim(),
      },
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Aktivasyon kodu oluşturuldu.'
              : 'Kod oluşturulamadı (HTTP ${res.statusCode}).'),
    );
  }

  Future<DevActionResult> toggleCodeActive(
    String idToken, {
    required String code,
    required bool isActive,
  }) async {
    final res = await _request(
      'PATCH',
      '/dev/codes',
      idToken: idToken,
      jsonBody: <String, Object?>{
        'code': code.trim().toUpperCase(),
        'is_active': isActive,
      },
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Kod durumu güncellendi.'
              : 'İşlem başarısız (HTTP ${res.statusCode}).'),
    );
  }

  Future<DevActionResult> deleteCode(String idToken, String code) async {
    final res = await _request(
      'DELETE',
      '/dev/codes',
      idToken: idToken,
      jsonBody: <String, Object?>{'code': code.trim().toUpperCase()},
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Kod silindi.'
              : 'Kod silinemedi (HTTP ${res.statusCode}).'),
    );
  }

  Future<List<DevArticleSummary>> fetchArticles(String idToken) async {
    final res = await _request('GET', '/dev/articles', idToken: idToken);
    final data = _decodeJsonMap(res.body);
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['message']?.toString() ??
            'Makale listesi alınamadı (HTTP ${res.statusCode}).',
      );
    }
    final raw = data['articles'];
    if (raw is! List<dynamic>) return const <DevArticleSummary>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(DevArticleSummary.fromJson)
        .where((a) => a.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<DevGeneratedArticle> generateArticle(
    String idToken, {
    required String level,
    String topic = '',
  }) async {
    final res = await _request(
      'POST',
      '/dev/articles/generate',
      idToken: idToken,
      jsonBody: <String, Object?>{
        'level': level.trim().toUpperCase(),
        'topic': topic.trim(),
      },
      timeout: const Duration(seconds: 65),
    );
    final data = _decodeJsonMap(res.body);
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['message']?.toString() ??
            'Makale üretilemedi (HTTP ${res.statusCode}).',
      );
    }
    final rawArticle = data['article'];
    if (rawArticle is! Map<String, dynamic>) {
      throw Exception('Sunucu geçerli makale verisi döndürmedi.');
    }
    return DevGeneratedArticle.fromJson(rawArticle);
  }

  Future<DevAudioResult> generateArticleAudio(
    String idToken, {
    required String id,
    required String title,
    required String content,
    String voice = 'Kore',
  }) async {
    final res = await _request(
      'POST',
      '/dev/articles/audio',
      idToken: idToken,
      jsonBody: <String, Object?>{
        'id': id,
        'title': title,
        'content': content,
        'voice': voice,
      },
      timeout: const Duration(seconds: 75),
    );
    final data = _decodeJsonMap(res.body);
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['message']?.toString() ??
            'Podcast AI sesi üretilemedi (HTTP ${res.statusCode}).',
      );
    }
    final rawSegments = data['audio_segments'];
    final parsedSegments = rawSegments is List<dynamic>
        ? rawSegments
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];

    return DevAudioResult(
      audioUrl: (data['audio_url'] ?? '').toString(),
      audioVoice: (data['audio_voice'] ?? voice).toString(),
      audioDurationSec: data['audio_duration_sec'] is num
          ? (data['audio_duration_sec'] as num).round()
          : 0,
      audioSegments: parsedSegments,
      message: data['message']?.toString() ?? 'Podcast AI sesi oluşturuldu.',
    );
  }

  Future<DevActionResult> publishArticle(
    String idToken,
    DevGeneratedArticle article,
  ) async {
    final res = await _request(
      'POST',
      '/dev/articles/publish',
      idToken: idToken,
      jsonBody: <String, Object?>{'article': article.toJson()},
      timeout: const Duration(seconds: 25),
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Makale yayınlandı!'
              : 'Yayınlama başarısız (HTTP ${res.statusCode}).'),
    );
  }

  Future<DevActionResult> toggleArticleHidden(
    String idToken, {
    required String id,
    required bool isHidden,
  }) async {
    final res = await _request(
      'PATCH',
      '/dev/articles',
      idToken: idToken,
      jsonBody: <String, Object?>{'id': id, 'is_hidden': isHidden},
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Makale güncellendi.'
              : 'İşlem başarısız (HTTP ${res.statusCode}).'),
    );
  }

  Future<DevActionResult> deleteArticle(String idToken, String id) async {
    final res = await _request(
      'DELETE',
      '/dev/articles',
      idToken: idToken,
      jsonBody: <String, Object?>{'id': id},
    );
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Makale silindi.'
              : 'Makale silinemedi (HTTP ${res.statusCode}).'),
    );
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const <String, dynamic>{};
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
