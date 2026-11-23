import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'settings_repository.dart';

/// Kullanıcının tercih ettiği IPA telaffuz aksanı (Amerikan veya İngiliz).
enum IpaAccent {
  us('us', 'US', 'Amerikan (US)', 'American (US)', 'en-US'),
  uk('uk', 'UK', 'İngiliz (UK)', 'British (UK)', 'en-GB');

  const IpaAccent(
    this.storageValue,
    this.shortLabel,
    this.turkishLabel,
    this.englishLabel,
    this.ttsLocale,
  );

  final String storageValue;
  final String shortLabel;
  final String turkishLabel;
  final String englishLabel;
  final String ttsLocale;

  static IpaAccent fromStorage(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == 'uk' || normalized == 'gb' || normalized == 'en-gb') {
      return IpaAccent.uk;
    }
    return IpaAccent.us;
  }
}

/// Uygulama genelinde Amerikan (US) / İngiliz (UK) IPA telaffuz aksan tercihini
/// yöneten ve SQLite `app_settings` tablosunda saklayan denetleyici.
class IpaAccentController extends ChangeNotifier {
  IpaAccentController({SettingsRepository? repository})
      : _repository = repository;

  static const String _settingsKey = 'ipa_accent';
  static const String _enabledSettingsKey = 'ipa_enabled';

  /// Uygulama genelinde tüm kelime ekranlarının ve Ayarlar'ın anında senkronize
  /// olması için paylaşılan tek örnek.
  static final IpaAccentController shared = IpaAccentController();

  final SettingsRepository? _repository;

  IpaAccent _accent = IpaAccent.us;
  bool _isEnabled = true;
  bool _hasLoaded = false;

  IpaAccent get accent => _accent;
  bool get isEnabled => _isEnabled;

  SettingsRepository _resolveRepository() {
    return _repository ?? SettingsRepository(AppDatabase.instance);
  }

  Future<void> load({bool force = false}) async {
    if (_hasLoaded && !force) return;
    _hasLoaded = true;
    try {
      final repo = _resolveRepository();
      final rawAccent = await repo.getString(_settingsKey);
      final rawEnabled = await repo.getString(_enabledSettingsKey);
      final parsedAccent = IpaAccent.fromStorage(rawAccent);
      final parsedEnabled = _parseEnabled(rawEnabled);
      var changed = false;
      if (parsedAccent != _accent) {
        _accent = parsedAccent;
        changed = true;
      }
      if (parsedEnabled != _isEnabled) {
        _isEnabled = parsedEnabled;
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
    } catch (_) {
      // Test veya DB henüz hazır değilse varsayılan değerlerle devam et.
    }
  }

  static bool _parseEnabled(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == 'false' || normalized == '0' || normalized == 'off') {
      return false;
    }
    return true;
  }

  Future<void> setEnabled(bool next) async {
    if (_isEnabled == next) return;
    _isEnabled = next;
    notifyListeners();
    try {
      await _resolveRepository().saveString(
        _enabledSettingsKey,
        next ? 'true' : 'false',
      );
    } catch (_) {}
  }

  Future<void> setAccent(IpaAccent next) async {
    if (_accent == next) return;
    _accent = next;
    notifyListeners();
    try {
      await _resolveRepository().saveString(_settingsKey, next.storageValue);
    } catch (_) {}
  }

  Future<void> toggle() {
    return setAccent(
      _accent == IpaAccent.us ? IpaAccent.uk : IpaAccent.us,
    );
  }
}
