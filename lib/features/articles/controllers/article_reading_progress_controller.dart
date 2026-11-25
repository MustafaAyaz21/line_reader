import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/settings_repository.dart';
import '../models/article.dart';
import '../models/article_reading_progress.dart';

/// Kullanıcının okuduğu makalelerdeki ilerleme yüzdesini ve en son okunan
/// makaleyi kalıcı olarak SQLite `app_settings` tablosunda yönetir.
class ArticleReadingProgressController extends ChangeNotifier {
  ArticleReadingProgressController({
    SettingsRepository? repository,
    DateTime Function()? nowProvider,
  })  : _repository = repository,
        _nowProvider = nowProvider ?? (() => DateTime.now().toUtc());

  static const String _storageKey = 'article_reading_progress_v1';
  static const int _maxStoredArticles = 60;

  /// Ana Menü kartı ile Makale Okuma ekranını anında senkronize tutan ortak örnek.
  static final ArticleReadingProgressController shared =
      ArticleReadingProgressController();

  final SettingsRepository? _repository;
  final DateTime Function() _nowProvider;

  final Map<String, ArticleReadingProgress> _itemsById =
      <String, ArticleReadingProgress>{};
  String? _lastArticleId;
  String? _dismissedArticleId;
  bool _hasLoaded = false;

  bool get hasLoaded => _hasLoaded;

  bool isContinueReadingDismissed(String articleId) {
    final trimmed = articleId.trim();
    return trimmed.isNotEmpty && _dismissedArticleId == trimmed;
  }

  Future<void> dismissContinueReading(String articleId) async {
    final trimmed = articleId.trim();
    if (trimmed.isEmpty || _dismissedArticleId == trimmed) return;
    _dismissedArticleId = trimmed;
    notifyListeners();
    await _persistState();
  }

  ArticleReadingProgress? get lastProgress {
    final id = _lastArticleId;
    if (id != null && _itemsById.containsKey(id)) {
      return _itemsById[id];
    }
    if (_itemsById.isEmpty) return null;
    ArticleReadingProgress? newest;
    for (final entry in _itemsById.values) {
      if (newest == null || entry.updatedAt.isAfter(newest.updatedAt)) {
        newest = entry;
      }
    }
    return newest;
  }

  ArticleReadingProgress? progressForArticle(String articleId) {
    final trimmed = articleId.trim();
    if (trimmed.isEmpty) return null;
    return _itemsById[trimmed];
  }

  SettingsRepository _resolveRepository() {
    return _repository ?? SettingsRepository(AppDatabase.instance);
  }

  Future<void> load({bool force = false}) async {
    if (_hasLoaded && !force) return;
    _hasLoaded = true;
    try {
      final raw = await _resolveRepository().getString(_storageKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final loaded = <String, ArticleReadingProgress>{};
      final rawItems = decoded['items'];
      if (rawItems is Map) {
        for (final entry in rawItems.entries) {
          final parsed = ArticleReadingProgress.fromJson(entry.value);
          if (parsed != null) {
            loaded[parsed.articleId] = parsed;
          }
        }
      }

      if (loaded.isEmpty) return;
      for (final entry in loaded.entries) {
        final existing = _itemsById[entry.key];
        if (existing == null ||
            entry.value.updatedAt.isAfter(existing.updatedAt)) {
          _itemsById[entry.key] = entry.value;
        }
      }

      final storedLastId = (decoded['lastArticleId'] as String?)?.trim();
      if (_lastArticleId == null &&
          storedLastId != null &&
          _itemsById.containsKey(storedLastId)) {
        _lastArticleId = storedLastId;
      }
      final storedDismissed =
          (decoded['dismissedArticleId'] as String?)?.trim();
      if (_dismissedArticleId == null &&
          storedDismissed != null &&
          storedDismissed.isNotEmpty) {
        _dismissedArticleId = storedDismissed;
      }
      notifyListeners();
    } catch (_) {
      // Test ortamı veya ilk açılışta yerel kayıt okunamazsa sessizce devam et.
    }
  }

  /// Makale açıldığında veya okunurken ilerleme durumunu günceller.
  /// [persist] `false` ise yalnızca belleği günceller (akıcı kaydırma için).
  Future<void> recordProgress({
    required Article article,
    required double progress,
    double scrollOffset = 0,
    int? audioPositionMs,
    bool persist = true,
  }) async {
    final id = article.id.trim();
    if (id.isEmpty) return;

    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final safeOffset = scrollOffset < 0 ? 0.0 : scrollOffset;
    final existing = _itemsById[id];
    final safeAudioPos = (audioPositionMs != null && audioPositionMs >= 0)
        ? audioPositionMs
        : (existing?.audioPositionMs ?? 0);
    final updated = ArticleReadingProgress(
      articleId: id,
      articleTitle: article.title.trim(),
      articleLevel: article.level.trim().toUpperCase(),
      progress: clamped,
      scrollOffset: safeOffset,
      audioPositionMs: safeAudioPos,
      updatedAt: _nowProvider().toUtc(),
    );

    final shouldNotify = _lastArticleId != id ||
        _dismissedArticleId != null ||
        existing == null ||
        existing.progressPercent != updated.progressPercent ||
        existing.audioPositionMs != updated.audioPositionMs ||
        existing.articleTitle != updated.articleTitle;

    _itemsById[id] = updated;
    _lastArticleId = id;
    _dismissedArticleId = null;
    _pruneOverflow();

    if (shouldNotify) {
      notifyListeners();
    }

    if (persist) {
      await _persistState();
    }
  }

  void _pruneOverflow() {
    if (_itemsById.length <= _maxStoredArticles) return;
    final entries = _itemsById.entries.toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    final keepIds = entries
        .take(_maxStoredArticles)
        .map((entry) => entry.key)
        .toSet();
    if (_lastArticleId != null) {
      keepIds.add(_lastArticleId!);
    }
    _itemsById.removeWhere((key, _) => !keepIds.contains(key));
  }

  Future<void> _persistState() async {
    try {
      final payload = <String, Object?>{
        'lastArticleId': _lastArticleId,
        'dismissedArticleId': _dismissedArticleId,
        'items': <String, Object?>{
          for (final entry in _itemsById.entries)
            entry.key: entry.value.toJson(),
        },
      };
      await _resolveRepository().saveString(_storageKey, jsonEncode(payload));
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTesting() {
    _itemsById.clear();
    _lastArticleId = null;
    _dismissedArticleId = null;
    _hasLoaded = false;
    notifyListeners();
  }
}
