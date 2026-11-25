import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linereader/core/database/app_database.dart';
import 'package:linereader/core/localization/app_locale.dart';
import 'package:linereader/core/settings/api_key_controller.dart';
import 'package:linereader/core/settings/settings_repository.dart';
import 'package:linereader/features/ads/widgets/promo_interstitial_dialog.dart';
import 'package:linereader/features/auth/controllers/auth_controller.dart';
import 'package:linereader/features/auth/data/auth_local_repository.dart';
import 'package:linereader/features/auth/models/auth_user.dart';
import 'package:linereader/features/auth/screens/auth_screen.dart';
import 'package:linereader/features/auth/services/auth_service.dart';
import 'package:linereader/features/auth/services/entitlement_service.dart';
import 'package:linereader/features/settings/screens/developer_panel_screen.dart';
import 'package:linereader/features/settings/screens/settings_screen.dart';
import 'package:linereader/features/settings/services/developer_panel_service.dart';
import 'package:linereader/features/update/controllers/app_update_controller.dart';
import 'package:linereader/features/update/models/app_update_info.dart';
import 'package:linereader/features/update/services/app_update_service.dart';

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
  bool cachedUnlimited = false;
  bool cachedSpecialThemes = false;
  String? cachedCodeUsed;
  String? cachedRole;

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

  @override
  Future<({
    bool isUnlimited,
    String? codeUsed,
    String? role,
    bool hasSpecialThemes,
  })> loadCachedEntitlement() async {
    return (
      isUnlimited: cachedUnlimited,
      codeUsed: cachedCodeUsed,
      role: cachedRole,
      hasSpecialThemes: cachedSpecialThemes,
    );
  }

  @override
  Future<void> saveCachedEntitlement({
    required bool isUnlimited,
    String? codeUsed,
    String? role,
    bool hasSpecialThemes = false,
  }) async {
    cachedUnlimited = isUnlimited;
    cachedSpecialThemes = hasSpecialThemes;
    cachedCodeUsed = isUnlimited ? codeUsed : null;
    cachedRole = isUnlimited ? role : null;
  }
}

class _FakeEntitlementClient extends EntitlementClient {
  bool remoteUnlimited = false;
  String? remoteCodeUsed;
  String? remoteRole;
  String? remoteSource;
  final String validCode = 'READER2026';

  @override
  Future<EntitlementStatus?> fetchEntitlement(String idToken) async {
    return EntitlementStatus(
      isUnlimited: remoteUnlimited,
      source: remoteSource ?? (remoteUnlimited ? 'code' : 'none'),
      codeUsed: remoteCodeUsed,
      role: remoteRole,
    );
  }

  @override
  Future<RedeemCodeResult> redeemCode({
    required String idToken,
    required String code,
  }) async {
    final normalized = code.trim().toUpperCase();
    if (normalized == validCode) {
      remoteUnlimited = true;
      remoteCodeUsed = normalized;
      return RedeemCodeResult(
        isSuccess: true,
        message: 'Sınırsız yetki aktif edildi!',
        code: normalized,
      );
    }
    return const RedeemCodeResult(
      isSuccess: false,
      message: 'Geçersiz veya kullanılmış kod.',
    );
  }

  @override
  void dispose() {}
}

class _FakeAuthBackend implements AuthBackend {
  _FakeAuthBackend({this.signUpReturnsUnverified = false});

  final bool signUpReturnsUnverified;
  final StreamController<AppAuthUser?> _stream =
      StreamController<AppAuthUser?>.broadcast();
  AppAuthUser? _current;
  int verificationSendCount = 0;

  void markEmailVerified() {
    if (_current == null) return;
    _current = AppAuthUser(
      uid: _current!.uid,
      email: _current!.email,
      displayName: _current!.displayName,
      photoUrl: _current!.photoUrl,
      provider: _current!.provider,
      emailVerified: true,
    );
  }

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
      email: 'reader@example.com',
      displayName: 'Reader User',
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
      emailVerified: !signUpReturnsUnverified,
    );
    _stream.add(_current);
    return AuthActionResult.success(user: _current);
  }

  @override
  Future<AuthActionResult> sendEmailVerification() async {
    verificationSendCount += 1;
    return const AuthActionResult.success();
  }

  @override
  Future<AppAuthUser?> reloadCurrentUser() async => _current;

  @override
  Future<AuthActionResult> sendPasswordResetEmail(String email) async {
    return const AuthActionResult.success(message: 'Sent');
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async =>
      _current == null ? null : 'fake-jwt-token';

  @override
  Future<void> signOut() async {
    _current = null;
    _stream.add(null);
  }
}

class _FakeAppUpdateService extends AppUpdateService {
  _FakeAppUpdateService(this.fakeResult);

  final AppUpdateCheckResult fakeResult;

  @override
  Future<AppUpdateCheckResult> checkUpdateStatus() async => fakeResult;
}

void main() {
  group('AuthController • 3 Katmanlı Kota, Kod Kullanımı & Reklam Sıklığı', () {
    test(
      'Misafir 40, standart kayıtlı 80, aktivasyon kodlu sınırsız kota uygular',
      () async {
        var fakeNow = DateTime(2026, 11, 22, 10, 0);
        final localStore = _InMemoryAuthLocalStore();
        final entitlementClient = _FakeEntitlementClient();
        final controller = AuthController(
          backend: _FakeAuthBackend(),
          localStore: localStore,
          entitlementClient: entitlementClient,
          nowProvider: () => fakeNow,
        );

        await controller.initialize();
        expect(controller.needsOnboarding, isTrue);

        // 1) Misafir: günlük 40 kelime
        await controller.continueAsGuest();
        expect(controller.isGuest, isTrue);
        expect(controller.dailyTranslationLimit, 40);
        expect(controller.guestRemainingToday, 40);

        for (var i = 0; i < 40; i++) {
          expect(await controller.consumeTranslationQuota(), isTrue);
        }
        expect(controller.guestRemainingToday, 0);
        expect(controller.hasReachedGuestLimit, isTrue);
        expect(await controller.consumeTranslationQuota(), isFalse);

        // Ertesi gün sıfırlanır
        fakeNow = DateTime(2026, 11, 23, 0, 5);
        expect(controller.guestRemainingToday, 40);

        // 2) Kayıtlı Standart Hesap: günlük 80 kelime (kod kullanmadan sınırsız değil)
        final res = await controller.signInWithGoogle();
        expect(res.isSuccess, isTrue);
        expect(controller.isAuthenticated, isTrue);
        expect(controller.isUnlimited, isFalse);
        expect(controller.dailyTranslationLimit, 80);

        for (var i = 0; i < 80; i++) {
          expect(await controller.consumeTranslationQuota(), isTrue);
        }
        expect(controller.dailyRemainingToday, 0);
        expect(controller.hasReachedDailyLimit, isTrue);
        expect(await controller.consumeTranslationQuota(), isFalse);

        // 3) Geçersiz kod reddedilir, doğru kod (READER2026) sınırsız açar
        final badRedeem = await controller.redeemAccessCode('YANLIS');
        expect(badRedeem.isSuccess, isFalse);
        expect(controller.isUnlimited, isFalse);

        final goodRedeem = await controller.redeemAccessCode('reader2026');
        expect(goodRedeem.isSuccess, isTrue);
        expect(controller.isUnlimited, isTrue);
        expect(controller.entitlementCodeUsed, 'READER2026');
        expect(controller.hasReachedDailyLimit, isFalse);

        for (var i = 0; i < 120; i++) {
          expect(await controller.consumeTranslationQuota(), isTrue);
        }

        controller.dispose();
      },
    );

    test(
      'Özel duyuru/reklam sıklığı misafirde 5, standart hesapta 8, yetkilide 0 olur',
      () async {
        final controller = AuthController(
          backend: _FakeAuthBackend(),
          localStore: _InMemoryAuthLocalStore(),
          entitlementClient: _FakeEntitlementClient(),
        );
        await controller.initialize();
        await controller.continueAsGuest();

        // Misafir: 5. ve 10. sorguda true
        final guestTriggers = <int>[];
        for (var i = 1; i <= 12; i++) {
          if (controller.recordWordLookupAndShouldShowPromo()) {
            guestTriggers.add(i);
          }
        }
        expect(guestTriggers, <int>[5, 10]);

        // Standart kayıtlı: 8. ve 16. sorguda true
        await controller.signInWithGoogle();
        final standardTriggers = <int>[];
        for (var i = 1; i <= 18; i++) {
          if (controller.recordWordLookupAndShouldShowPromo()) {
            standardTriggers.add(i);
          }
        }
        expect(standardTriggers, <int>[8, 16]);

        // Yetkili (kod kullanmış): hiç gösterilmez
        await controller.redeemAccessCode('READER2026');
        final unlimitedTriggers = <int>[];
        for (var i = 1; i <= 20; i++) {
          if (controller.recordWordLookupAndShouldShowPromo()) {
            unlimitedTriggers.add(i);
          }
        }
        expect(unlimitedTriggers, isEmpty);

        controller.dispose();
      },
    );
  });

  group('PromoInterstitialDialog (5 saniye geri sayım)', () {
    testWidgets('0. saniyede geçilemez, 5 saniye sonra geçilebilir', (
      tester,
    ) async {
      final localeController =
          AppLocaleController(store: _InMemoryLanguageStore());

      await tester.pumpWidget(
        AppLocaleScope(
          controller: localeController,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => PromoInterstitialDialog.show(context),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      expect(find.text('Geliştirme Aşamasındayız'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('promo_countdown_pill')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('promo_skip_button')),
        findsNothing,
      );

      // 5 saniye ilerlet
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('promo_skip_button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('promo_skip_button')));
      await tester.pumpAndSettle();

      expect(find.text('Geliştirme Aşamasındayız'), findsNothing);
      localeController.dispose();
    });
  });

  group('AuthScreen & SettingsScreen & Kod Kullan UI', () {
    testWidgets(
      'AuthScreen misafir 40 kelime bilgisini ve Google/E-posta seçeneklerini gösterir',
      (tester) async {
        final localeController =
            AppLocaleController(store: _InMemoryLanguageStore());
        final authController = AuthController(
          backend: _FakeAuthBackend(),
          localStore: _InMemoryAuthLocalStore(),
          entitlementClient: _FakeEntitlementClient(),
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

        expect(
          find.byKey(const ValueKey<String>('auth_google_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('auth_email_field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('auth_guest_button')),
          findsOneWidget,
        );
        expect(find.textContaining('40 kelime'), findsOneWidget);

        final guestButton =
            find.byKey(const ValueKey<String>('auth_guest_button'));
        await tester.ensureVisible(guestButton);
        await tester.pumpAndSettle();
        await tester.tap(guestButton);
        await tester.pumpAndSettle();
        expect(authController.isGuest, isTrue);

        authController.dispose();
        localeController.dispose();
      },
    );

    testWidgets(
      'SettingsScreen dil değiştirince arayüz anında İngilizceye geçer ve kaydeder',
      (tester) async {
        final langStore = _InMemoryLanguageStore();
        final localeController = AppLocaleController(store: langStore);
        final authController = AuthController(
          backend: _FakeAuthBackend(),
          localStore: _InMemoryAuthLocalStore(),
          entitlementClient: _FakeEntitlementClient(),
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
        expect(find.byKey(const ValueKey<String>('settings_cat_profile')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('settings_cat_appearance')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('settings_cat_features')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('settings_cat_quick_lookup')), findsOneWidget);
        expect(find.textContaining('Misafir Modu'), findsOneWidget);
        expect(find.textContaining('40 / 40'), findsOneWidget);

        // Görünüm ve Temalar kartına girip dili English yap.
        await tester.tap(find.byKey(const ValueKey<String>('settings_cat_appearance')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('English'));
        await tester.pumpAndSettle();

        expect(langStore.saved, AppLanguage.en);
        expect(find.text('Appearance & Themes'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
        expect(find.textContaining('Guest Mode'), findsOneWidget);

        // Line'da Bak kartına girip özelleştirme kontrollerini doğrula.
        await tester.tap(find.byKey(const ValueKey<String>('settings_cat_quick_lookup')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('overlay_ipa_mode_us')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('overlay_show_synonyms_switch')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('overlay_show_antonyms_switch')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('overlay_show_tts_switch')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('overlay_show_save_bar_switch')), findsOneWidget);

        apiKeyController.dispose();
        authController.dispose();
        localeController.dispose();
      },
    );

    testWidgets(
      'SettingsScreen standart hesapta Kod Kullan gösterir ve READER2026 sonrası Sınırsız olur',
      (tester) async {
        final localeController =
            AppLocaleController(store: _InMemoryLanguageStore());
        final authController = AuthController(
          backend: _FakeAuthBackend(),
          localStore: _InMemoryAuthLocalStore(),
          entitlementClient: _FakeEntitlementClient(),
        );
        await authController.initialize();
        await authController.signInWithGoogle();

        final apiKeyController = ApiKeyController(
          SettingsRepository(AppDatabase.instance),
        );

        await tester.pumpWidget(
          AppLocaleScope(
            controller: localeController,
            child: MaterialApp(
              home: SettingsScreen(
                apiKeyController: apiKeyController,
                localeController: localeController,
                authController: authController,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('settings_cat_profile')));
        await tester.pumpAndSettle();

        expect(find.text('Standart Hesap'), findsOneWidget);
        expect(find.textContaining('80 / 80'), findsOneWidget);
        final codeField =
            find.byKey(const ValueKey<String>('settings_redeem_code_field'));
        final applyBtn =
            find.byKey(const ValueKey<String>('settings_redeem_code_button'));
        expect(codeField, findsOneWidget);
        expect(applyBtn, findsOneWidget);

        await tester.enterText(codeField, 'READER2026');
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('settings_unlimited_badge')),
          findsOneWidget,
        );
        expect(find.text('Premium Üye'), findsOneWidget);
        expect(find.text('Yetkiyi Yenile'), findsNothing);
        expect(find.text('Çıkış Yap'), findsOneWidget);
        expect(find.textContaining('READER2026'), findsOneWidget);

        apiKeyController.dispose();
        authController.dispose();
        localeController.dispose();
      },
    );

    testWidgets(
      'Yetkili (admin) rolündeki hesapta Ayarlar ekranında Premium Üye yerine Yetkili yazar',
      (WidgetTester tester) async {
        final localStore = _InMemoryAuthLocalStore();
        final entitlementClient = _FakeEntitlementClient()
          ..remoteUnlimited = true
          ..remoteRole = 'admin'
          ..remoteSource = 'admin';
        final authController = AuthController(
          backend: _FakeAuthBackend(),
          localStore: localStore,
          entitlementClient: entitlementClient,
        );
        await authController.initialize();
        await authController.signInWithGoogle();
        expect(authController.isUnlimited, isTrue);
        expect(authController.isAuthorizedStaff, isTrue);

        final localeController = AppLocaleController(
          store: _InMemoryLanguageStore(),
        );
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

        await tester.tap(find.byKey(const ValueKey<String>('settings_cat_profile')));
        await tester.pumpAndSettle();

        expect(find.text('Geliştirici'), findsOneWidget);
        expect(find.text('Premium Üye'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('settings_developer_panel_button')),
          findsOneWidget,
        );

        await localeController.setLanguage(AppLanguage.en);
        await tester.pumpAndSettle();
        expect(find.text('Developer'), findsOneWidget);
        expect(find.text('Premium Member'), findsNothing);
        expect(find.text('Developer Panel'), findsOneWidget);

        apiKeyController.dispose();
        authController.dispose();
        localeController.dispose();
      },
    );

    testWidgets(
      'DeveloperPanelScreen sends Bearer token to /dev/users and /dev/codes to grant Premium and create codes',
      (WidgetTester tester) async {
        final localStore = _InMemoryAuthLocalStore();
        final entitlementClient = _FakeEntitlementClient()
          ..remoteUnlimited = true
          ..remoteRole = 'admin'
          ..remoteSource = 'admin';
        final authController = AuthController(
          backend: _FakeAuthBackend(),
          localStore: localStore,
          entitlementClient: entitlementClient,
        );
        await authController.initialize();
        await authController.signInWithGoogle();

        final users = <Map<String, Object?>>[
          <String, Object?>{
            'email': 'dev@gmail.com',
            'source': 'admin',
            'is_unlimited': 1,
          },
        ];
        final codes = <Map<String, Object?>>[];
        final articles = <Map<String, Object?>>[];
        String? capturedAuthHeader;

        final mockClient = MockClient((request) async {
          capturedAuthHeader = request.headers['Authorization'];
          final path = request.url.path;
          if (path.endsWith('/dev/users') && request.method == 'GET') {
            return http.Response(
              jsonEncode(<String, Object?>{'ok': true, 'users': users}),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/dev/users') && request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final email = body['email'].toString();
            users.add(<String, Object?>{
              'email': email,
              'source': 'manual',
              'is_unlimited': 1,
              'code_used': 'dev:dev@gmail.com',
            });
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': true,
                'role': 'premium',
                'message': '$email hesabına Premium Üye yetkisi verildi.',
              }),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/dev/codes') && request.method == 'GET') {
            return http.Response(
              jsonEncode(<String, Object?>{'ok': true, 'codes': codes}),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/dev/codes') && request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final code = body['code'].toString();
            codes.add(<String, Object?>{
              'code': code,
              'max_uses': body['max_uses'] ?? 5,
              'used_count': 0,
              'is_active': 1,
              'note': 'Geliştirici: dev@gmail.com',
            });
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': true,
                'code': code,
                'message': '$code kodu oluşturuldu.',
              }),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/dev/articles') && request.method == 'GET') {
            return http.Response(
              jsonEncode(<String, Object?>{'ok': true, 'articles': articles}),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/dev/articles/generate') &&
              request.method == 'POST') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': true,
                'article': <String, Object?>{
                  'id': 'b1-mobile-space-travel',
                  'level': 'B1',
                  'title': 'Future of Space Travel',
                  'content':
                      'Modern rockets are changing how humans explore space every year.\n\nScientists are planning new missions to the Moon and Mars.',
                  'word_meanings': <String, String>{'rockets': 'roketler'},
                  'sentence_translations': <String, String>{
                    'Modern rockets are changing how humans explore space every year.':
                        'Modern roketler insanların uzayı keşfetme biçimini her yıl değiştiriyor.',
                  },
                  'word_relations': <String, Object?>{
                    'modern': <String, Object?>{
                      'syn': <String>['contemporary'],
                      'ant': <String>['ancient'],
                    },
                  },
                },
              }),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/dev/articles/audio') && request.method == 'POST') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': true,
                'audio_url':
                    'https://raw.githubusercontent.com/MustafaAyaz21/line_reader/main/audio/b1-mobile-space-travel.wav',
                'audio_voice': 'Kore',
                'audio_duration_sec': 42,
                'message': 'Podcast AI sesi oluşturuldu (42 sn).',
              }),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/dev/articles/publish') &&
              request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final art = body['article'] as Map<String, dynamic>;
            articles.add(<String, Object?>{
              'id': art['id'],
              'level': art['level'],
              'title': art['title'],
              'is_hidden': art['is_hidden'] == true,
              'has_audio': art['audio_url'] != null,
              'audio_url': art['audio_url'],
            });
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': true,
                'id': art['id'],
                'message': '"${art['title']}" anında yayınlandı!',
              }),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        });

        final devService = DeveloperPanelService(httpClient: mockClient);
        final localeController = AppLocaleController(
          store: _InMemoryLanguageStore(),
        );

        await tester.pumpWidget(
          AppLocaleScope(
            controller: localeController,
            child: MaterialApp(
              home: DeveloperPanelScreen(
                authController: authController,
                service: devService,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(capturedAuthHeader, startsWith('Bearer '));
        expect(find.text('dev@gmail.com'), findsOneWidget);

        // 1) Yeni Gmail'e Premium Üye ver
        await tester.enterText(
          find.byKey(const ValueKey<String>('dev_panel_email_field')),
          'arkadas@gmail.com',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('dev_panel_grant_premium_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('arkadas@gmail.com'), findsOneWidget);

        // 2) Kodlar sekmesine geç, rastgele kod üret ve oluştur
        await tester.tap(find.text('Kodlar'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('dev_panel_random_code_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('dev_panel_create_code_btn')),
        );
        await tester.pumpAndSettle();
        expect(codes.length, 1);
        expect(find.text(codes.first['code']! as String), findsOneWidget);

        // 3) Makaleler sekmesine geç: Makale Yayınla bölümünü aç -> Gemini üret -> Podcast AI sesi üret -> Anında yayınla
        await tester.tap(find.text('Makaleler'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey<String>('dev_panel_toggle_publish_section_btn'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('dev_panel_generate_article_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Taslak Hazır'), findsOneWidget);

        await tester.drag(find.byType(ListView).last, const Offset(0, -520));
        await tester.pumpAndSettle();
        final audioBtn = find.byKey(
          const ValueKey<String>('dev_panel_generate_audio_btn'),
        );
        await tester.tap(audioBtn);
        await tester.pumpAndSettle();
        expect(find.textContaining('Podcast Hazır (42 sn)'), findsOneWidget);

        await tester.drag(find.byType(ListView).last, const Offset(0, -320));
        await tester.pumpAndSettle();
        final publishBtn = find.byKey(
          const ValueKey<String>('dev_panel_publish_article_btn'),
        );
        await tester.tap(publishBtn);
        await tester.pumpAndSettle();
        expect(articles.length, 1);
        expect(articles.first['has_audio'], isTrue);
        await tester.drag(find.byType(ListView).last, const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(find.text('Future of Space Travel'), findsOneWidget);

        authController.dispose();
        localeController.dispose();
      },
    );
  });

  group('AppUpdateController • Zorunlu Minimum Sürüm (min_version_code)', () {
    test('currentBuildNumber < min_version_code olduğunda zorunlu güncelleme tetiklenir',
        () async {
      final info = AppUpdateInfo.fromJson(<String, Object?>{
        'latest_version': '0.1.16',
        'version_code': 17,
        'min_version_code': 16,
        'apk_url': 'https://example.com/app-release.apk',
        'release_notes': 'Performans iyileştirmeleri.',
      });
      expect(info.minVersionCode, 16);

      final mandatoryController = AppUpdateController(
        service: _FakeAppUpdateService(
          AppUpdateCheckResult(
            currentVersion: '0.1.14',
            currentBuildNumber: 15,
            remoteInfo: info,
          ),
        ),
      );
      await mandatoryController.checkForUpdates();
      expect(mandatoryController.hasUpdate, isTrue);
      expect(mandatoryController.requiresMandatoryUpdate, isTrue);
      mandatoryController.dispose();

      final optionalController = AppUpdateController(
        service: _FakeAppUpdateService(
          AppUpdateCheckResult(
            currentVersion: '0.1.15',
            currentBuildNumber: 16,
            remoteInfo: info,
          ),
        ),
      );
      await optionalController.checkForUpdates();
      expect(optionalController.hasUpdate, isTrue);
      expect(optionalController.requiresMandatoryUpdate, isFalse);
      optionalController.dispose();
    });
  });

  group('AuthScreen • Zorunlu Kayıt Alanları & Otomatik E-posta Doğrulama', () {
    testWidgets(
      'Kayıtta Ad Soyad zorunlu olur; doğrulama sonrası otomatik Doğrulandınız ekranına geçer',
      (tester) async {
        final backend = _FakeAuthBackend(signUpReturnsUnverified: true);
        final authController = AuthController(
          backend: backend,
          localStore: _InMemoryAuthLocalStore(),
          entitlementClient: _FakeEntitlementClient(),
        );
        await authController.initialize();
        final localeController = AppLocaleController(
          store: _InMemoryLanguageStore(),
        );
        await localeController.load();

        await tester.pumpWidget(
          AppLocaleScope(
            controller: localeController,
            child: MaterialApp(
              home: AuthScreen(
                controller: authController,
                canPop: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Kayıt Ol sekmesine geç
        await tester.tap(find.text('Kayıt Ol'));
        await tester.pumpAndSettle();

        expect(find.text('Ad Soyad *'), findsOneWidget);
        expect(find.text('E-posta (Gmail) *'), findsOneWidget);
        expect(find.text('Şifre *'), findsOneWidget);

        // Ad Soyad boşken kayıt reddedilmeli
        await tester.enterText(
          find.byKey(const ValueKey<String>('auth_email_field')),
          'yeni@gmail.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('auth_password_field')),
          '123456',
        );
        final submitBtn = find.byKey(
          const ValueKey<String>('auth_email_submit_button'),
        );
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Lütfen adınızı ve soyadınızı girin (zorunlu).'),
          findsOneWidget,
        );
        expect(authController.isAwaitingEmailVerification, isFalse);

        // Ad Soyad girip kayıt ol -> doğrulama bekleme ekranı açılır
        await tester.enterText(
          find.byKey(const ValueKey<String>('auth_name_field')),
          'Mustafa Ayaz',
        );
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(authController.isAwaitingEmailVerification, isTrue);
        expect(authController.isAuthenticated, isFalse);
        expect(
          find.byKey(const ValueKey<String>('auth_verify_waiting_title')),
          findsOneWidget,
        );
        expect(backend.verificationSendCount, 1);

        // Kullanıcı e-postadaki linke tıklar ve uygulama öne döner (resumed)
        backend.markEmailVerified();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(
          find.byKey(const ValueKey<String>('auth_verified_success_title')),
          findsOneWidget,
        );
        expect(find.text('Doğrulandınız!'), findsOneWidget);

        // 900ms geçiş süresi bitince kullanıcı artık doğrulanmış + oturum açmış olur
        await tester.pump(const Duration(seconds: 1));
        expect(authController.isAuthenticated, isTrue);
        expect(authController.isAwaitingEmailVerification, isFalse);

        authController.dispose();
        localeController.dispose();
      },
    );
  });
}
