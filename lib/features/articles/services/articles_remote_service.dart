import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/article.dart';

/// Uzak makale JSON kaynağına erişim veya ayrıştırma sırasında oluşan hata.
class ArticlesRemoteException implements Exception {
  const ArticlesRemoteException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode != null
      ? 'ArticlesRemoteException($statusCode): $message'
      : 'ArticlesRemoteException: $message';
}

/// Yapılandırılabilir uzak JSON kaynağından (`ApiConfig.articlesJsonUrl`)
/// güncel makale listesini çeken servis (birincil adres başarısız olursa
/// isteğe bağlı yedek adresi dener).
class ArticlesRemoteService {
  ArticlesRemoteService({
    http.Client? httpClient,
    String? remoteUrl,
    String? fallbackUrl,
    Duration? timeout,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        remoteUrl = (remoteUrl != null && remoteUrl.trim().isNotEmpty)
            ? remoteUrl.trim()
            : ApiConfig.articlesJsonUrl,
        fallbackUrl = fallbackUrl != null
            ? (fallbackUrl.trim().isEmpty ? null : fallbackUrl.trim())
            : (remoteUrl == null ? ApiConfig.articlesFallbackJsonUrl : null),
        _timeout = timeout ?? ApiConfig.requestTimeout;

  static const Map<String, String> _baseHeaders = <String, String>{
    'User-Agent': 'LineReaderApp',
    'Accept': 'application/json',
    'Cache-Control': 'no-cache, no-store, must-revalidate',
    'Pragma': 'no-cache',
  };

  final http.Client _httpClient;
  final bool _ownsClient;
  final String remoteUrl;
  final String? fallbackUrl;
  final Duration _timeout;

  /// Uzak `articles.json` kaynağını sorgular.
  ///
  /// - [etag] verilirse `If-None-Match` başlığı gönderir; sunucu HTTP 304
  ///   döndürürse [ArticleFeedPayload.notModified] döner.
  /// - Hem üst düzey JSON dizisini (`[...]`) hem de sarmalanmış nesneyi
  ///   (`{"version": 1, "articles": [...]}`) destekler.
  /// - Birincil adres başarısız olursa varsa [fallbackUrl] denenir.
  /// - Tüm kaynaklar başarısız olursa [ArticlesRemoteException] fırlatır;
  ///   böylece yerel önbellek asla bozuk veriyle ezilmez.
  Future<ArticleFeedPayload> fetchArticles({
    String? etag,
    bool bypassCdnCache = true,
  }) async {
    try {
      return await _fetchFromUrl(
        remoteUrl,
        etag: etag,
        bypassCdnCache: bypassCdnCache,
      );
    } on ArticlesRemoteException catch (primaryError) {
      final backup = fallbackUrl;
      if (backup == null || backup == remoteUrl) {
        rethrow;
      }
      try {
        // Yedek uç nokta farklı ETag üretir; temiz yanıt almak için ETag gönderme.
        return await _fetchFromUrl(
          backup,
          etag: null,
          bypassCdnCache: bypassCdnCache,
        );
      } on ArticlesRemoteException {
        throw primaryError;
      }
    }
  }

  Future<ArticleFeedPayload> _fetchFromUrl(
    String targetUrl, {
    String? etag,
    required bool bypassCdnCache,
  }) async {
    final parsedUri = Uri.tryParse(targetUrl);
    if (parsedUri == null || !parsedUri.hasScheme) {
      throw const ArticlesRemoteException(
        'Geçersiz makale veri kaynağı adresi.',
      );
    }

    final uri = bypassCdnCache
        ? parsedUri.replace(
            queryParameters: <String, String>{
              ...parsedUri.queryParameters,
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          )
        : parsedUri;

    final headers = <String, String>{
      ..._baseHeaders,
      if (etag != null && etag.trim().isNotEmpty) 'If-None-Match': etag.trim(),
    };

    http.Response response;
    try {
      response = await _httpClient.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw const ArticlesRemoteException(
        'Makale sunucusu zaman aşımına uğradı.',
      );
    } on SocketException {
      throw const ArticlesRemoteException(
        'İnternet bağlantısı kurulamadı.',
      );
    } on http.ClientException {
      throw const ArticlesRemoteException(
        'Makale sunucusuna erişilemedi.',
      );
    } catch (error) {
      throw ArticlesRemoteException('Makaleler çekilirken hata oluştu: $error');
    }

    final responseEtag = response.headers['etag']?.trim();

    if (response.statusCode == 304) {
      return ArticleFeedPayload.notModified(etag: responseEtag ?? etag);
    }

    if (response.statusCode != 200) {
      throw ArticlesRemoteException(
        'Makale kaynağı yanıt vermedi (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    final decoded = _decodeJsonBody(response.bodyBytes);
    return _parsePayload(decoded, etag: responseEtag);
  }

  Object? _decodeJsonBody(List<int> bodyBytes) {
    try {
      final text = utf8.decode(bodyBytes, allowMalformed: true).trim();
      if (text.isEmpty) {
        throw const ArticlesRemoteException('Makale kaynağı boş yanıt döndürdü.');
      }
      return jsonDecode(text);
    } on ArticlesRemoteException {
      rethrow;
    } catch (_) {
      throw const ArticlesRemoteException(
        'Makale verisi geçerli JSON biçiminde değil.',
      );
    }
  }

  ArticleFeedPayload _parsePayload(Object? decoded, {String? etag}) {
    List<Object?> rawItems;
    String? remoteVersion;
    DateTime? updatedAt;

    if (decoded is List) {
      rawItems = decoded.cast<Object?>();
    } else if (decoded is Map) {
      final map = Map<String, Object?>.from(decoded);
      final dynamicList = map['articles'] ?? map['items'] ?? map['data'];
      if (dynamicList is! List) {
        throw const ArticlesRemoteException(
          'Makale JSON yapısında "articles" listesi bulunamadı.',
        );
      }
      rawItems = dynamicList.cast<Object?>();

      final rawVersion = map['version'];
      if (rawVersion != null && rawVersion.toString().trim().isNotEmpty) {
        remoteVersion = rawVersion.toString().trim();
      }

      final rawUpdatedAt = map['updated_at'] ?? map['updatedAt'];
      if (rawUpdatedAt is String && rawUpdatedAt.trim().isNotEmpty) {
        updatedAt = DateTime.tryParse(rawUpdatedAt.trim());
      }
    } else {
      throw const ArticlesRemoteException(
        'Beklenmeyen makale JSON kök yapısı.',
      );
    }

    final articles = <Article>[];
    final seenIds = <String>{};

    for (var i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is! Map) continue;

      final article = Article.tryFromJson(
        Map<String, Object?>.from(item),
        fallbackIndex: articles.length,
      );
      if (article == null) continue;

      // Aynı kimliğe sahip yinelenen kayıtları atla.
      if (seenIds.add(article.id)) {
        articles.add(article);
      }
    }

    return ArticleFeedPayload(
      articles: List<Article>.unmodifiable(articles),
      remoteVersion: remoteVersion,
      updatedAt: updatedAt,
      etag: etag,
    );
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
