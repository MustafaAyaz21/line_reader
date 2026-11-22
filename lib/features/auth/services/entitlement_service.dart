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
  });

  static const EntitlementStatus standard = EntitlementStatus(isUnlimited: false);

  final bool isUnlimited;
  final String? source;
  final String? codeUsed;
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
    http.Client? httpClient,
  })  : _baseUrl = (baseUrl ?? ApiConfig.browserAiTranslateEndpoint)
            .trim()
            .replaceFirst(RegExp(r'/+$'), ''),
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final String _baseUrl;
  final http.Client _httpClient;
  final bool _ownsClient;

  bool get _hasEndpoint => _baseUrl.startsWith('http');

  @override
  Future<EntitlementStatus?> fetchEntitlement(String idToken) async {
    final token = idToken.trim();
    if (!_hasEndpoint || token.isEmpty) return null;

    try {
      final uri = Uri.parse('$_baseUrl/me');
      final response = await _httpClient
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'User-Agent': 'LineReaderApp',
            },
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;

      return EntitlementStatus(
        isUnlimited: decoded['is_unlimited'] == true,
        source: decoded['source']?.toString(),
        codeUsed: decoded['code_used']?.toString(),
      );
    } catch (error) {
      debugPrint('[CloudflareEntitlementService] /me kontrol hatasi: $error');
      return null;
    }
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

    try {
      final uri = Uri.parse('$_baseUrl/redeem');
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
        return RedeemCodeResult(
          isSuccess: true,
          alreadyUnlimited: data['already_unlimited'] == true,
          code: data['code']?.toString() ?? trimmedCode,
          message: serverMsg.isNotEmpty
              ? serverMsg
              : 'Kod başarıyla onaylandı! Sınırsız yetki aktif.',
        );
      }

      return RedeemCodeResult(
        isSuccess: false,
        message: serverMsg.isNotEmpty
            ? serverMsg
            : 'Kod doğrulanamadı (HTTP ${response.statusCode}).',
      );
    } on TimeoutException {
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'Sunucu zaman aşımına uğradı. Lütfen tekrar deneyin.',
      );
    } on SocketException {
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'İnternet bağlantısı yok. Bağlantınızı kontrol edin.',
      );
    } catch (error) {
      debugPrint('[CloudflareEntitlementService] /redeem hatasi: $error');
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'Kod işlenirken beklenmeyen bir hata oluştu.',
      );
    }
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
