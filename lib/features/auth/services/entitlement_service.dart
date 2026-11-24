import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';

/// Sunucudan okunan kullanıcı sınırsız/AI yetki durumu.
class EntitlementStatus {
  const EntitlementStatus({
    required this.isUnlimited,
    this.source,
    this.codeUsed,
    this.role,
    this.hasSpecialThemes = false,
  });

  static const EntitlementStatus standard = EntitlementStatus(isUnlimited: false);

  final bool isUnlimited;
  final String? source;
  final String? codeUsed;

  /// Yetki rolü (`'admin'` -> Yetkili, `'premium'` -> Premium Üye).
  final String? role;

  /// Kullanıcının gizli "Özel Temalar" koleksiyonuna erişim hakkı.
  final bool hasSpecialThemes;

  bool get isAuthorizedStaff =>
      isUnlimited &&
      ((role?.trim().toLowerCase() == 'admin') ||
          (source?.trim().toLowerCase() == 'admin'));

  /// Geliştirici (admin) hesaplar tüm özel temaları otomatik görür.
  bool get effectiveSpecialThemes => hasSpecialThemes || isAuthorizedStaff;
}

/// Aktivasyon kodu kullanma sonucu.
class RedeemCodeResult {
  const RedeemCodeResult({
    required this.isSuccess,
    required this.message,
    this.alreadyUnlimited = false,
    this.code,
  });

  final bool isSuccess;
  final bool alreadyUnlimited;
  final String? code;
  final String message;
}

/// Cloudflare Worker `/me` ve `/redeem` uç noktaları için soyut istemci.
abstract class EntitlementClient {
  Future<EntitlementStatus?> fetchEntitlement(String idToken);

  Future<RedeemCodeResult> redeemCode({
    required String idToken,
    required String code,
  });

  void dispose();
}

/// Cloudflare Worker + D1 üzerinden kullanıcının sınırsız yetkisini doğrulayan
/// ve aktivasyon kodunu (`READER2026` vb.) işleyen servis.
class CloudflareEntitlementService implements EntitlementClient {
  CloudflareEntitlementService({
    String? baseUrl,
    String? fallbackBaseUrl,
    http.Client? httpClient,
  })  : _baseUrl = (baseUrl ?? ApiConfig.browserAiTranslateEndpoint)
            .trim()
            .replaceFirst(RegExp(r'/+$'), ''),
        _fallbackBaseUrl = (fallbackBaseUrl ??
                (baseUrl == null ? ApiConfig.browserAiFallbackEndpoint : ''))
            .trim()
            .replaceFirst(RegExp(r'/+$'), ''),
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final String _baseUrl;
  final String _fallbackBaseUrl;
  final http.Client _httpClient;
  final bool _ownsClient;
  String? _preferredBaseUrl;

  bool get _hasEndpoint =>
      _baseUrl.startsWith('http') || _fallbackBaseUrl.startsWith('http');

  List<String> _orderedBaseUrls() {
    final ordered = <String>[];
    if (_preferredBaseUrl != null && _preferredBaseUrl!.startsWith('http')) {
      ordered.add(_preferredBaseUrl!);
    }
    if (_baseUrl.startsWith('http') && !ordered.contains(_baseUrl)) {
      ordered.add(_baseUrl);
    }
    if (_fallbackBaseUrl.startsWith('http') &&
        !ordered.contains(_fallbackBaseUrl)) {
      ordered.add(_fallbackBaseUrl);
    }
    return ordered;
  }

  @override
  Future<EntitlementStatus?> fetchEntitlement(String idToken) async {
    final token = idToken.trim();
    if (!_hasEndpoint || token.isEmpty) return null;

    final urls = _orderedBaseUrls();
    for (var i = 0; i < urls.length; i++) {
      final base = urls[i];
      // İlk denemede mobil operatör workers.dev'i düşürüyorsa 12 sn beklemeyip
      // 3.5 sn içinde pages.dev/api yedeğine geç.
      final timeout = i == 0 && urls.length > 1
          ? const Duration(milliseconds: 3500)
          : ApiConfig.requestTimeout;
      try {
        final uri = Uri.parse('$base/me');
        final response = await _httpClient
            .get(
              uri,
              headers: <String, String>{
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
                'User-Agent': 'LineReaderApp',
              },
            )
            .timeout(timeout);

        if (response.statusCode != 200) continue;

        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        );
        if (decoded is! Map) continue;

        _preferredBaseUrl = base;
        final rawSpecial = decoded['has_special_themes'];
        final hasSpecialThemes = rawSpecial == true ||
            rawSpecial == 1 ||
            rawSpecial == '1';

        return EntitlementStatus(
          isUnlimited: decoded['is_unlimited'] == true,
          source: decoded['source']?.toString(),
          codeUsed: decoded['code_used']?.toString(),
          role: decoded['role']?.toString(),
          hasSpecialThemes: hasSpecialThemes,
        );
      } catch (error) {
        debugPrint(
          '[CloudflareEntitlementService] /me kontrol hatasi ($base): $error',
        );
      }
    }
    return null;
  }

  @override
  Future<RedeemCodeResult> redeemCode({
    required String idToken,
    required String code,
  }) async {
    final trimmedCode = code.trim().toUpperCase();
    if (trimmedCode.length < 3) {
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'Lütfen geçerli bir aktivasyon kodu girin.',
      );
    }

    final token = idToken.trim();
    if (!_hasEndpoint || token.isEmpty) {
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'Kod kullanmak için lütfen hesabınızla giriş yapın.',
      );
    }

    Object? lastError;
    for (final base in _orderedBaseUrls()) {
      try {
        final uri = Uri.parse('$base/redeem');
        final response = await _httpClient
            .post(
              uri,
              headers: <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
                'User-Agent': 'LineReaderApp',
              },
              body: jsonEncode(<String, Object?>{'code': trimmedCode}),
            )
            .timeout(ApiConfig.requestTimeout);

        Map<String, Object?> data = const <String, Object?>{};
        try {
          final decoded = jsonDecode(
            utf8.decode(response.bodyBytes, allowMalformed: true),
          );
          if (decoded is Map) {
            data = Map<String, Object?>.from(decoded);
          }
        } catch (_) {}

        final serverMsg = (data['message']?.toString() ?? '').trim();

        if (response.statusCode == 200 && data['ok'] == true) {
          _preferredBaseUrl = base;
          return RedeemCodeResult(
            isSuccess: true,
            alreadyUnlimited: data['already_unlimited'] == true,
            code: data['code']?.toString() ?? trimmedCode,
            message: serverMsg.isNotEmpty
                ? serverMsg
                : 'Kod başarıyla onaylandı! Sınırsız yetki aktif.',
          );
        }

        if (response.statusCode >= 400 && response.statusCode < 500) {
          _preferredBaseUrl = base;
          return RedeemCodeResult(
            isSuccess: false,
            message: serverMsg.isNotEmpty
                ? serverMsg
                : 'Kod doğrulanamadı (HTTP ${response.statusCode}).',
          );
        }

        lastError = 'HTTP ${response.statusCode}';
      } catch (error) {
        lastError = error;
        debugPrint(
          '[CloudflareEntitlementService] /redeem hatasi ($base): $error',
        );
      }
    }

    if (lastError is TimeoutException) {
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'Sunucu zaman aşımına uğradı. Lütfen tekrar deneyin.',
      );
    }
    if (lastError is SocketException) {
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'İnternet bağlantısı yok. Bağlantınızı kontrol edin.',
      );
    }
    return const RedeemCodeResult(
      isSuccess: false,
      message: 'Kod işlenirken beklenmeyen bir hata oluştu.',
    );
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
