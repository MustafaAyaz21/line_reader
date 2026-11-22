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

  /// Tüm ekranların ve Ayarlar'ın anında senkronize olması için paylaşılan örnek.
  static final AppThemeController shared = AppThemeController();

  final SettingsRepository? _repository;
  AppThemePreset _preset;
  bool _hasLoaded = false;

  AppThemePreset get preset => _preset;
  bool get hasLoaded => _hasLoaded;

  SettingsRepository _resolveRepository() {
    return _repository ?? SettingsRepository(AppDatabase.instance);
  }

  Future<void> load({bool force = false}) async {
    if (_hasLoaded && !force) return;
    _hasLoaded = true;
    try {
      final raw = await _resolveRepository().getString(_settingsKey);
      final parsed = AppThemePreset.fromStorageKey(raw);
      if (parsed != _preset) {
        _preset = parsed;
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
      if (next.isGradientTheme) {
        // Yeni gradyan tema seçildiğinde makale okuma alanı da otomatik olarak
        // temaya uyumlu okunaklı yüzey moduna geçer (kullanıcı Aa'dan yine
        // Beyaz/Kağıt/Koyu seçebilir).
        await repo.saveString('article_reader_tone', 'theme');
      }
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTesting() {
    _preset = AppThemePreset.classic;
    _hasLoaded = false;
    notifyListeners();
  }
}
