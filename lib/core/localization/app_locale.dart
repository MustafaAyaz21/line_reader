import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../settings/settings_repository.dart';

/// Uygulama arayüzü için desteklenen diller (yalnızca UI metinlerini etkiler;
/// kelime çevirileri her zaman Türkçe, makaleler orijinal dilinde kalır).
enum AppLanguage {
  tr(code: 'tr', nativeName: 'Türkçe', shortLabel: 'TR'),
  en(code: 'en', nativeName: 'English', shortLabel: 'EN');

  const AppLanguage({
    required this.code,
    required this.nativeName,
    required this.shortLabel,
  });

  final String code;
  final String nativeName;
  final String shortLabel;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == 'en') return AppLanguage.en;
    return AppLanguage.tr;
  }
}

/// Arayüz dilini kalıcı olarak saklayan soyut depo.
abstract class AppLanguageStore {
  Future<AppLanguage> loadLanguage();

  Future<void> saveLanguage(AppLanguage language);
}

class SqliteAppLanguageStore implements AppLanguageStore {
  SqliteAppLanguageStore(this._settingsRepository);

  static const String _languageSettingKey = 'app_interface_language';

  final SettingsRepository _settingsRepository;

  @override
  Future<AppLanguage> loadLanguage() async {
    final raw = await _settingsRepository.getString(_languageSettingKey);
    return AppLanguage.fromCode(raw);
  }

  @override
  Future<void> saveLanguage(AppLanguage language) async {
    await _settingsRepository.saveString(_languageSettingKey, language.code);
  }
}

/// Uygulama genelinde arayüz dilini reaktif olarak yöneten denetleyici.
class AppLocaleController extends ChangeNotifier {
  AppLocaleController({
    AppLanguageStore? store,
    AppLanguage initialLanguage = AppLanguage.tr,
  })  : _store = store ??
            SqliteAppLanguageStore(SettingsRepository(AppDatabase.instance)),
        _language = initialLanguage;

  final AppLanguageStore _store;
  AppLanguage _language;
  bool _isLoaded = false;
  bool _isDisposed = false;

  AppLanguage get language => _language;
  bool get isEnglish => _language == AppLanguage.en;
  bool get isTurkish => _language == AppLanguage.tr;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    try {
      final saved = await _store.loadLanguage();
      _language = saved;
    } catch (error) {
      debugPrint('[AppLocaleController] Dil yukleme hatasi: $error');
    } finally {
      _isLoaded = true;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> setLanguage(AppLanguage next) async {
    if (_language == next && _isLoaded) return;
    _language = next;
    _isLoaded = true;
    if (!_isDisposed) {
      notifyListeners();
    }
    try {
      await _store.saveLanguage(next);
    } catch (error) {
      debugPrint('[AppLocaleController] Dil kaydetme hatasi: $error');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

/// Uygulama ağacının her yerinden aktif arayüz diline reaktif erişim sağlar.
class AppLocaleScope extends InheritedNotifier<AppLocaleController> {
  const AppLocaleScope({
    super.key,
    required AppLocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLocaleController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppLocaleScope>()
        ?.notifier;
  }

  static AppLanguage languageOf(BuildContext context) {
    return maybeOf(context)?.language ?? AppLanguage.tr;
  }
}
