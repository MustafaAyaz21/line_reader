import 'package:flutter/foundation.dart';

import '../models/article.dart';
import '../services/articles_sync_service.dart';

/// Makale önbelleğini ve canlı yenileme yaşam döngüsünü yöneten denetleyici.
///
/// - Uygulama açılışında yerel önbelleği anında yükler ve arka planda uzak
///   kaynağı kontrol eder.
/// - Makaleler ekranına girildiğinde ve aşağı çekerek yenilemede güncel
///   veriyi çeker.
/// - Eşzamanlı yenileme isteklerini tek bir canlı istekte birleştirir.
/// - Ağ hatasında mevcut önbellekteki verileri korur ve uygulamayı bozmaz.
class ArticlesController extends ChangeNotifier {
  ArticlesController(
    this._syncService, {
    Duration silentCooldown = const Duration(seconds: 30),
  }) : _silentCooldown = silentCooldown;

  final ArticlesSyncService _syncService;
  final Duration _silentCooldown;

  List<Article> _articles = const <Article>[];
  ArticleSyncMetadata _metadata = ArticleSyncMetadata.empty;
  bool _isLoadingCache = false;
  bool _hasLoadedCache = false;
  bool _isRefreshing = false;
  bool _isOfflineFallback = false;
  String? _lastErrorMessage;
  DateTime? _lastAttemptAt;
  bool _isDisposed = false;

  Future<void>? _activeCacheLoad;
  Future<ArticleSyncResult>? _activeRefresh;

  List<Article> get articles => _articles;
  ArticleSyncMetadata get metadata => _metadata;
  DateTime? get lastSyncedAt => _metadata.lastSyncedAt;
  bool get isLoadingCache => _isLoadingCache;
  bool get hasLoadedCache => _hasLoadedCache;
  bool get isRefreshing => _isRefreshing;
  bool get isOfflineFallback => _isOfflineFallback;
  String? get lastErrorMessage => _lastErrorMessage;
  bool get hasArticles => _articles.isNotEmpty;

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Yerel SQLite önbelleğindeki makaleleri hızlıca belleğe alır.
  Future<void> loadCache() {
    final inFlight = _activeCacheLoad;
    if (inFlight != null) return inFlight;

    final future = _loadCacheInternal();
    _activeCacheLoad = future;
    return future.whenComplete(() {
      if (identical(_activeCacheLoad, future)) {
        _activeCacheLoad = null;
      }
    });
  }

  Future<void> _loadCacheInternal() async {
    _isLoadingCache = true;
    _safeNotify();

    try {
      final snapshot = await _syncService.loadCachedSnapshot();
      // Eşzamanlı tamamlanan bir uzak yenileme daha taze veri getirdiyse
      // eski önbellekle üzerine yazma.
      if (!_hasLoadedCache || _articles.isEmpty) {
        _articles = List<Article>.unmodifiable(snapshot.articles);
      }
      if (snapshot.metadata.lastSyncedAt != null ||
          _metadata.lastSyncedAt == null) {
        _metadata = snapshot.metadata;
      }
      _hasLoadedCache = true;
    } catch (error) {
      debugPrint('[ArticlesController] Onbellek yukleme hatasi: $error');
      _hasLoadedCache = true;
    } finally {
      _isLoadingCache = false;
      _safeNotify();
    }
  }

  /// Arka planda sessizce uzak kaynağı kontrol eder; ağ kapalıysa sessizce
  /// mevcut önbelleği korur.
  Future<ArticleSyncResult?> refreshSilently({bool force = false}) async {
    if (!force) {
      final lastAttempt = _lastAttemptAt;
      if (lastAttempt != null &&
          DateTime.now().difference(lastAttempt) < _silentCooldown) {
        return null;
      }
    }
    return refresh(silent: true, force: force);
  }

  /// Makaleler ekranına girildiğinde önbelleği garanti altına alır ve uzak
  /// kaynaktan taze veri kontrolü başlatır.
  Future<void> onScreenEntered() async {
    if (!_hasLoadedCache) {
      await loadCache();
    }
    await refresh(silent: true, force: true);
  }

  /// Uzak makale kaynağını kontrol eder ve yerel önbelleği günceller.
  ///
  /// - [silent] `true` ise kullanıcıya hata banner'ı/mesajı yansıtılmaz.
  /// - [force] `true` ise bekleme süresi (cooldown) ve ETag atlanır (ör.
  ///   aşağı çekerek yenileme veya ekran açılışı).
  Future<ArticleSyncResult> refresh({
    bool silent = false,
    bool force = false,
  }) {
    final inFlight = _activeRefresh;
    if (inFlight != null) return inFlight;

    final future = _refreshInternal(silent: silent, force: force);
    _activeRefresh = future;
    return future.whenComplete(() {
      if (identical(_activeRefresh, future)) {
        _activeRefresh = null;
      }
    });
  }

  Future<ArticleSyncResult> _refreshInternal({
    required bool silent,
    required bool force,
  }) async {
    if (!_hasLoadedCache) {
      await loadCache();
    }

    _isRefreshing = true;
    if (!silent) {
      _lastErrorMessage = null;
    }
    _safeNotify();

    try {
      // Kullanıcı aşağı çektiğinde (`!silent && force`) ETag atlanarak tam
      // doğrulama yapılır; sessiz kontrollerde ETag ile bant genişliği korunur.
      final result = await _syncService.syncArticles(
        ignoreEtag: !silent && force,
      );
      _lastAttemptAt = DateTime.now();

      _articles = List<Article>.unmodifiable(result.articles);
      _metadata = result.metadata;
      _hasLoadedCache = true;
      _isOfflineFallback = result.isOfflineFallback;
      _lastErrorMessage = result.isOfflineFallback
          ? (silent ? _lastErrorMessage : result.errorMessage)
          : null;

      return result;
    } catch (error) {
      debugPrint('[ArticlesController] Yenileme hatasi: $error');
      _lastAttemptAt = DateTime.now();
      _isOfflineFallback = true;
      final fallbackMessage =
          'Güncel makaleler kontrol edilemedi; çevrimdışı önbellek korunuyor.';
      if (!silent) {
        _lastErrorMessage = fallbackMessage;
      }
      return ArticleSyncResult(
        status: ArticleSyncStatus.offlineFallback,
        articles: _articles,
        metadata: _metadata,
        errorMessage: fallbackMessage,
      );
    } finally {
      _isRefreshing = false;
      _safeNotify();
    }
  }

  Future<void> clearCache() async {
    await _syncService.clearCache();
    _articles = const <Article>[];
    _metadata = ArticleSyncMetadata.empty;
    _isOfflineFallback = false;
    _lastErrorMessage = null;
    _safeNotify();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _syncService.dispose();
    super.dispose();
  }
}
