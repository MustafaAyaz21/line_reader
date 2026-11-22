import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/settings_repository.dart';
import '../data/auth_local_repository.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';

/// Kullanıcı oturumunu (Google / E-posta / Misafir) ve misafir kullanıcılar için
/// günlük 40 kelime çeviri kotasını yöneten denetleyici.
class AuthController extends ChangeNotifier {
  AuthController({
    AuthBackend? backend,
    AuthLocalStore? localStore,
    DateTime Function()? nowProvider,
  })  : _backend = backend ?? FirebaseAuthBackend(),
        _localStore = localStore ??
            AuthLocalRepository(SettingsRepository(AppDatabase.instance)),
        _nowProvider = nowProvider ?? DateTime.now;

  static const int guestDailyTranslationLimit = 40;

  final AuthBackend _backend;
  final AuthLocalStore _localStore;
  final DateTime Function() _nowProvider;

  StreamSubscription<AppAuthUser?>? _authSub;
  AuthSessionStatus _status = AuthSessionStatus.loading;
  AppAuthUser? _user;
  bool _isBusy = false;
  String _quotaDateKey = '';
  int _guestUsedToday = 0;
  bool _isDisposed = false;

  AuthSessionStatus get status => _status;
  AppAuthUser? get user => _user;
  bool get isBusy => _isBusy;
  bool get isFirebaseConfigured => _backend.isConfigured;

  bool get isLoading => _status == AuthSessionStatus.loading;
  bool get isAuthenticated => _status == AuthSessionStatus.authenticated;
  bool get isGuest => _status == AuthSessionStatus.guest;
  bool get needsOnboarding => _status == AuthSessionStatus.unauthenticated;

  int get guestUsedToday {
    _resetQuotaInMemoryIfNewDay();
    return _guestUsedToday;
  }

  int get guestRemainingToday {
    if (isAuthenticated) return guestDailyTranslationLimit;
    return (guestDailyTranslationLimit - guestUsedToday)
        .clamp(0, guestDailyTranslationLimit);
  }

  bool get hasReachedGuestLimit => isGuest && guestRemainingToday <= 0;

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
      _guestUsedToday = 0;
    }
  }

  /// Uygulama açılışında oturum ve günlük misafir kotasını yükler.
  Future<void> initialize() async {
    try {
      await _backend.initialize();
      final quota = await _localStore.loadGuestQuota();
      final today = _todayKey();
      if (quota.dateKey == today) {
        _quotaDateKey = today;
        _guestUsedToday = quota.usedCount;
      } else {
        _quotaDateKey = today;
        _guestUsedToday = 0;
      }

      final current = _backend.currentUser;
      if (current != null) {
        _user = current;
        _status = AuthSessionStatus.authenticated;
      } else {
        final guestEnabled = await _localStore.isGuestModeEnabled();
        _user = null;
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
        } else if (_status == AuthSessionStatus.authenticated) {
          _user = null;
          _status = AuthSessionStatus.unauthenticated;
          _safeNotify();
        }
      });
    } catch (error) {
      debugPrint('[AuthController] Ilklendirme hatasi: $error');
      _status = AuthSessionStatus.unauthenticated;
    } finally {
      _safeNotify();
    }
  }

  /// Misafir kullanıcı çeviri yapmadan önce günlük 40 kelime kotasını kontrol
  /// edip 1 azaltır. Hesapla giriş yapmış kullanıcılar için her zaman `true`
  /// (sınırsız) döner.
  Future<bool> consumeTranslationQuotaIfGuest() async {
    if (isAuthenticated) return true;

    final today = _todayKey();
    if (_quotaDateKey != today) {
      _quotaDateKey = today;
      _guestUsedToday = 0;
    }

    if (_guestUsedToday >= guestDailyTranslationLimit) {
      _safeNotify();
      return false;
    }

    _guestUsedToday += 1;
    _safeNotify();

    try {
      await _localStore.saveGuestQuota(
        dateKey: today,
        usedCount: _guestUsedToday,
      );
    } catch (error) {
      debugPrint('[AuthController] Kota kaydetme hatasi: $error');
    }

    return true;
  }

  Future<void> continueAsGuest() async {
    _user = null;
    _status = AuthSessionStatus.guest;
    _resetQuotaInMemoryIfNewDay();
    _safeNotify();
    try {
      await _localStore.setGuestModeEnabled(true);
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
        await _localStore.setGuestModeEnabled(false);
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
        await _localStore.setGuestModeEnabled(false);
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
        await _localStore.setGuestModeEnabled(false);
      }
      return result;
    } finally {
      _isBusy = false;
      _safeNotify();
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

  Future<void> signOut() async {
    if (_isBusy) return;
    _isBusy = true;
    _safeNotify();

    try {
      await _backend.signOut();
      await _localStore.setGuestModeEnabled(true);
      _user = null;
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
    super.dispose();
  }
}
