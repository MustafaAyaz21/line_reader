import '../../../core/settings/settings_repository.dart';

/// Yerel misafir oturumu ve günlük çeviri kotasını saklayan soyut depo.
abstract class AuthLocalStore {
  Future<bool> isGuestModeEnabled();

  Future<void> setGuestModeEnabled(bool enabled);

  Future<({String dateKey, int usedCount})> loadGuestQuota();

  Future<void> saveGuestQuota({
    required String dateKey,
    required int usedCount,
  });
}

/// Misafir oturum tercihini ve günlük 40 kelime çeviri sayacını SQLite
/// `app_settings` tablosunda kalıcı olarak saklar.
class AuthLocalRepository implements AuthLocalStore {
  AuthLocalRepository(this._settingsRepository);

  static const String _guestModeKey = 'auth_guest_mode_enabled';
  static const String _guestQuotaDateKey = 'auth_guest_quota_date';
  static const String _guestQuotaUsedKey = 'auth_guest_quota_used';

  final SettingsRepository _settingsRepository;

  @override
  Future<bool> isGuestModeEnabled() async {
    final value = await _settingsRepository.getString(_guestModeKey);
    return value == 'true';
  }

  @override
  Future<void> setGuestModeEnabled(bool enabled) async {
    await _settingsRepository.saveString(
      _guestModeKey,
      enabled ? 'true' : 'false',
    );
  }

  @override
  Future<({String dateKey, int usedCount})> loadGuestQuota() async {
    final dateKey =
        (await _settingsRepository.getString(_guestQuotaDateKey)) ?? '';
    final rawCount = await _settingsRepository.getString(_guestQuotaUsedKey);
    final parsed = int.tryParse(rawCount ?? '') ?? 0;
    return (dateKey: dateKey, usedCount: parsed < 0 ? 0 : parsed);
  }

  @override
  Future<void> saveGuestQuota({
    required String dateKey,
    required int usedCount,
  }) async {
    await _settingsRepository.saveString(_guestQuotaDateKey, dateKey);
    await _settingsRepository.saveString(
      _guestQuotaUsedKey,
      (usedCount < 0 ? 0 : usedCount).toString(),
    );
  }
}
