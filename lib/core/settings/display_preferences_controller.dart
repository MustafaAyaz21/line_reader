import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'settings_repository.dart';

/// IPA okunuşunun nasıl gösterileceğini belirler.
enum IpaDisplayMode {
  both('both', 'İkisi (US + UK)', 'Both (US + UK)'),
  usOnly('us', 'Sadece US', 'US Only'),
  ukOnly('uk', 'Sadece UK', 'UK Only'),
  off('off', 'Kapalı', 'Off');

  const IpaDisplayMode(this.storageValue, this.trLabel, this.enLabel);

  final String storageValue;
  final String trLabel;
  final String enLabel;

  bool get showUs => this == IpaDisplayMode.both || this == IpaDisplayMode.usOnly;
  bool get showUk => this == IpaDisplayMode.both || this == IpaDisplayMode.ukOnly;
  bool get isEnabled => this != IpaDisplayMode.off;

  String label({required bool isEnglish}) => isEnglish ? enLabel : trLabel;

  static IpaDisplayMode fromStorage(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final mode in IpaDisplayMode.values) {
      if (mode.storageValue == normalized) return mode;
    }
    return IpaDisplayMode.both;
  }
}

/// Uygulama içi (Makale, Tarayıcı, Kelimelerim) ve dışarıdan açılan
/// "Line'da Bak" mini kartının görünüm tercihlerini SQLite `app_settings`
/// tablosunda saklayan paylaşılan denetleyici.
class DisplayPreferencesController extends ChangeNotifier {
  DisplayPreferencesController({SettingsRepository? repository})
      : _repository = repository;

  static final DisplayPreferencesController shared =
      DisplayPreferencesController();

  static const String _kAppIpaMode = 'display_app_ipa_mode';
  static const String _kAppShowSynonyms = 'display_app_show_synonyms';
  static const String _kAppShowAntonyms = 'display_app_show_antonyms';

  static const String _kOverlayIpaMode = 'display_overlay_ipa_mode';
  static const String _kOverlayShowSynonyms = 'display_overlay_show_synonyms';
  static const String _kOverlayShowAntonyms = 'display_overlay_show_antonyms';
  static const String _kOverlayShowTts = 'display_overlay_show_tts';
  static const String _kOverlayShowSaveBar = 'display_overlay_show_save_bar';

  final SettingsRepository? _repository;
  bool _hasLoaded = false;

  IpaDisplayMode _appIpaMode = IpaDisplayMode.both;
  bool _appShowSynonyms = true;
  bool _appShowAntonyms = true;

  IpaDisplayMode _overlayIpaMode = IpaDisplayMode.both;
  bool _overlayShowSynonyms = true;
  bool _overlayShowAntonyms = true;
  bool _overlayShowTts = true;
  bool _overlayShowSaveBar = true;

  IpaDisplayMode get appIpaMode => _appIpaMode;
  bool get appShowSynonyms => _appShowSynonyms;
  bool get appShowAntonyms => _appShowAntonyms;

  IpaDisplayMode get overlayIpaMode => _overlayIpaMode;
  bool get overlayShowSynonyms => _overlayShowSynonyms;
  bool get overlayShowAntonyms => _overlayShowAntonyms;
  bool get overlayShowTts => _overlayShowTts;
  bool get overlayShowSaveBar => _overlayShowSaveBar;

  SettingsRepository _resolveRepository() {
    return _repository ?? SettingsRepository(AppDatabase.instance);
  }

  static bool _parseBool(String? raw, {bool fallback = true}) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == 'false' || normalized == '0' || normalized == 'off') {
      return false;
    }
    if (normalized == 'true' || normalized == '1' || normalized == 'on') {
      return true;
    }
    return fallback;
  }

  Future<void> load({bool force = false}) async {
    if (_hasLoaded && !force) return;
    _hasLoaded = true;
    try {
      final repo = _resolveRepository();
      final results = await Future.wait<String?>(<Future<String?>>[
        repo.getString(_kAppIpaMode),
        repo.getString(_kAppShowSynonyms),
        repo.getString(_kAppShowAntonyms),
        repo.getString(_kOverlayIpaMode),
        repo.getString(_kOverlayShowSynonyms),
        repo.getString(_kOverlayShowAntonyms),
        repo.getString(_kOverlayShowTts),
        repo.getString(_kOverlayShowSaveBar),
      ]);

      final nextAppIpa = IpaDisplayMode.fromStorage(results[0]);
      final nextAppSyn = _parseBool(results[1]);
      final nextAppAnt = _parseBool(results[2]);
      final nextOvIpa = IpaDisplayMode.fromStorage(results[3]);
      final nextOvSyn = _parseBool(results[4]);
      final nextOvAnt = _parseBool(results[5]);
      final nextOvTts = _parseBool(results[6]);
      final nextOvSave = _parseBool(results[7]);

      final changed = nextAppIpa != _appIpaMode ||
          nextAppSyn != _appShowSynonyms ||
          nextAppAnt != _appShowAntonyms ||
          nextOvIpa != _overlayIpaMode ||
          nextOvSyn != _overlayShowSynonyms ||
          nextOvAnt != _overlayShowAntonyms ||
          nextOvTts != _overlayShowTts ||
          nextOvSave != _overlayShowSaveBar;

      _appIpaMode = nextAppIpa;
      _appShowSynonyms = nextAppSyn;
      _appShowAntonyms = nextAppAnt;
      _overlayIpaMode = nextOvIpa;
      _overlayShowSynonyms = nextOvSyn;
      _overlayShowAntonyms = nextOvAnt;
      _overlayShowTts = nextOvTts;
      _overlayShowSaveBar = nextOvSave;

      if (changed) notifyListeners();
    } catch (_) {
      // DB henüz hazır değilse varsayılanlarla devam et.
    }
  }

  Future<void> _save(String key, String value) async {
    try {
      await _resolveRepository().saveString(key, value);
    } catch (_) {}
  }

  Future<void> setAppIpaMode(IpaDisplayMode next) async {
    if (_appIpaMode == next) return;
    _appIpaMode = next;
    notifyListeners();
    await _save(_kAppIpaMode, next.storageValue);
  }

  Future<void> setAppShowSynonyms(bool next) async {
    if (_appShowSynonyms == next) return;
    _appShowSynonyms = next;
    notifyListeners();
    await _save(_kAppShowSynonyms, next ? 'true' : 'false');
  }

  Future<void> setAppShowAntonyms(bool next) async {
    if (_appShowAntonyms == next) return;
    _appShowAntonyms = next;
    notifyListeners();
    await _save(_kAppShowAntonyms, next ? 'true' : 'false');
  }

  Future<void> setOverlayIpaMode(IpaDisplayMode next) async {
    if (_overlayIpaMode == next) return;
    _overlayIpaMode = next;
    notifyListeners();
    await _save(_kOverlayIpaMode, next.storageValue);
  }

  Future<void> setOverlayShowSynonyms(bool next) async {
    if (_overlayShowSynonyms == next) return;
    _overlayShowSynonyms = next;
    notifyListeners();
    await _save(_kOverlayShowSynonyms, next ? 'true' : 'false');
  }

  Future<void> setOverlayShowAntonyms(bool next) async {
    if (_overlayShowAntonyms == next) return;
    _overlayShowAntonyms = next;
    notifyListeners();
    await _save(_kOverlayShowAntonyms, next ? 'true' : 'false');
  }

  Future<void> setOverlayShowTts(bool next) async {
    if (_overlayShowTts == next) return;
    _overlayShowTts = next;
    notifyListeners();
    await _save(_kOverlayShowTts, next ? 'true' : 'false');
  }

  Future<void> setOverlayShowSaveBar(bool next) async {
    if (_overlayShowSaveBar == next) return;
    _overlayShowSaveBar = next;
    notifyListeners();
    await _save(_kOverlayShowSaveBar, next ? 'true' : 'false');
  }

  @visibleForTesting
  void resetForTesting() {
    _hasLoaded = false;
    _appIpaMode = IpaDisplayMode.both;
    _appShowSynonyms = true;
    _appShowAntonyms = true;
    _overlayIpaMode = IpaDisplayMode.both;
    _overlayShowSynonyms = true;
    _overlayShowAntonyms = true;
    _overlayShowTts = true;
    _overlayShowSaveBar = true;
    notifyListeners();
  }
}
