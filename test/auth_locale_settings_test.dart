import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linereader/core/database/app_database.dart';
import 'package:linereader/core/localization/app_locale.dart';
import 'package:linereader/core/settings/api_key_controller.dart';
import 'package:linereader/core/settings/settings_repository.dart';
import 'package:linereader/features/auth/controllers/auth_controller.dart';
import 'package:linereader/features/auth/data/auth_local_repository.dart';
import 'package:linereader/features/auth/models/auth_user.dart';
import 'package:linereader/features/auth/screens/auth_screen.dart';
import 'package:linereader/features/auth/services/auth_service.dart';
import 'package:linereader/features/settings/screens/settings_screen.dart';

class _InMemoryLanguageStore implements AppLanguageStore {
  AppLanguage saved = AppLanguage.tr;

  @override
  Future<AppLanguage> loadLanguage() async => saved;

  @override
  Future<void> saveLanguage(AppLanguage language) async {
    saved = language;
  }
}

class _InMemoryAuthLocalStore implements AuthLocalStore {
  bool guestEnabled = false;
  String quotaDate = '';
  int quotaUsed = 0;

  @override
  Future<bool> isGuestModeEnabled() async => guestEnabled;

  @override
  Future<void> setGuestModeEnabled(bool enabled) async {
    guestEnabled = enabled;
  }

  @override
  Future<({String dateKey, int usedCount})> loadGuestQuota() async {
    return (dateKey: quotaDate, usedCount: quotaUsed);
  }

  @override
  Future<void> saveGuestQuota({
    required String dateKey,
    required int usedCount,
  }) async {
    quotaDate = dateKey;
    quotaUsed = usedCount;
  }
}

class _FakeAuthBackend implements AuthBackend {
  final StreamController<AppAuthUser?> _stream =
      StreamController<AppAuthUser?>.broadcast();
  AppAuthUser? _current;

  @override
  bool get isConfigured => true;

  @override
  Future<void> initialize() async {}

  @override
  AppAuthUser? get currentUser => _current;

  @override
  Stream<AppAuthUser?> get authStateChanges => _stream.stream;

  @override
  Future<AuthActionResult> signInWithGoogle() async {
    _current = const AppAuthUser(
      uid: 'google-1',
      email: 'mustafa@gmail.com',
      displayName: 'Mustafa',
      provider: AuthProviderType.google,
    );
    _stream.add(_current);
    return AuthActionResult.success(user: _current);
  }

  @override
  Future<AuthActionResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _current = AppAuthUser(
      uid: 'email-1',
      email: email,
      provider: AuthProviderType.email,
    );
    _stream.add(_current);
    return AuthActionResult.success(user: _current);
  }

  @override
  Future<AuthActionResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _current = AppAuthUser(
      uid: 'email-2',
      email: email,
      displayName: displayName,
      provider: AuthProviderType.email,
    );
    _stream.add(_current);
    return AuthActionResult.success(user: _current);
  }

  @override
  Future<AuthActionResult> sendPasswordResetEmail(String email) async {
    return const AuthActionResult.success(message: 'Sent');
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _stream.add(null);
  }
}

void main() {
  group('AuthController & Günlük 40 Kelime Misafir Kotası', () {
    test('misafir kullanıcı günde en fazla 40 çeviri yapabilir ve ertesi gün sıfırlanır',
        () async {
      var fakeNow = DateTime(2026, 11, 22, 10, 0);
      final localStore = _InMemoryAuthLocalStore();
      final controller = AuthController(
        backend: _FakeAuthBackend(),
        localStore: localStore,
        nowProvider: () => fakeNow,
      );

      await controller.initialize();
      expect(controller.needsOnboarding, isTrue);

      await controller.continueAsGuest();
      expect(controller.isGuest, isTrue);
      expect(controller.guestRemainingToday, 40);

      for (var i = 0; i < 40; i++) {
        final allowed = await controller.consumeTranslationQuotaIfGuest();
        expect(allowed, isTrue);
      }
      expect(controller.guestRemainingToday, 0);
      expect(controller.hasReachedGuestLimit, isTrue);

      // 41. çeviri engellenmeli.
      final overLimit = await controller.consumeTranslationQuotaIfGuest();
      expect(overLimit, isFalse);

      // Ertesi gün kota yeniden 40 olmalı.
      fakeNow = DateTime(2026, 11, 23, 0, 5);
      expect(controller.guestRemainingToday, 40);
      expect(await controller.consumeTranslationQuotaIfGuest(), isTrue);
      expect(controller.guestRemainingToday, 39);

      // Google ile giriş yapınca sınırsız olmalı.
      final res = await controller.signInWithGoogle();
      expect(res.isSuccess, isTrue);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.hasReachedGuestLimit, isFalse);
      for (var i = 0; i < 60; i++) {
        expect(await controller.consumeTranslationQuotaIfGuest(), isTrue);
      }

      controller.dispose();
    });
  });

  group('AuthScreen & SettingsScreen & Dil Seçimi', () {
    testWidgets('AuthScreen misafir 40 kelime bilgisini ve Google/E-posta seçeneklerini gösterir',
        (tester) async {
      final localeController =
          AppLocaleController(store: _InMemoryLanguageStore());
      final authController = AuthController(
        backend: _FakeAuthBackend(),
        localStore: _InMemoryAuthLocalStore(),
      );
      await authController.initialize();

      await tester.pumpWidget(
        AppLocaleScope(
          controller: localeController,
          child: MaterialApp(
            home: AuthScreen(controller: authController),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('auth_google_button')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('auth_email_field')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('auth_guest_button')), findsOneWidget);
      expect(find.textContaining('40 kelime'), findsOneWidget);

      final guestButton = find.byKey(const ValueKey<String>('auth_guest_button'));
      await tester.ensureVisible(guestButton);
      await tester.pumpAndSettle();
      await tester.tap(guestButton);
      await tester.pumpAndSettle();
      expect(authController.isGuest, isTrue);

      authController.dispose();
      localeController.dispose();
    });

    testWidgets('SettingsScreen dil değiştirince arayüz anında İngilizceye geçer ve kaydeder',
        (tester) async {
      final langStore = _InMemoryLanguageStore();
      final localeController = AppLocaleController(store: langStore);
      final authController = AuthController(
        backend: _FakeAuthBackend(),
        localStore: _InMemoryAuthLocalStore(),
      );
      await authController.initialize();
      await authController.continueAsGuest();

      final apiKeyController = ApiKeyController(
        SettingsRepository(AppDatabase.instance),
      );

      await tester.pumpWidget(
        AppLocaleScope(
          controller: localeController,
          child: ListenableBuilder(
            listenable: localeController,
            builder: (context, _) {
              return MaterialApp(
                home: SettingsScreen(
                  apiKeyController: apiKeyController,
                  localeController: localeController,
                  authController: authController,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ayarlar'), findsOneWidget);
      expect(find.text('Misafir Modu'), findsOneWidget);
      expect(find.textContaining('40 / 40'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('settings_api_key_tile')), findsOneWidget);

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(langStore.saved, AppLanguage.en);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Guest Mode'), findsOneWidget);

      apiKeyController.dispose();
      authController.dispose();
      localeController.dispose();
    });
  });
}
