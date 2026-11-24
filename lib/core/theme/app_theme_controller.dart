import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../settings/settings_repository.dart';
import 'app_theme_preset.dart';

/// Seçilen uygulama temasını (`AppThemePreset`) SQLite `app_settings`
/// tablosunda saklar ve uygulama genelinde anlık olarak günceller.
class AppThemeController extends ChangeNotifier {
  AppThemeController({
    SettingsRepository? repository,
    AppThemePreset initialPreset = AppThemePreset.classic,
  })  : _repository = repository,
        _preset = initialPreset;

  static const String _settingsKey = 'app_theme_preset';
  static const String _animationPausedKey = 'app_theme_animation_paused';
  static const String _ecoAnimationKey = 'app_theme_eco_animation';

  /// Tüm ekranların ve Ayarlar'ın anında senkronize olması için paylaşılan örnek.
  static final AppThemeController shared = AppThemeController();

  final SettingsRepository? _repository;
  AppThemePreset _preset;
  bool _isAnimationPaused = false;
  bool _isEcoAnimation = false;
  bool _hasLoaded = false;

  AppThemePreset get preset => _preset;
  bool get isAnimationPaused => _isAnimationPaused;
  bool get isEcoAnimation => _isEcoAnimation;
  bool get hasLoaded => _hasLoaded;

  SettingsRepository _resolveRepository() {
    return _repository ?? SettingsRepository(AppDatabase.instance);
  }

  Future<void> load({bool force = false}) async {
    if (_hasLoaded && !force) return;
    _hasLoaded = true;
    try {
      final repo = _resolveRepository();
      final raw = await repo.getString(_settingsKey);
      final parsed = AppThemePreset.fromStorageKey(raw);
      final rawPaused = await repo.getString(_animationPausedKey);
      final parsedPaused = rawPaused == '1' || rawPaused == 'true';
      final rawEco = await repo.getString(_ecoAnimationKey);
      final parsedEco = rawEco == '1' || rawEco == 'true';
      var changed = false;
      if (parsed != _preset) {
        _preset = parsed;
        changed = true;
      }
      if (parsedPaused != _isAnimationPaused) {
        _isAnimationPaused = parsedPaused;
        changed = true;
      }
      if (parsedEco != _isEcoAnimation) {
        _isEcoAnimation = parsedEco;
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
    } catch (_) {
      // Test ortamı veya DB henüz hazır değilse varsayılan tema ile devam et.
    }
  }

  Future<void> setPreset(AppThemePreset next) async {
    if (_preset == next) return;
    _preset = next;
    _hasLoaded = true;
    notifyListeners();
    try {
      final repo = _resolveRepository();
      await repo.saveString(_settingsKey, next.storageKey);
      await repo.saveString('article_reader_tone', 'theme');
    } catch (_) {}
  }

  Future<void> setAnimationPaused(bool paused) async {
    if (_isAnimationPaused == paused) return;
    _isAnimationPaused = paused;
    _hasLoaded = true;
    notifyListeners();
    try {
      final repo = _resolveRepository();
      await repo.saveString(_animationPausedKey, paused ? '1' : '0');
    } catch (_) {}
  }

  Future<void> setEcoAnimation(bool eco) async {
    if (_isEcoAnimation == eco) return;
    _isEcoAnimation = eco;
    _hasLoaded = true;
    notifyListeners();
    try {
      final repo = _resolveRepository();
      await repo.saveString(_ecoAnimationKey, eco ? '1' : '0');
    } catch (_) {}
  }

  /// Özel tema yetkisi geri alındığında veya oturum kapatıldığında, aktif tema
  /// özel bir temaysa güvenli şekilde Varsayılan (Classic) temaya geri döner.
  void enforceSpecialThemeAccess({required bool hasSpecialThemes}) {
    if (!hasSpecialThemes && _preset.isSpecialTheme) {
      setPreset(AppThemePreset.classic);
    }
  }

  /// Kullanıcı oturum / Premium / Özel Tema yetkilerine göre aktif temayı doğrular:
  /// - Misafir / giriş yapmamış: Yalnızca Klasik (varsayılan) tema.
  /// - Standart üye: Yalnızca hareketsiz (statik) temalar.
  /// - Premium üye / Geliştirici: Hareketsiz + Hareketli temalar.
  /// - Özel tema yetkisi olanlar / Geliştirici: Özel temalar da dahil.
  void enforceThemeAccess({
    required bool isAuthenticated,
    required bool isPremium,
    required bool hasSpecialThemes,
  }) {
    if (_preset == AppThemePreset.classic) return;
    if (!isAuthenticated) {
      setPreset(AppThemePreset.classic);
      return;
    }
    if (_preset.isSpecialTheme && !hasSpecialThemes) {
      setPreset(AppThemePreset.classic);
      return;
    }
    if (_preset.isAnimatedTheme && !_preset.isSpecialTheme && !isPremium) {
      setPreset(AppThemePreset.classic);
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _preset = AppThemePreset.classic;
    _isAnimationPaused = false;
    _isEcoAnimation = false;
    _hasLoaded = false;
    notifyListeners();
  }
}
