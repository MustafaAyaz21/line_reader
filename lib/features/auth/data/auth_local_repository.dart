import '../../../core/settings/settings_repository.dart';

/// Yerel misafir oturumu, günlük çeviri kotası ve önbellekli yetki durumunu
/// saklayan soyut depo.
abstract class AuthLocalStore {
  Future<bool> isGuestModeEnabled();

  Future<void> setGuestModeEnabled(bool enabled);

  Future<({String dateKey, int usedCount})> loadGuestQuota();

  Future<void> saveGuestQuota({
    required String dateKey,
    required int usedCount,
  });

  Future<({
    bool isUnlimited,
    String? codeUsed,
    String? role,
    bool hasSpecialThemes,
  })> loadCachedEntitlement();

  Future<void> saveCachedEntitlement({
    required bool isUnlimited,
    String? codeUsed,
    String? role,
    bool hasSpecialThemes = false,
  });
}

/// Misafir oturum tercihini, günlük çeviri sayacını ve son doğrulanmış yetki
/// bilgisini SQLite `app_settings` tablosunda kalıcı olarak saklar.
class AuthLocalRepository implements AuthLocalStore {
  AuthLocalRepository(this._settingsRepository);

  static const String _guestModeKey = 'auth_guest_mode_enabled';
  static const String _guestQuotaDateKey = 'auth_guest_quota_date';
  static const String _guestQuotaUsedKey = 'auth_guest_quota_used';
  static const String _entitlementUnlimitedKey = 'auth_entitlement_unlimited';
  static const String _entitlementCodeKey = 'auth_entitlement_code';
  static const String _entitlementRoleKey = 'auth_entitlement_role';
  static const String _entitlementSpecialThemesKey =
      'auth_entitlement_special_themes';

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

  @override
  Future<({
    bool isUnlimited,
    String? codeUsed,
    String? role,
    bool hasSpecialThemes,
  })> loadCachedEntitlement() async {
    final rawUnlimited =
        await _settingsRepository.getString(_entitlementUnlimitedKey);
    final codeUsed = await _settingsRepository.getString(_entitlementCodeKey);
    final role = await _settingsRepository.getString(_entitlementRoleKey);
    final rawSpecial =
        await _settingsRepository.getString(_entitlementSpecialThemesKey);
    return (
      isUnlimited: rawUnlimited == 'true',
      codeUsed: codeUsed,
      role: role,
      hasSpecialThemes: rawSpecial == 'true',
    );
  }

  @override
  Future<void> saveCachedEntitlement({
    required bool isUnlimited,
    String? codeUsed,
    String? role,
    bool hasSpecialThemes = false,
  }) async {
    await _settingsRepository.saveString(
      _entitlementUnlimitedKey,
      isUnlimited ? 'true' : 'false',
    );
    await _settingsRepository.saveString(
      _entitlementSpecialThemesKey,
      hasSpecialThemes ? 'true' : 'false',
    );
    if (isUnlimited && codeUsed != null && codeUsed.trim().isNotEmpty) {
      await _settingsRepository.saveString(
        _entitlementCodeKey,
        codeUsed.trim(),
      );
    } else {
      await _settingsRepository.deleteKey(_entitlementCodeKey);
    }
    if (isUnlimited && role != null && role.trim().isNotEmpty) {
      await _settingsRepository.saveString(
        _entitlementRoleKey,
        role.trim().toLowerCase(),
      );
    } else {
      await _settingsRepository.deleteKey(_entitlementRoleKey);
    }
  }
}
