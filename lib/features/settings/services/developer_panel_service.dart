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
