import 'package:flutter/foundation.dart';

import '../data/favorite_sites_repository.dart';
import '../models/favorite_site.dart';

/// Tarayıcı favori sitelerinin durumunu ve SQLite işlemlerini yönetir.
class FavoriteSitesController extends ChangeNotifier {
  FavoriteSitesController(this._repository);

  final FavoriteSitesRepository _repository;

  List<FavoriteSite>? _sites;
  bool _isDisposed = false;

  List<FavoriteSite> get sites =>
      List<FavoriteSite>.unmodifiable(_sites ?? const <FavoriteSite>[]);

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  bool isFavorite(String url) {
    final normalized = FavoriteSitesRepository.normalizeUrl(url);
    if (normalized.isEmpty) return false;
    final list = _sites;
    if (list == null) return false;
    return list.any(
      (site) => FavoriteSitesRepository.normalizeUrl(site.url) == normalized,
    );
  }

  Future<void> load() async {
    try {
      _sites = await _repository.getAll();
      _safeNotifyListeners();
    } catch (error) {
      debugPrint('[FavoriteSitesController] Favoriler yuklenemedi: $error');
    }
  }

  /// Site favorilerde yoksa ekler (`true` döner), varsa çıkarır (`false` döner).
  Future<bool> toggleFavorite({
    required String title,
    required String url,
  }) async {
    final normalized = FavoriteSitesRepository.normalizeUrl(url);
    if (normalized.isEmpty) return false;

    if (isFavorite(normalized)) {
      await _repository.deleteByUrl(normalized);
      await load();
      return false;
    }

    await _repository.save(title: title, url: normalized);
    await load();
    return true;
  }

  Future<void> removeSite(FavoriteSite site) async {
    try {
      if (site.id != null) {
        await _repository.deleteById(site.id!);
      } else {
        await _repository.deleteByUrl(site.url);
      }
      await load();
    } catch (error) {
      debugPrint('[FavoriteSitesController] Favori silinemedi: $error');
    }
  }
}
