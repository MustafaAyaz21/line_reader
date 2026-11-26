import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme_controller.dart';
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
  bool _hasSpecialThemes = false;
  bool _d1EmailVerified = false;
  bool _isOtpVerificationMode = true;
  int _otpResendCooldownSeconds = 0;
  String? _entitlementCodeUsed;
  String? _entitlementRole;
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
  String? get entitlementRole => isUnlimited ? _entitlementRole : null;

  /// Panelden "Yetkili" olarak işaretlenen hesaplarda `true` döner;
  /// Ayarlar'da "Premium Üye" yerine "Yetkili" olarak gösterilir.
  bool get isAuthorizedStaff =>
      isUnlimited && _entitlementRole?.trim().toLowerCase() == 'admin';

  /// Kullanıcının gizli "Özel Temalar" bölümüne erişim hakkı.
  /// Geliştirici (admin) hesaplar her zaman tüm özel temaları görür.
  /// Misafir veya çıkış yapmış oturumlarda her zaman `false` döner.
  bool get hasSpecialThemes =>
      isAuthenticated && (_hasSpecialThemes || isAuthorizedStaff);

  void _enforceSpecialThemeFallback() {
    AppThemeController.shared.enforceThemeAccess(
      isAuthenticated: isAuthenticated,
      isPremium: isUnlimited,
      hasSpecialThemes: hasSpecialThemes,
    );
  }

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
      final persistedVerifiedUid = await _loadPersistedVerifiedUid();
      final current = _backend.currentUser;
      if (current != null) {
        _user = await _enrichUser(current);
        if (persistedVerifiedUid != null &&
            persistedVerifiedUid == current.uid) {
          _d1EmailVerified = true;
        }
        if (!current.emailVerified && !_d1EmailVerified) {
          // Yerel önbellek boşsa (ör. yeni cihaz / sayfa yenileme) OTP ekranına
          // atmadan önce Cloudflare D1 (/me) üzerinden doğrulama durumunu sor.
          await _checkRemoteD1EmailVerified();
        }
        if (current.emailVerified || _d1EmailVerified) {
          _status = AuthSessionStatus.authenticated;
          _isUnlimited = cachedEnt.isUnlimited;
          _hasSpecialThemes = cachedEnt.hasSpecialThemes;
          _entitlementCodeUsed = cachedEnt.codeUsed;
          _entitlementRole = cachedEnt.role;
        } else {
          // E-posta henüz doğrulanmamışsa authenticated yapma, OTP ekranında tut
          _status = AuthSessionStatus.unauthenticated;
          _isOtpVerificationMode = true;
          _isUnlimited = false;
          _hasSpecialThemes = false;
          _entitlementCodeUsed = null;
          _entitlementRole = null;
        }
      } else {
        final guestEnabled = await _localStore.isGuestModeEnabled();
        _user = null;
        _isUnlimited = false;
        _hasSpecialThemes = false;
        _entitlementCodeUsed = null;
        _entitlementRole = null;
        _status = guestEnabled
            ? AuthSessionStatus.guest
            : AuthSessionStatus.unauthenticated;
      }
      _enforceSpecialThemeFallback();

      await _authSub?.cancel();
      _authSub = _backend.authStateChanges.listen((nextUser) async {
        if (_isDisposed) return;
        if (nextUser != null) {
          _user = await _enrichUser(nextUser);
          if (!nextUser.emailVerified && !_d1EmailVerified) {
            final savedUid = await _loadPersistedVerifiedUid();
            if (savedUid != null && savedUid == nextUser.uid) {
              _d1EmailVerified = true;
            } else {
              await _checkRemoteD1EmailVerified();
            }
          }
          if (_isDisposed || _user?.uid != nextUser.uid) return;
          if (nextUser.emailVerified || _d1EmailVerified) {
            _status = AuthSessionStatus.authenticated;
            _safeNotify();
            refreshEntitlement();
          } else {
            // E-posta doğrulanana kadar oturum durumunu beklet
            _status = AuthSessionStatus.unauthenticated;
            _isOtpVerificationMode = true;
            _safeNotify();
          }
        } else if (_status == AuthSessionStatus.authenticated) {
          _user = null;
          _isUnlimited = false;
          _hasSpecialThemes = false;
          _entitlementCodeUsed = null;
          _entitlementRole = null;
          _status = AuthSessionStatus.unauthenticated;
          _enforceSpecialThemeFallback();
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
  Future<void> refreshEntitlement({bool forceTokenRefresh = false}) async {
    if (!isAuthenticated || _isSyncingEntitlement) return;
    _isSyncingEntitlement = true;
    _safeNotify();

    try {
      var token = await getIdToken(forceRefresh: forceTokenRefresh);
      if (token == null || token.trim().isEmpty) return;

      var remote = await _entitlementClient.fetchEntitlement(token);
      if (remote == null && !forceTokenRefresh) {
        // Eski/süresi dolmuş Firebase token ihtimaline karşı zorla yenileyip tekrar dene
        final freshToken = await getIdToken(forceRefresh: true);
        if (freshToken != null &&
            freshToken.trim().isNotEmpty &&
            freshToken != token) {
          token = freshToken;
          remote = await _entitlementClient.fetchEntitlement(token);
        }
      }
      if (remote == null) return;

      _isUnlimited = remote.isUnlimited;
      _hasSpecialThemes = remote.effectiveSpecialThemes;
      _entitlementCodeUsed = remote.codeUsed;
      _entitlementRole = remote.isAuthorizedStaff
          ? 'admin'
          : (remote.isUnlimited ? 'premium' : null);
      await _localStore.saveCachedEntitlement(
        isUnlimited: _isUnlimited,
        codeUsed: _entitlementCodeUsed,
        role: _entitlementRole,
        hasSpecialThemes: _hasSpecialThemes,
      );
      _enforceSpecialThemeFallback();
    } catch (error) {
      debugPrint('[AuthController] Yetki yenileme hatasi: $error');
    } finally {
      _isSyncingEntitlement = false;
      _safeNotify();
    }
  }

  /// Kayıtlı kullanıcı için aktivasyon kodunu (`READER2026` vb.) sunucuda doğrular.
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
        _entitlementRole ??= 'premium';
        await _localStore.saveCachedEntitlement(
          isUnlimited: true,
          codeUsed: _entitlementCodeUsed,
          role: _entitlementRole,
          hasSpecialThemes: _hasSpecialThemes,
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
    _hasSpecialThemes = false;
    _entitlementCodeUsed = null;
    _entitlementRole = null;
    _sessionLookupCount = 0;
    _status = AuthSessionStatus.guest;
    _resetQuotaInMemoryIfNewDay();
    _enforceSpecialThemeFallback();
    _safeNotify();
    try {
      await _localStore.setGuestModeEnabled(true);
      await _localStore.saveCachedEntitlement(
        isUnlimited: false,
        hasSpecialThemes: false,
      );
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
      final cleanEmail = email.trim().toLowerCase();
      // Önce bu e-postanın Google ile kayıtlı olup olmadığını denetle
      try {
        final methods = await _backend.fetchSignInMethodsForEmail(cleanEmail);
        if (methods.contains('google.com') && !methods.contains('password')) {
          return const AuthActionResult.failure(
            errorCode: 'account_exists_with_google',
            message:
                'Bu e-posta adresi Google ile kayıtlıdır. Lütfen "Google ile Giriş Yap" butonunu kullanın.',
          );
        }
      } catch (_) {}

      final result = await _backend.signInWithEmail(
        email: cleanEmail,
        password: password,
      );
      if (result.isSuccess && result.user != null) {
        _user = result.user;
        final persistedUid = await _loadPersistedVerifiedUid();
        if (persistedUid != null && persistedUid == result.user!.uid) {
          _d1EmailVerified = true;
        }
        if (!result.user!.emailVerified && !_d1EmailVerified) {
          await _checkRemoteD1EmailVerified();
        }
        if (result.user!.emailVerified || _d1EmailVerified) {
          _status = AuthSessionStatus.authenticated;
          _sessionLookupCount = 0;
          await _localStore.setGuestModeEnabled(false);
          await _syncEntitlementAfterSignIn();
        } else {
          _status = AuthSessionStatus.unauthenticated;
          _isOtpVerificationMode = true;
        }
      }
      return result;
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  bool get isAwaitingEmailVerification =>
      _user != null &&
      _user!.provider == AuthProviderType.email &&
      !_user!.emailVerified &&
      !_d1EmailVerified;

  bool get isOtpVerificationMode => _isOtpVerificationMode;
  int get otpResendCooldownSeconds => _otpResendCooldownSeconds;

  Future<AuthActionResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
    String lang = 'tr',
  }) async {
    if (_isBusy) return const AuthActionResult.cancelled();
    _isBusy = true;
    _safeNotify();

    try {
      final cleanEmail = email.trim().toLowerCase();
      // Google ile kayıtlı bir hesap varsa şifreyle yeniden kaydolmayı engelle
      try {
        final methods = await _backend.fetchSignInMethodsForEmail(cleanEmail);
        if (methods.contains('google.com')) {
          return const AuthActionResult.failure(
            errorCode: 'account_exists_with_google',
            message:
                'Bu e-posta adresi zaten Google ile kayıtlıdır. Lütfen "Google ile Giriş Yap" butonunu kullanın.',
          );
        }
      } catch (_) {}

      final result = await _backend.signUpWithEmail(
        email: cleanEmail,
        password: password,
        displayName: displayName,
      );
      if (result.isSuccess && result.user != null) {
        _user = result.user;
        _d1EmailVerified = false;
        _sessionLookupCount = 0;
        if (result.user!.emailVerified) {
          _status = AuthSessionStatus.authenticated;
          await _localStore.setGuestModeEnabled(false);
          await _syncEntitlementAfterSignIn();
        } else {
          _status = AuthSessionStatus.unauthenticated;
          final token = await _backend.getIdToken();
          if (token != null && token.trim().isNotEmpty) {
            final otpRes = await _entitlementClient.sendEmailVerificationOtp(
              token,
              lang: lang,
            );
            if (otpRes.isSuccess) {
              _isOtpVerificationMode = true;
              _otpResendCooldownSeconds = otpRes.cooldownSeconds;
            } else if (otpRes.fallbackToLink) {
              _isOtpVerificationMode = false;
              await _backend.sendEmailVerification();
            } else {
              _isOtpVerificationMode = true;
              _otpResendCooldownSeconds = otpRes.cooldownSeconds;
            }
          } else {
            _isOtpVerificationMode = false;
            await _backend.sendEmailVerification();
          }
        }
      }
      return result;
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  /// 6 haneli doğrulama kodunu Cloudflare Worker + D1 üzerinden onaylar.
  Future<AuthActionResult> verifyEmailOtp(
    String code, {
    String lang = 'tr',
  }) async {
    if (_isBusy) return const AuthActionResult.cancelled();
    _isBusy = true;
    _safeNotify();

    try {
      final token = await _backend.getIdToken();
      if (token == null || token.trim().isEmpty) {
        return const AuthActionResult.failure(
          errorCode: 'no_token',
          message: 'Oturum doğrulanamadı. Lütfen tekrar deneyin.',
        );
      }

      final otpRes = await _entitlementClient.verifyEmailOtp(
        idToken: token,
        code: code,
        lang: lang,
      );
      if (!otpRes.isSuccess) {
        return AuthActionResult.failure(
          errorCode: 'invalid_otp',
          message: otpRes.message,
        );
      }

      _d1EmailVerified = true;
      await _savePersistedVerifiedUid(_user?.uid);
      _status = AuthSessionStatus.authenticated;
      _sessionLookupCount = 0;
      await _localStore.setGuestModeEnabled(false);
      await _syncEntitlementAfterSignIn();
      return AuthActionResult.success(
        user: _user,
        message: otpRes.message,
      );
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  Future<String?> _loadPersistedVerifiedUid() async {
    try {
      final store = _localStore;
      if (store is AuthLocalRepository) {
        return await store.loadVerifiedEmailUid();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _savePersistedVerifiedUid(String? uid) async {
    try {
      final store = _localStore;
      if (store is AuthLocalRepository) {
        await store.saveVerifiedEmailUid(uid);
      }
    } catch (_) {}
  }

  Future<bool> _checkRemoteD1EmailVerified() async {
    try {
      final token = await getIdToken();
      if (token == null || token.trim().isEmpty) return false;
      final remote = await _entitlementClient.fetchEntitlement(token);
      if (remote != null && remote.emailVerified) {
        _d1EmailVerified = true;
        await _savePersistedVerifiedUid(_user?.uid);
        _isUnlimited = remote.isUnlimited;
        _hasSpecialThemes = remote.effectiveSpecialThemes;
        _entitlementCodeUsed = remote.codeUsed;
        _entitlementRole = remote.isAuthorizedStaff
            ? 'admin'
            : (remote.isUnlimited ? 'premium' : null);
        await _localStore.saveCachedEntitlement(
          isUnlimited: _isUnlimited,
          codeUsed: _entitlementCodeUsed,
          role: _entitlementRole,
          hasSpecialThemes: _hasSpecialThemes,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Sunucudan kullanıcının e-posta doğrulamasını tamamlayıp tamamlamadığını
  /// sessizce kontrol eder; doğrulandıysa oturumu otomatik aktif eder.
  Future<bool> checkEmailVerified() async {
    try {
      if (_d1EmailVerified) return true;
      if (await _checkRemoteD1EmailVerified()) {
        _status = AuthSessionStatus.authenticated;
        _sessionLookupCount = 0;
        await _localStore.setGuestModeEnabled(false);
        _safeNotify();
        return true;
      }
      final reloaded = await _backend.reloadCurrentUser();
      if (reloaded == null) return false;
      _user = reloaded;
      if (reloaded.emailVerified) {
        _d1EmailVerified = true;
        await _savePersistedVerifiedUid(reloaded.uid);
        _status = AuthSessionStatus.authenticated;
        _sessionLookupCount = 0;
        await _localStore.setGuestModeEnabled(false);
        await _syncEntitlementAfterSignIn();
        _safeNotify();
        return true;
      }
      _safeNotify();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<AuthActionResult> resendVerificationEmail({String lang = 'tr'}) async {
    final token = await _backend.getIdToken();
    if (token != null && token.trim().isNotEmpty) {
      final otpRes = await _entitlementClient.sendEmailVerificationOtp(
        token,
        lang: lang,
      );
      if (otpRes.isSuccess) {
        _isOtpVerificationMode = true;
        _otpResendCooldownSeconds = otpRes.cooldownSeconds;
        _safeNotify();
        return AuthActionResult.success(message: otpRes.message);
      }
      if (!otpRes.fallbackToLink) {
        if (otpRes.cooldownSeconds > 0) {
          _otpResendCooldownSeconds = otpRes.cooldownSeconds;
          _safeNotify();
        }
        return AuthActionResult.failure(
          errorCode: 'otp_send_failed',
          message: otpRes.message,
        );
      }
    }
    _isOtpVerificationMode = false;
    _safeNotify();
    return _backend.sendEmailVerification();
  }

  Future<void> _syncEntitlementAfterSignIn() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final token = await _backend.getIdToken();
        if (token == null || token.trim().isEmpty) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue;
          }
          return;
        }
        final remote = await _entitlementClient.fetchEntitlement(token);
        if (remote != null) {
          if (remote.emailVerified) {
            _d1EmailVerified = true;
          }
          _isUnlimited = remote.isUnlimited;
          _hasSpecialThemes = remote.effectiveSpecialThemes;
          _entitlementCodeUsed = remote.codeUsed;
          _entitlementRole = remote.isAuthorizedStaff
              ? 'admin'
              : (remote.isUnlimited ? 'premium' : null);
          await _localStore.saveCachedEntitlement(
            isUnlimited: _isUnlimited,
            codeUsed: _entitlementCodeUsed,
            role: _entitlementRole,
            hasSpecialThemes: _hasSpecialThemes,
          );
          _enforceSpecialThemeFallback();
          _safeNotify();
          return;
        }
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }
    }
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
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (!isAuthenticated) return null;
    return _backend.getIdToken(forceRefresh: forceRefresh);
  }

  /// Kullanıcının varsa yerel olarak özelleştirilmiş görünen adını ekler.
  Future<AppAuthUser> _enrichUser(AppAuthUser user) async {
    final rawName = user.displayName?.trim() ?? '';
    if (rawName.isNotEmpty) {
      return user;
    }
    if (_localStore is AuthLocalRepository) {
      final custom = await (_localStore as AuthLocalRepository).loadCustomDisplayName();
      if (custom != null && custom.isNotEmpty) {
        return user.copyWith(displayName: custom);
      }
    }
    return user;
  }

  /// Kullanıcının profil görünen adını (Display Name) günceller ve kaydeder.
  Future<bool> updateDisplayName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _backend.updateDisplayName(trimmed);
      final current = _user;
      if (current != null) {
        _user = current.copyWith(displayName: trimmed);
      }
      if (_localStore is AuthLocalRepository) {
        await (_localStore as AuthLocalRepository).saveCustomDisplayName(trimmed);
      }
      _safeNotify();
      return true;
    } catch (e) {
      debugPrint('[AuthController] Isim guncellenemedi: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    if (_isBusy) return;
    _isBusy = true;
    _safeNotify();

    try {
      await _backend.signOut();
      await _localStore.setGuestModeEnabled(true);
      await _localStore.saveCachedEntitlement(
        isUnlimited: false,
        hasSpecialThemes: false,
      );
      _user = null;
      _d1EmailVerified = false;
      _isOtpVerificationMode = true;
      _otpResendCooldownSeconds = 0;
      _isUnlimited = false;
      _hasSpecialThemes = false;
      _entitlementCodeUsed = null;
      _entitlementRole = null;
      _sessionLookupCount = 0;
      _status = AuthSessionStatus.guest;
      _enforceSpecialThemeFallback();
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
