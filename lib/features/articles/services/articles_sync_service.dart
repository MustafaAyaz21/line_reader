import 'package:flutter/foundation.dart';

import '../data/articles_cache_repository.dart';
import '../models/article.dart';
import 'articles_remote_service.dart';

/// Yerel önbellek okuması, uzak kaynak kontrolü ve çevrimdışı düşüş
/// (offline fallback) davranışını tek noktada yöneten servis.
class ArticlesSyncService {
  ArticlesSyncService({
    required ArticlesCacheStore cacheStore,
    ArticlesRemoteService? remoteService,
  })  : _cacheStore = cacheStore,
        _remoteService = remoteService ?? ArticlesRemoteService(),
        _ownsRemoteService = remoteService == null;

  final ArticlesCacheStore _cacheStore;
  final ArticlesRemoteService _remoteService;
  final bool _ownsRemoteService;

  String get remoteUrl => _remoteService.remoteUrl;

  /// Yerel SQLite önbelleğindeki mevcut makale listesini ve son eşitleme
  /// üst verisini okur. Okuma hatasında bile boş ve güvenli bir sonuç döner.
  Future<({List<Article> articles, ArticleSyncMetadata metadata})>
      loadCachedSnapshot() async {
    try {
      final articles = await _cacheStore.getCachedArticles();
      final metadata = await _cacheStore.getSyncMetadata();
      return (articles: articles, metadata: metadata);
    } catch (error) {
      debugPrint('[ArticlesSyncService] Onbellek okuma hatasi: $error');
      return (
        articles: const <Article>[],
        metadata: ArticleSyncMetadata.empty,
      );
    }
  }

  /// Uzak `articles.json` kaynağını kontrol eder ve başarılı olursa yerel
  /// önbelleği atomik olarak günceller.
  ///
  /// Ağ bağlantısı yoksa veya istek/ayrıştırma başarısız olursa mevcut
  /// yerel önbelleğe hiç dokunmadan onu korur ve [ArticleSyncStatus.offlineFallback]
  /// döndürür (asla hata fırlatmaz).
  Future<ArticleSyncResult> syncArticles({bool ignoreEtag = false}) async {
    final snapshot = await loadCachedSnapshot();
    final existingArticles = snapshot.articles;
    final existingMetadata = snapshot.metadata;

    try {
      final payload = await _remoteService.fetchArticles(
        etag: ignoreEtag ? null : existingMetadata.etag,
        bypassCdnCache: true,
      );

      final now = DateTime.now();

      if (payload.notModified) {
        final refreshedMeta = existingMetadata.copyWith(
          lastSyncedAt: now,
          etag: payload.etag ?? existingMetadata.etag,
          sourceUrl: _remoteService.remoteUrl,
        );
        try {
          await _cacheStore.updateSyncMetadata(refreshedMeta);
        } catch (error) {
          debugPrint('[ArticlesSyncService] Ust veri guncelleme hatasi: $error');
        }

        return ArticleSyncResult(
          status: ArticleSyncStatus.notModified,
          articles: existingArticles,
          metadata: refreshedMeta,
          serverTimeUtc: payload.serverTimeUtc,
        );
      }

      final updatedMeta = ArticleSyncMetadata(
        lastSyncedAt: now,
        etag: payload.etag,
        remoteVersion: payload.remoteVersion,
        sourceUrl: _remoteService.remoteUrl,
      );

      await _cacheStore.replaceArticles(
        payload.articles,
        metadata: updatedMeta,
      );

      return ArticleSyncResult(
        status: ArticleSyncStatus.updated,
        articles: payload.articles,
        metadata: updatedMeta,
        serverTimeUtc: payload.serverTimeUtc,
      );
    } on ArticlesRemoteException catch (error) {
      debugPrint('[ArticlesSyncService] Uzak makale yenileme hatasi: $error');
      return ArticleSyncResult(
        status: ArticleSyncStatus.offlineFallback,
        articles: existingArticles,
        metadata: existingMetadata,
        errorMessage: error.message,
      );
    } catch (error) {
      debugPrint('[ArticlesSyncService] Beklenmeyen yenileme hatasi: $error');
      return ArticleSyncResult(
        status: ArticleSyncStatus.offlineFallback,
        articles: existingArticles,
        metadata: existingMetadata,
        errorMessage:
            'Güncel makaleler kontrol edilemedi; çevrimdışı önbellek korunuyor.',
      );
    }
  }

  Future<void> clearCache() async {
    try {
      await _cacheStore.clearCache();
    } catch (error) {
      debugPrint('[ArticlesSyncService] Onbellek temizleme hatasi: $error');
    }
  }

  void dispose() {
    if (_ownsRemoteService) {
      _remoteService.dispose();
    }
  }
}
