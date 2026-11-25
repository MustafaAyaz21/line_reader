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
    this.emailVerified = false,
  });

  static const EntitlementStatus standard = EntitlementStatus(isUnlimited: false);

  final bool isUnlimited;
  final String? source;
  final String? codeUsed;

  /// Yetki rolü (`'admin'` -> Yetkili, `'premium'` -> Premium Üye).
  final String? role;

  /// Kullanıcının gizli "Özel Temalar" koleksiyonuna erişim hakkı.
  final bool hasSpecialThemes;

  /// D1 veya Firebase üzerinden e-posta doğrulama durumu.
  final bool emailVerified;

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

/// 6 haneli e-posta OTP gönderme / doğrulama sonucu.
class OtpActionResult {
  const OtpActionResult({
    required this.isSuccess,
    required this.message,
    this.fallbackToLink = false,
    this.cooldownSeconds = 0,
  });

  final bool isSuccess;
  final String message;
  final bool fallbackToLink;
  final int cooldownSeconds;
}

/// Cloudflare Worker `/me` ve `/redeem` uç noktaları için soyut istemci.
abstract class EntitlementClient {
  Future<EntitlementStatus?> fetchEntitlement(String idToken);

  Future<RedeemCodeResult> redeemCode({
    required String idToken,
    required String code,
  });

  Future<OtpActionResult> sendEmailVerificationOtp(
    String idToken, {
    String lang = 'tr',
  }) async =>
      const OtpActionResult(
        isSuccess: false,
        fallbackToLink: true,
        message: '',
      );

  Future<OtpActionResult> verifyEmailOtp({
    required String idToken,
    required String code,
    String lang = 'tr',
  }) async =>
      const OtpActionResult(
        isSuccess: false,
        message: '',
      );

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
    if (_fallbackBaseUrl.isNotEmpty &&
        ApiConfig.browserAiSecondaryFallbackEndpoint.startsWith('http') &&
        !ordered.contains(ApiConfig.browserAiSecondaryFallbackEndpoint)) {
      ordered.add(ApiConfig.browserAiSecondaryFallbackEndpoint);
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
          emailVerified: decoded['email_verified'] == true,
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
  Future<OtpActionResult> sendEmailVerificationOtp(
    String idToken, {
    String lang = 'tr',
  }) async {
    final token = idToken.trim();
    if (!_hasEndpoint || token.isEmpty) {
      return const OtpActionResult(
        isSuccess: false,
        fallbackToLink: true,
        message: 'Oturum doğrulanamadı.',
      );
    }

    for (final base in _orderedBaseUrls()) {
      try {
        final uri = Uri.parse('$base/auth/send-otp');
        final response = await _httpClient
            .post(
              uri,
              headers: <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(<String, Object?>{'lang': lang}),
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
        final cooldown = (data['cooldown_seconds'] as num?)?.toInt() ?? 0;

        if (response.statusCode == 200 && data['ok'] == true) {
          _preferredBaseUrl = base;
          return OtpActionResult(
            isSuccess: true,
            cooldownSeconds: cooldown > 0 ? cooldown : 60,
            message: serverMsg.isNotEmpty
                ? serverMsg
                : '6 haneli doğrulama kodu e-posta adresinize gönderildi.',
          );
        }

        if (data['fallback_to_firebase_link'] == true) {
          return OtpActionResult(
            isSuccess: false,
            fallbackToLink: true,
            message: serverMsg,
          );
        }

        if (response.statusCode >= 400 && response.statusCode < 500) {
          _preferredBaseUrl = base;
          return OtpActionResult(
            isSuccess: false,
            cooldownSeconds: cooldown,
            message: serverMsg.isNotEmpty
                ? serverMsg
                : 'Doğrulama kodu gönderilemedi.',
          );
        }
      } catch (error) {
        debugPrint(
          '[CloudflareEntitlementService] /auth/send-otp hatasi ($base): $error',
        );
      }
    }

    return const OtpActionResult(
      isSuccess: false,
      fallbackToLink: true,
      message: 'Kod servisine ulaşılamadı.',
    );
  }

  @override
  Future<OtpActionResult> verifyEmailOtp({
    required String idToken,
    required String code,
    String lang = 'tr',
  }) async {
    final token = idToken.trim();
    final digits = code.replaceAll(RegExp(r'\D'), '').trim();
    if (!_hasEndpoint || token.isEmpty) {
      return const OtpActionResult(
        isSuccess: false,
        message: 'Oturum doğrulanamadı.',
      );
    }
    if (digits.length != 6) {
      return const OtpActionResult(
        isSuccess: false,
        message: 'Lütfen 6 haneli doğrulama kodunu girin.',
      );
    }

    for (final base in _orderedBaseUrls()) {
      try {
        final uri = Uri.parse('$base/auth/verify-otp');
        final response = await _httpClient
            .post(
              uri,
              headers: <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(<String, Object?>{
                'code': digits,
                'lang': lang,
              }),
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
          return OtpActionResult(
            isSuccess: true,
            message: serverMsg.isNotEmpty ? serverMsg : 'E-posta doğrulandı!',
          );
        }

        if (response.statusCode >= 400 && response.statusCode < 500) {
          _preferredBaseUrl = base;
          return OtpActionResult(
            isSuccess: false,
            message: serverMsg.isNotEmpty
                ? serverMsg
                : 'Kod doğrulanamadı (HTTP ${response.statusCode}).',
          );
        }
      } catch (error) {
        debugPrint(
          '[CloudflareEntitlementService] /auth/verify-otp hatasi ($base): $error',
        );
      }
    }

    return const OtpActionResult(
      isSuccess: false,
      message: 'Doğrulama sunucusuna bağlanılamadı. Lütfen tekrar deneyin.',
    );
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
