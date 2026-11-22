import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/settings_repository.dart';
import '../data/auth_local_repository.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';
import '../services/entitlement_service.dart';

/// Kullanıcı oturumunu (Google / E-posta / Misafir), sunucu doğrulamalı
/// sınırsız yetkiyi (kod veya admin yetkisi), 3 katmanlı günlük çeviri kotasını
/// (Misafir: 40 • Kayıtlı normal: 80 • Yetkili: Sınırsız + Tarayıcı AI) ve
/// özel duyuru/reklam sıklığını (Misafir: 5 sorguda 1 • Standart: 8 sorguda 1)
/// tek merkezden yöneten denetleyici.
class AuthController extends ChangeNotifier {
  AuthController({
    AuthBackend? backend,
    AuthLocalStore? localStore,
    EntitlementClient? entitlementClient,
    DateTime Function()? nowProvider,
  })  : _backend = backend ?? FirebaseAuthBackend(),
        _localStore = localStore ??
            AuthLocalRepository(SettingsRepository(AppDatabase.instance)),
        _entitlementClient =
            entitlementClient ?? CloudflareEntitlementService(),
        _ownsEntitlementClient = entitlementClient == null,
        _nowProvider = nowProvider ?? DateTime.now;

  static const int guestDailyTranslationLimit = 40;
  static const int standardUserDailyTranslationLimit = 80;
  static const int guestPromoFrequency = 5;
  static const int standardUserPromoFrequency = 8;

  final AuthBackend _backend;
  final AuthLocalStore _localStore;
  final EntitlementClient _entitlementClient;
  final bool _ownsEntitlementClient;
  final DateTime Function() _nowProvider;

  StreamSubscription<AppAuthUser?>? _authSub;
  AuthSessionStatus _status = AuthSessionStatus.loading;
  AppAuthUser? _user;
  bool _isBusy = false;
  bool _isSyncingEntitlement = false;
  bool _isUnlimited = false;
  String? _entitlementCodeUsed;
  String _quotaDateKey = '';
  int _dailyUsedToday = 0;
  int _sessionLookupCount = 0;
  bool _isDisposed = false;

  AuthSessionStatus get status => _status;
  AppAuthUser? get user => _user;
  bool get isBusy => _isBusy;
  bool get isSyncingEntitlement => _isSyncingEntitlement;
  bool get isFirebaseConfigured => _backend.isConfigured;

  bool get isLoading => _status == AuthSessionStatus.loading;
  bool get isAuthenticated => _status == AuthSessionStatus.authenticated;
  bool get isGuest => _status == AuthSessionStatus.guest;
  bool get needsOnboarding => _status == AuthSessionStatus.unauthenticated;

  /// Yalnızca kayıtlı ve sunucu (kod veya admin) tarafından yetkilendirilmiş
  /// hesaplarda `true` döner: sınırsız çeviri, reklamsız kullanım ve Tarayıcı AI.
  bool get isUnlimited => isAuthenticated && _isUnlimited;
  String? get entitlementCodeUsed => isUnlimited ? _entitlementCodeUsed : null;

  /// Aktif oturum için günlük çeviri limiti (Misafir: 40, Kayıtlı standart: 80).
  int get dailyTranslationLimit =>
      isAuthenticated ? standardUserDailyTranslationLimit : guestDailyTranslationLimit;

  int get dailyUsedToday {
    _resetQuotaInMemoryIfNewDay();
    return _dailyUsedToday;
  }

  int get dailyRemainingToday {
    if (isUnlimited) return dailyTranslationLimit;
    return (dailyTranslationLimit - dailyUsedToday)
        .clamp(0, dailyTranslationLimit);
  }

  bool get hasReachedDailyLimit => !isUnlimited && dailyRemainingToday <= 0;

  // Geriye dönük uyumluluk getter'ları
  int get guestUsedToday => dailyUsedToday;
  int get guestRemainingToday => dailyRemainingToday;
  bool get hasReachedGuestLimit => isGuest && hasReachedDailyLimit;

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  String _todayKey() {
    final now = _nowProvider();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _resetQuotaInMemoryIfNewDay() {
    final today = _todayKey();
    if (_quotaDateKey != today) {
      _quotaDateKey = today;
      _dailyUsedToday = 0;
    }
  }

  /// Uygulama açılışında oturum, günlük kota ve önbellekli yetkiyi yükler;
  /// kullanıcı giriş yapmışsa sunucudan güncel yetki durumunu sessizce doğrular.
  Future<void> initialize() async {
    try {
      await _backend.initialize();
      final quota = await _localStore.loadGuestQuota();
      final today = _todayKey();
      if (quota.dateKey == today) {
        _quotaDateKey = today;
        _dailyUsedToday = quota.usedCount;
      } else {
        _quotaDateKey = today;
        _dailyUsedToday = 0;
      }

      final cachedEnt = await _localStore.loadCachedEntitlement();
      final current = _backend.currentUser;
      if (current != null) {
        _user = current;
        _status = AuthSessionStatus.authenticated;
        _isUnlimited = cachedEnt.isUnlimited;
        _entitlementCodeUsed = cachedEnt.codeUsed;
      } else {
        final guestEnabled = await _localStore.isGuestModeEnabled();
        _user = null;
        _isUnlimited = false;
        _entitlementCodeUsed = null;
        _status = guestEnabled
            ? AuthSessionStatus.guest
            : AuthSessionStatus.unauthenticated;
      }

      await _authSub?.cancel();
      _authSub = _backend.authStateChanges.listen((nextUser) {
        if (nextUser != null) {
          _user = nextUser;
          _status = AuthSessionStatus.authenticated;
          _safeNotify();
          refreshEntitlement();
        } else if (_status == AuthSessionStatus.authenticated) {
          _user = null;
          _isUnlimited = false;
          _entitlementCodeUsed = null;
          _status = AuthSessionStatus.unauthenticated;
          _safeNotify();
        }
      });

      if (isAuthenticated) {
        unawaited(refreshEntitlement());
      }
    } catch (error) {
      debugPrint('[AuthController] Ilklendirme hatasi: $error');
      _status = AuthSessionStatus.unauthenticated;
    } finally {
      _safeNotify();
    }
  }

  /// Sunucudan (`/me`) kullanıcının güncel yetkisini çeker ve yerel önbelleği günceller.
  Future<void> refreshEntitlement() async {
    if (!isAuthenticated || _isSyncingEntitlement) return;
    _isSyncingEntitlement = true;
    _safeNotify();

    try {
      final token = await getIdToken();
      if (token == null || token.trim().isEmpty) return;

      final remote = await _entitlementClient.fetchEntitlement(token);
      if (remote == null) return;

      _isUnlimited = remote.isUnlimited;
      _entitlementCodeUsed = remote.codeUsed;
      await _localStore.saveCachedEntitlement(
        isUnlimited: _isUnlimited,
        codeUsed: _entitlementCodeUsed,
      );
    } catch (error) {
      debugPrint('[AuthController] Yetki yenileme hatasi: $error');
    } finally {
      _isSyncingEntitlement = false;
      _safeNotify();
    }
  }

  /// Kayıtlı kullanıcı için aktivasyon kodunu (`AYAZ2026` vb.) sunucuda doğrular.
  Future<RedeemCodeResult> redeemAccessCode(String rawCode) async {
    if (!isAuthenticated) {
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'Kod kullanmak için önce Google veya E-posta ile giriş yapın.',
      );
    }

    if (_isBusy) {
      return const RedeemCodeResult(
        isSuccess: false,
        message: 'Devam eden işlem var, lütfen bekleyin.',
      );
    }

    _isBusy = true;
    _safeNotify();

    try {
      final token = await getIdToken();
      if (token == null || token.trim().isEmpty) {
        return const RedeemCodeResult(
          isSuccess: false,
          message: 'Oturum doğrulanamadı. Lütfen tekrar giriş yapın.',
        );
      }

      final result = await _entitlementClient.redeemCode(
        idToken: token,
        code: rawCode,
      );

      if (result.isSuccess) {
        _isUnlimited = true;
        _entitlementCodeUsed = result.code ?? _entitlementCodeUsed;
        await _localStore.saveCachedEntitlement(
          isUnlimited: true,
          codeUsed: _entitlementCodeUsed,
        );
      }
      return result;
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  /// Her kelime çevirisi öncesinde aktif kullanıcı katmanının kotasını kontrol
  /// edip 1 azaltır:
  /// - Yetkili (`isUnlimited`): Her zaman `true` (sınırsız).
  /// - Kayıtlı standart: Günde en fazla 80 kelime.
  /// - Misafir: Günde en fazla 40 kelime.
  Future<bool> consumeTranslationQuota() async {
    if (isUnlimited) return true;

    final today = _todayKey();
    if (_quotaDateKey != today) {
      _quotaDateKey = today;
      _dailyUsedToday = 0;
    }

    final limit = dailyTranslationLimit;
    if (_dailyUsedToday >= limit) {
      _safeNotify();
      return false;
    }

    _dailyUsedToday += 1;
    _safeNotify();

    try {
      await _localStore.saveGuestQuota(
        dateKey: today,
        usedCount: _dailyUsedToday,
      );
    } catch (error) {
      debugPrint('[AuthController] Kota kaydetme hatasi: $error');
    }

    return true;
  }

  Future<bool> consumeTranslationQuotaIfGuest() => consumeTranslationQuota();

  /// Kelime sorgulama sayacını artırır ve geliştirme duyurusu/reklamının
  /// gösterilip gösterilmeyeceğini döner:
  /// - Yetkili (`isUnlimited`): Hiçbir zaman gösterilmez (`false`).
  /// - Misafir: Her 5 kelime sorgulamasında 1 (`5, 10, 15...`).
  /// - Kayıtlı standart: Her 8 kelime sorgulamasında 1 (`8, 16, 24...`).
  bool recordWordLookupAndShouldShowPromo() {
    if (isUnlimited) return false;
    _sessionLookupCount += 1;
    final frequency =
        isAuthenticated ? standardUserPromoFrequency : guestPromoFrequency;
    return _sessionLookupCount % frequency == 0;
  }

  Future<void> continueAsGuest() async {
    _user = null;
    _isUnlimited = false;
    _entitlementCodeUsed = null;
    _sessionLookupCount = 0;
    _status = AuthSessionStatus.guest;
    _resetQuotaInMemoryIfNewDay();
    _safeNotify();
    try {
      await _localStore.setGuestModeEnabled(true);
      await _localStore.saveCachedEntitlement(isUnlimited: false);
    } catch (error) {
      debugPrint('[AuthController] Misafir modu kaydetme hatasi: $error');
    }
  }

  Future<AuthActionResult> signInWithGoogle() async {
    if (_isBusy) return const AuthActionResult.cancelled();
    _isBusy = true;
    _safeNotify();

    try {
      final result = await _backend.signInWithGoogle();
      if (result.isSuccess && result.user != null) {
        _user = result.user;
        _status = AuthSessionStatus.authenticated;
        _sessionLookupCount = 0;
        await _localStore.setGuestModeEnabled(false);
        await _syncEntitlementAfterSignIn();
      }
      return result;
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  Future<AuthActionResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (_isBusy) return const AuthActionResult.cancelled();
    _isBusy = true;
    _safeNotify();

    try {
      final result = await _backend.signInWithEmail(
        email: email,
        password: password,
      );
      if (result.isSuccess && result.user != null) {
        _user = result.user;
        _status = AuthSessionStatus.authenticated;
        _sessionLookupCount = 0;
        await _localStore.setGuestModeEnabled(false);
        await _syncEntitlementAfterSignIn();
      }
      return result;
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  Future<AuthActionResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (_isBusy) return const AuthActionResult.cancelled();
    _isBusy = true;
    _safeNotify();

    try {
      final result = await _backend.signUpWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (result.isSuccess && result.user != null) {
        _user = result.user;
        _status = AuthSessionStatus.authenticated;
        _sessionLookupCount = 0;
        await _localStore.setGuestModeEnabled(false);
        await _syncEntitlementAfterSignIn();
      }
      return result;
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  Future<void> _syncEntitlementAfterSignIn() async {
    try {
      final token = await _backend.getIdToken();
      if (token == null || token.trim().isEmpty) return;
      final remote = await _entitlementClient.fetchEntitlement(token);
      if (remote != null) {
        _isUnlimited = remote.isUnlimited;
        _entitlementCodeUsed = remote.codeUsed;
        await _localStore.saveCachedEntitlement(
          isUnlimited: _isUnlimited,
          codeUsed: _entitlementCodeUsed,
        );
      }
    } catch (_) {}
  }

  Future<AuthActionResult> sendPasswordResetEmail(String email) async {
    if (_isBusy) return const AuthActionResult.cancelled();
    _isBusy = true;
    _safeNotify();

    try {
      return await _backend.sendPasswordResetEmail(email);
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  /// Yalnızca kayıtlı kullanıcılar için tarayıcı AI Worker doğrulama token'ı döner;
  /// misafir kullanıcılar için her zaman `null` döner.
  Future<String?> getIdToken() async {
    if (!isAuthenticated) return null;
    return _backend.getIdToken();
  }

  Future<void> signOut() async {
    if (_isBusy) return;
    _isBusy = true;
    _safeNotify();

    try {
      await _backend.signOut();
      await _localStore.setGuestModeEnabled(true);
      await _localStore.saveCachedEntitlement(isUnlimited: false);
      _user = null;
      _isUnlimited = false;
      _entitlementCodeUsed = null;
      _sessionLookupCount = 0;
      _status = AuthSessionStatus.guest;
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authSub?.cancel();
    if (_ownsEntitlementClient) {
      _entitlementClient.dispose();
    }
    super.dispose();
  }
}
