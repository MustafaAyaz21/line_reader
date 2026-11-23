import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';

/// Geliştirici Paneli kullanıcı yetki kaydı.
class DevEntitlementUser {
  const DevEntitlementUser({
    required this.email,
    required this.source,
    this.codeUsed,
    this.grantedAt,
  });

  final String email;
  final String source;
  final String? codeUsed;
  final String? grantedAt;

  bool get isDeveloper => source.trim().toLowerCase() == 'admin';

  factory DevEntitlementUser.fromJson(Map<String, dynamic> json) {
    return DevEntitlementUser(
      email: (json['email'] ?? '').toString().trim(),
      source: (json['source'] ?? 'manual').toString().trim(),
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
    this.audioUrl,
  });

  final String id;
  final String level;
  final String title;
  final bool isHidden;
  final bool hasAudio;
  final String? audioUrl;

  factory DevArticleSummary.fromJson(Map<String, dynamic> json) {
    return DevArticleSummary(
      id: (json['id'] ?? '').toString().trim(),
      level: (json['level'] ?? 'B1').toString().trim().toUpperCase(),
      title: (json['title'] ?? '').toString().trim(),
      isHidden: json['is_hidden'] == true,
      hasAudio: json['has_audio'] == true,
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
    this.audioUrl,
    this.audioVoice,
    this.audioDurationSec,
    this.isHidden = false,
  });

  final String id;
  final String level;
  final String title;
  final String content;
  final Map<String, dynamic> wordMeanings;
  final Map<String, dynamic> sentenceTranslations;
  final Map<String, dynamic> wordRelations;
  final String? audioUrl;
  final String? audioVoice;
  final int? audioDurationSec;
  final bool isHidden;

  bool get hasAudio => audioUrl != null && audioUrl!.trim().isNotEmpty;

  DevGeneratedArticle copyWith({
    String? title,
    String? content,
    String? audioUrl,
    String? audioVoice,
    int? audioDurationSec,
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
      audioUrl: audioUrl ?? this.audioUrl,
      audioVoice: audioVoice ?? this.audioVoice,
      audioDurationSec: audioDurationSec ?? this.audioDurationSec,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'level': level,
        'title': title,
        'content': content,
        'word_meanings': wordMeanings,
        'sentence_translations': sentenceTranslations,
        'word_relations': wordRelations,
        if (audioUrl != null && audioUrl!.trim().isNotEmpty)
          'audio_url': audioUrl,
        if (audioVoice != null && audioVoice!.trim().isNotEmpty)
          'audio_voice': audioVoice,
        if (audioDurationSec != null) 'audio_duration_sec': audioDurationSec,
        'is_hidden': isHidden,
      };

  factory DevGeneratedArticle.fromJson(Map<String, dynamic> json) {
    return DevGeneratedArticle(
      id: (json['id'] ?? '').toString().trim(),
      level: (json['level'] ?? 'B1').toString().trim().toUpperCase(),
      title: (json['title'] ?? '').toString().trim(),
      content: (json['content'] ?? '').toString().trim(),
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
  });

  final String audioUrl;
  final String audioVoice;
  final int audioDurationSec;
  final String message;
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
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _baseUrl = (baseUrl ?? ApiConfig.browserAiTranslateEndpoint)
            .replaceAll(RegExp(r'/+$'), '');

  final http.Client _httpClient;
  final bool _ownsClient;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 12);

  Map<String, String> _headers(String idToken) => <String, String>{
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      };

  Future<List<DevEntitlementUser>> fetchUsers(String idToken) async {
    final res = await _httpClient
        .get(Uri.parse('$_baseUrl/dev/users'), headers: _headers(idToken))
        .timeout(_timeout);
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
    final res = await _httpClient
        .post(
          Uri.parse('$_baseUrl/dev/users'),
          headers: _headers(idToken),
          body: jsonEncode(<String, Object?>{'email': email.trim()}),
        )
        .timeout(_timeout);
    final data = _decodeJsonMap(res.body);
    return DevActionResult(
      ok: res.statusCode == 200 && data['ok'] == true,
      message: data['message']?.toString() ??
          (res.statusCode == 200
              ? 'Premium yetkisi verildi.'
              : 'İşlem başarısız (HTTP ${res.statusCode}).'),
    );
  }

  Future<DevActionResult> revokePremium(String idToken, String email) async {
    final req = http.Request('DELETE', Uri.parse('$_baseUrl/dev/users'))
      ..headers.addAll(_headers(idToken))
      ..body = jsonEncode(<String, Object?>{'email': email.trim()});
    final streamed = await _httpClient.send(req).timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
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
    final res = await _httpClient
        .get(Uri.parse('$_baseUrl/dev/codes'), headers: _headers(idToken))
        .timeout(_timeout);
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
    final res = await _httpClient
        .post(
          Uri.parse('$_baseUrl/dev/codes'),
          headers: _headers(idToken),
          body: jsonEncode(<String, Object?>{
            'code': code.trim().toUpperCase(),
            'max_uses': maxUses,
            'note': note.trim(),
          }),
        )
        .timeout(_timeout);
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
    final res = await _httpClient
        .patch(
          Uri.parse('$_baseUrl/dev/codes'),
          headers: _headers(idToken),
          body: jsonEncode(<String, Object?>{
            'code': code.trim().toUpperCase(),
            'is_active': isActive,
          }),
        )
        .timeout(_timeout);
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
    final req = http.Request('DELETE', Uri.parse('$_baseUrl/dev/codes'))
      ..headers.addAll(_headers(idToken))
      ..body = jsonEncode(<String, Object?>{'code': code.trim().toUpperCase()});
    final streamed = await _httpClient.send(req).timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
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
    final res = await _httpClient
        .get(Uri.parse('$_baseUrl/dev/articles'), headers: _headers(idToken))
        .timeout(_timeout);
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
    final res = await _httpClient
        .post(
          Uri.parse('$_baseUrl/dev/articles/generate'),
          headers: _headers(idToken),
          body: jsonEncode(<String, Object?>{
            'level': level.trim().toUpperCase(),
            'topic': topic.trim(),
          }),
        )
        .timeout(const Duration(seconds: 65));
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
    final res = await _httpClient
        .post(
          Uri.parse('$_baseUrl/dev/articles/audio'),
          headers: _headers(idToken),
          body: jsonEncode(<String, Object?>{
            'id': id,
            'title': title,
            'content': content,
            'voice': voice,
          }),
        )
        .timeout(const Duration(seconds: 75));
    final data = _decodeJsonMap(res.body);
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['message']?.toString() ??
            'Podcast AI sesi üretilemedi (HTTP ${res.statusCode}).',
      );
    }
    return DevAudioResult(
      audioUrl: (data['audio_url'] ?? '').toString(),
      audioVoice: (data['audio_voice'] ?? voice).toString(),
      audioDurationSec: data['audio_duration_sec'] is num
          ? (data['audio_duration_sec'] as num).round()
          : 0,
      message: data['message']?.toString() ?? 'Podcast AI sesi oluşturuldu.',
    );
  }

  Future<DevActionResult> publishArticle(
    String idToken,
    DevGeneratedArticle article,
  ) async {
    final res = await _httpClient
        .post(
          Uri.parse('$_baseUrl/dev/articles/publish'),
          headers: _headers(idToken),
          body: jsonEncode(<String, Object?>{'article': article.toJson()}),
        )
        .timeout(const Duration(seconds: 25));
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
    final res = await _httpClient
        .patch(
          Uri.parse('$_baseUrl/dev/articles'),
          headers: _headers(idToken),
          body: jsonEncode(<String, Object?>{'id': id, 'is_hidden': isHidden}),
        )
        .timeout(_timeout);
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
    final req = http.Request('DELETE', Uri.parse('$_baseUrl/dev/articles'))
      ..headers.addAll(_headers(idToken))
      ..body = jsonEncode(<String, Object?>{'id': id});
    final streamed = await _httpClient.send(req).timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
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
