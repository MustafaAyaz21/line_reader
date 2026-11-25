import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linereader/core/database/app_database.dart';
import 'package:linereader/core/localization/app_locale.dart';
import 'package:linereader/core/settings/api_key_controller.dart';
import 'package:linereader/core/settings/settings_repository.dart';
import 'package:linereader/core/theme/app_theme.dart';
import 'package:linereader/core/theme/app_theme_backdrop.dart';
import 'package:linereader/core/theme/app_theme_controller.dart';
import 'package:linereader/core/theme/app_theme_preset.dart';
import 'package:linereader/features/articles/data/article_reader_repository.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/models/article_reader_models.dart';
import 'package:linereader/features/articles/screens/article_reader_screen.dart';
import 'package:linereader/features/auth/controllers/auth_controller.dart';
import 'package:linereader/features/auth/data/auth_local_repository.dart';
import 'package:linereader/features/auth/models/auth_user.dart';
import 'package:linereader/features/auth/screens/auth_screen.dart';
import 'package:linereader/features/auth/services/auth_service.dart';
import 'package:linereader/features/auth/services/entitlement_service.dart';
import 'package:linereader/features/settings/screens/settings_screen.dart';

class _FakeThemeAuthBackend implements AuthBackend {
  _FakeThemeAuthBackend({this.user});

  final AppAuthUser? user;
  final StreamController<AppAuthUser?> _controller =
      StreamController<AppAuthUser?>.broadcast();

  @override
  bool get isConfigured => true;

  @override
  AppAuthUser? get currentUser => user;

  @override
  Stream<AppAuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async =>
      user != null ? 'fake-token' : null;

  @override
  Future<AuthActionResult> signInWithGoogle() async =>
      const AuthActionResult.cancelled();

  @override
  Future<AuthActionResult> signInWithEmail({
    required String email,
    required String password,
  }) async =>
      const AuthActionResult.cancelled();

  @override
  Future<AuthActionResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async =>
      const AuthActionResult.cancelled();

  @override
  Future<AuthActionResult> sendEmailVerification() async =>
      const AuthActionResult.cancelled();

  @override
  Future<AppAuthUser?> reloadCurrentUser() async => user;

  @override
  Future<AuthActionResult> sendPasswordResetEmail(String email) async =>
      const AuthActionResult.cancelled();

  @override
  Future<void> signOut() async {}
}

class _FakeThemeAuthLocalStore implements AuthLocalStore {
  _FakeThemeAuthLocalStore({
    this.isUnlimited = false,
    this.hasSpecialThemes = false,
    this.guestMode = false,
  });

  final bool isUnlimited;
  final bool hasSpecialThemes;
  bool guestMode;

  @override
  Future<bool> isGuestModeEnabled() async => guestMode;

  @override
  Future<void> setGuestModeEnabled(bool enabled) async {
    guestMode = enabled;
  }

  @override
  Future<({String dateKey, int usedCount})> loadGuestQuota() async =>
      (dateKey: '', usedCount: 0);

  @override
  Future<void> saveGuestQuota({
    required String dateKey,
    required int usedCount,
  }) async {}

  @override
  Future<({
    bool isUnlimited,
    String? codeUsed,
    String? role,
    bool hasSpecialThemes,
  })> loadCachedEntitlement() async => (
        isUnlimited: isUnlimited,
        codeUsed: null,
        role: isUnlimited ? 'premium' : null,
        hasSpecialThemes: hasSpecialThemes,
      );

  @override
  Future<void> saveCachedEntitlement({
    required bool isUnlimited,
    String? codeUsed,
    String? role,
    bool hasSpecialThemes = false,
  }) async {}
}

class _FakeThemeEntitlementClient extends EntitlementClient {
  _FakeThemeEntitlementClient({
    this.isUnlimited = false,
    this.hasSpecialThemes = false,
  });

  final bool isUnlimited;
  final bool hasSpecialThemes;

  @override
  Future<EntitlementStatus?> fetchEntitlement(String idToken) async =>
      EntitlementStatus(
        isUnlimited: isUnlimited,
        role: isUnlimited ? 'premium' : 'user',
        hasSpecialThemes: hasSpecialThemes,
      );

  @override
  Future<RedeemCodeResult> redeemCode({
    required String idToken,
    required String code,
  }) async =>
      const RedeemCodeResult(isSuccess: false, message: 'unused');

  @override
  void dispose() {}
}

Future<AuthController> _createTestAuthController({
  required bool authenticated,
  bool isPremium = false,
  bool hasSpecialThemes = false,
}) async {
  final controller = AuthController(
    backend: _FakeThemeAuthBackend(
      user: authenticated
          ? const AppAuthUser(
              uid: 'u-theme-1',
              email: 'reader@example.com',
              displayName: 'Reader',
              provider: AuthProviderType.email,
              emailVerified: true,
            )
          : null,
    ),
    localStore: _FakeThemeAuthLocalStore(
      isUnlimited: isPremium,
      hasSpecialThemes: hasSpecialThemes,
      guestMode: !authenticated,
    ),
    entitlementClient: _FakeThemeEntitlementClient(
      isUnlimited: isPremium,
      hasSpecialThemes: hasSpecialThemes,
    ),
  );
  await controller.initialize();
  return controller;
}

class _InMemorySettingsRepository extends SettingsRepository {
  _InMemorySettingsRepository() : super(AppDatabase.instance);

  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> saveString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async {
    values.remove(key);
  }
}

class _InMemoryReaderStore implements ArticleReaderStore {
  _InMemoryReaderStore(this.preferences);

  ArticleReaderPreferences preferences;

  @override
  Future<ArticleReaderPreferences> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(ArticleReaderPreferences next) async {
    preferences = next;
  }

  @override
  Future<List<ArticleUnderline>> getUnderlinesForArticle(
    String articleId,
  ) async =>
      const <ArticleUnderline>[];

  @override
  Future<void> saveUnderlinesForArticle(
    String articleId,
    List<ArticleUnderline> underlines,
  ) async {}
}

double _contrastRatio(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('All 4 gradient themes define lossless palettes with >= 4.5:1 WCAG AA contrast',
      () {
    for (final preset in <AppThemePreset>[
      AppThemePreset.pastelDawn,
      AppThemePreset.nightDepth,
      AppThemePreset.softMist,
      AppThemePreset.electricCoral,
    ]) {
      final theme = AppTheme.forPreset(preset);
      final cs = theme.colorScheme;
      final visuals = theme.extension<AppThemeVisuals>();

      expect(visuals, isNotNull, reason: '${preset.name} must provide visuals');
      expect(visuals!.hasBackdrop, isTrue);
      expect(
        cs.brightness,
        preset.isDarkPreset ? Brightness.dark : Brightness.light,
      );

      // Kart yüzeyi üzerinde ana metin okunabilirliği
      final blendedCard = Color.alphaBlend(cs.surfaceContainerLow, cs.surface);
      expect(
        _contrastRatio(cs.onSurface, blendedCard),
        greaterThanOrEqualTo(7.0),
        reason: '${preset.name} card text contrast must be crisp',
      );

      // Birincil buton kontrastı
      expect(
        _contrastRatio(cs.onPrimary, cs.primary),
        greaterThanOrEqualTo(4.5),
        reason: '${preset.name} primary button contrast must meet WCAG AA',
      );

      // Makale okuma kağıdı kontrastı
      final blendedReader =
          Color.alphaBlend(visuals.readerPaperColor, cs.surface);
      expect(
        _contrastRatio(visuals.readerTextColor, blendedReader),
        greaterThanOrEqualTo(7.0),
        reason: '${preset.name} article reader text contrast must be high',
      );
    }
  });

  test('AppThemeController persists preset and syncs article reader tone to theme',
      () async {
    final repo = _InMemorySettingsRepository();
    final controller = AppThemeController(repository: repo);

    await controller.setPreset(AppThemePreset.electricCoral);
    expect(controller.preset, AppThemePreset.electricCoral);
    expect(repo.values['app_theme_preset'], 'electric_coral');
    expect(repo.values['article_reader_tone'], 'theme');

    final reloaded = AppThemeController(repository: repo);
    await reloaded.load();
    expect(reloaded.preset, AppThemePreset.electricCoral);
  });

  testWidgets(
      'SettingsScreen displays all 5 themes in Turkish & English and applies selection live',
      (WidgetTester tester) async {
    AppThemeController.shared.resetForTesting();
    addTearDown(() => AppThemeController.shared.resetForTesting());

    final settingsRepo = _InMemorySettingsRepository();
    final localeController = AppLocaleController(
      store: SqliteAppLanguageStore(settingsRepo),
    );
    final apiKeyController = ApiKeyController(settingsRepo);
    final authController = await _createTestAuthController(authenticated: true);

    await tester.pumpWidget(
      AppLocaleScope(
        controller: localeController,
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            localeController,
            AppThemeController.shared,
          ]),
          builder: (context, _) {
            final preset = AppThemeController.shared.preset;
            return MaterialApp(
              theme: AppTheme.forPreset(preset),
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

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_cat_appearance')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_theme_cat_static')),
    );
    await tester.pumpAndSettle();

    final electricCoralTile = find.byKey(
      const ValueKey<String>('settings_theme_electric_coral'),
    );
    await tester.scrollUntilVisible(
      electricCoralTile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Pastel Şafak'), findsOneWidget);
    expect(find.text('Gece Derinliği'), findsOneWidget);
    expect(find.text('Hafif Sis'), findsOneWidget);
    expect(find.text('Elektrik Mercan'), findsOneWidget);

    await tester.tap(electricCoralTile);
    await tester.pumpAndSettle();

    expect(AppThemeController.shared.preset, AppThemePreset.electricCoral);
    expect(find.byType(AppThemeBackdrop), findsOneWidget);

    await localeController.setLanguage(AppLanguage.en);
    await tester.pumpAndSettle();

    expect(find.text('Pastel Dawn'), findsOneWidget);
    expect(find.text('Night Depth'), findsOneWidget);
    expect(find.text('Soft Mist'), findsOneWidget);
    expect(find.text('Electric Coral'), findsOneWidget);

    apiKeyController.dispose();
    localeController.dispose();
    authController.dispose();
  });

  testWidgets(
      'ArticleReaderScreen applies active gradient theme backdrop and frosted surface when tone is appTheme',
      (WidgetTester tester) async {
    const sampleArticle = Article(
      id: 'theme-article-1',
      title: 'Colors of the Sky',
      summary: 'A short reading passage.',
      level: 'B1',
      content: 'Evening light shifts softly from deep cobalt to warm coral.',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.forPreset(AppThemePreset.nightDepth),
        home: ArticleReaderScreen(
          article: sampleArticle,
          readerStore: _InMemoryReaderStore(
            const ArticleReaderPreferences(tone: ArticleReaderTone.appTheme),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppThemeBackdrop), findsOneWidget);
    expect(find.text('Colors of the Sky'), findsOneWidget);
  });

  testWidgets(
    'Default classic theme & article reader automatically follow system dark/light mode',
    (WidgetTester tester) async {
      expect(AppThemePreset.classic.themeMode, ThemeMode.system);
      expect(ArticleReaderPreferences.defaults.tone, ArticleReaderTone.appTheme);
      expect(ArticleReaderTone.fromStorageKey(null), ArticleReaderTone.appTheme);

      ArticleReaderPalette? darkPalette;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppThemePreset.classic.themeMode,
          home: Builder(
            builder: (context) {
              darkPalette =
                  ArticleReaderPreferences.defaults.tone.resolvePalette(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(darkPalette, isNotNull);
      expect(darkPalette!.brightness, Brightness.dark);

      ArticleReaderPalette? lightPalette;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppThemePreset.classic.themeMode,
          home: Builder(
            builder: (context) {
              lightPalette =
                  ArticleReaderPreferences.defaults.tone.resolvePalette(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(lightPalette, isNotNull);
      expect(lightPalette!.brightness, Brightness.light);
    },
  );

  test(
    'All 4 animated themes define lossless palettes with >= 4.5:1 button and >= 7:1 text contrast',
    () {
      expect(AppThemePreset.staticPresets.length, 5);
      expect(AppThemePreset.animatedPresets.length, 4);

      for (final preset in AppThemePreset.animatedPresets) {
        final theme = AppTheme.forPreset(preset);
        final cs = theme.colorScheme;
        final visuals = theme.extension<AppThemeVisuals>();

        expect(preset.isAnimatedTheme, isTrue);
        expect(visuals, isNotNull);
        expect(visuals!.hasBackdrop, isTrue);
        expect(
          cs.brightness,
          preset.isDarkPreset ? Brightness.dark : Brightness.light,
        );

        final blendedCard = Color.alphaBlend(cs.surfaceContainerLow, cs.surface);
        expect(
          _contrastRatio(cs.onSurface, blendedCard),
          greaterThanOrEqualTo(7.0),
          reason: '${preset.name} card text contrast must be crisp',
        );
        expect(
          _contrastRatio(cs.onPrimary, cs.primary),
          greaterThanOrEqualTo(4.5),
          reason: '${preset.name} primary button contrast must meet WCAG AA',
        );

        final blendedReader =
            Color.alphaBlend(visuals.readerPaperColor, cs.surface);
        expect(
          _contrastRatio(visuals.readerTextColor, blendedReader),
          greaterThanOrEqualTo(7.0),
          reason: '${preset.name} reader text contrast must be high',
        );

        if (!preset.isDarkPreset) {
          expect(cs.onSurface, const Color(0xFF292524));
          expect(cs.onSurfaceVariant, const Color(0xFF57534E));
        }
      }
    },
  );

  test('AppThemeController persists animated theme and animation pause toggle',
      () async {
    final repo = _InMemorySettingsRepository();
    final controller = AppThemeController(repository: repo);

    await controller.setPreset(AppThemePreset.amethystGalaxy);
    await controller.setAnimationPaused(true);
    expect(controller.preset, AppThemePreset.amethystGalaxy);
    expect(controller.isAnimationPaused, isTrue);
    expect(repo.values['app_theme_preset'], 'amethyst_galaxy');
    expect(repo.values['app_theme_animation_paused'], '1');

    final reloaded = AppThemeController(repository: repo);
    await reloaded.load();
    expect(reloaded.preset, AppThemePreset.amethystGalaxy);
    expect(reloaded.isAnimationPaused, isTrue);
  });

  testWidgets(
    'SettingsScreen splits Static & Animated Themes and toggles pause switch',
    (WidgetTester tester) async {
      AppThemeController.shared.resetForTesting();
      addTearDown(() => AppThemeController.shared.resetForTesting());

      final settingsRepo = _InMemorySettingsRepository();
      final localeController = AppLocaleController(
        store: SqliteAppLanguageStore(settingsRepo),
      );
      final apiKeyController = ApiKeyController(settingsRepo);
      final authController = await _createTestAuthController(
        authenticated: true,
        isPremium: true,
      );

      await tester.pumpWidget(
        AppLocaleScope(
          controller: localeController,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              localeController,
              AppThemeController.shared,
            ]),
            builder: (context, _) {
              final preset = AppThemeController.shared.preset;
              return MaterialApp(
                theme: AppTheme.forPreset(preset),
                home: SettingsScreen(
                  apiKeyController: apiKeyController,
                  authController: authController,
                  localeController: localeController,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ayarlar > Görünüm ve Temalar alt sayfasını aç
      await tester.tap(
        find.byKey(const ValueKey<String>('settings_cat_appearance')),
      );
      await tester.pumpAndSettle();

      // Hareketsiz Temalar ve Hareketli Temalar ayrı kategori kartları olarak görünür
      expect(find.text('Hareketsiz Temalar'), findsOneWidget);
      expect(find.text('Hareketli Temalar'), findsOneWidget);
      // Yetkisiz / misafir kullanıcıda Özel Temalar kategorisi tamamen gizli olmalı
      expect(find.text('Özel Temalar'), findsNothing);

      // Hareketli Temalar alt sayfasına gir
      await tester.tap(
        find.byKey(const ValueKey<String>('settings_theme_cat_animated')),
      );
      await tester.pumpAndSettle();

      final pauseSwitch = find.byKey(
        const ValueKey<String>('settings_theme_pause_animation_switch'),
      );
      await tester.scrollUntilVisible(
        pauseSwitch,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // 4 yeni hareketli tema başlık & kısa açıklamaları
      expect(find.text('Ametist Galaksi'), findsOneWidget);
      expect(find.text('Dönen mor galaksi ve pulsar'), findsOneWidget);
      expect(find.text('Okyanus Derinlikleri'), findsOneWidget);
      expect(find.text('Sakin derin deniz ve balıklar'), findsOneWidget);
      expect(find.text('Sıcak Latte Bokeh'), findsOneWidget);
      expect(find.text('Sıcak karamel ve yumuşak ışıklar'), findsOneWidget);
      expect(find.text('Adaçayı & Gün Işığı'), findsOneWidget);
      expect(find.text('Ferah adaçayı ve pastel ışıltılar'), findsOneWidget);

      // Hareketli tema seç -> canlı olarak uygulanır
      final oceanTile = find.byKey(
        const ValueKey<String>('settings_theme_ocean_depths'),
      );
      await tester.ensureVisible(oceanTile);
      await tester.tap(oceanTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(AppThemeController.shared.preset, AppThemePreset.oceanDepths);

      // Uygulama küçültüldüğünde yaşam döngüsü hatasız duraklatır
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Animasyonu Duraklat anahtarını aç
      await tester.scrollUntilVisible(
        pauseSwitch,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(pauseSwitch);
      await tester.pump();
      expect(AppThemeController.shared.isAnimationPaused, isTrue);

      // Yetkisiz kullanıcıda Sakura Bahçesi görünmez
      expect(find.text('Sakura Bahçesi'), findsNothing);

      apiKeyController.dispose();
      localeController.dispose();
      authController.dispose();
    },
  );

  test(
    'Sakura Garden special theme meets WCAG contrast and enforces fallback when access is revoked',
    () async {
      const preset = AppThemePreset.sakuraGarden;
      expect(preset.isSpecialTheme, isTrue);
      expect(preset.isAnimatedTheme, isTrue);
      expect(AppThemePreset.specialPresets, contains(preset));
      expect(AppThemePreset.staticPresets, isNot(contains(preset)));
      expect(AppThemePreset.animatedPresets, isNot(contains(preset)));

      final theme = AppTheme.forPreset(preset);
      final cs = theme.colorScheme;
      final visuals = theme.extension<AppThemeVisuals>()!;
      final blendedCard = Color.alphaBlend(cs.surfaceContainerLow, cs.surface);
      expect(_contrastRatio(cs.onSurface, blendedCard), greaterThanOrEqualTo(7.0));
      expect(_contrastRatio(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
      final blendedReader =
          Color.alphaBlend(visuals.readerPaperColor, cs.surface);
      expect(
        _contrastRatio(visuals.readerTextColor, blendedReader),
        greaterThanOrEqualTo(7.0),
      );

      // Yetki varken özel tema seçilebilir; yetki kaldırılınca Classic'e döner
      final repo = _InMemorySettingsRepository();
      final controller = AppThemeController(repository: repo);
      await controller.setPreset(AppThemePreset.sakuraGarden);
      await controller.setEcoAnimation(true);
      expect(controller.preset, AppThemePreset.sakuraGarden);
      expect(controller.isEcoAnimation, isTrue);

      controller.enforceSpecialThemeAccess(hasSpecialThemes: true);
      expect(controller.preset, AppThemePreset.sakuraGarden);

      controller.enforceSpecialThemeAccess(hasSpecialThemes: false);
      expect(controller.preset, AppThemePreset.classic);
    },
  );

  test(
    'AppThemeController.enforceThemeAccess restricts guests to Classic and animated themes to Premium',
    () async {
      final repo = _InMemorySettingsRepository();
      final controller = AppThemeController(repository: repo);

      // Misafir kullanıcı hiçbir özel/statik/hareketli temayı koruyamaz
      await controller.setPreset(AppThemePreset.electricCoral);
      controller.enforceThemeAccess(
        isAuthenticated: false,
        isPremium: false,
        hasSpecialThemes: false,
      );
      expect(controller.preset, AppThemePreset.classic);

      // Standart kayıtlı kullanıcı statik temayı koruyabilir
      await controller.setPreset(AppThemePreset.electricCoral);
      controller.enforceThemeAccess(
        isAuthenticated: true,
        isPremium: false,
        hasSpecialThemes: false,
      );
      expect(controller.preset, AppThemePreset.electricCoral);

      // Standart kullanıcıda hareketli tema otomatik Classic'e döner
      await controller.setPreset(AppThemePreset.oceanDepths);
      controller.enforceThemeAccess(
        isAuthenticated: true,
        isPremium: false,
        hasSpecialThemes: false,
      );
      expect(controller.preset, AppThemePreset.classic);

      // Premium kullanıcıda hareketli tema aktif kalır
      await controller.setPreset(AppThemePreset.oceanDepths);
      controller.enforceThemeAccess(
        isAuthenticated: true,
        isPremium: true,
        hasSpecialThemes: false,
      );
      expect(controller.preset, AppThemePreset.oceanDepths);
    },
  );

  testWidgets(
    'Guest users cannot select themes and Kayıt Ol button opens AuthScreen',
    (WidgetTester tester) async {
      AppThemeController.shared.resetForTesting();
      addTearDown(() => AppThemeController.shared.resetForTesting());

      final settingsRepo = _InMemorySettingsRepository();
      final localeController = AppLocaleController(
        store: SqliteAppLanguageStore(settingsRepo),
      );
      final apiKeyController = ApiKeyController(settingsRepo);
      final authController = await _createTestAuthController(
        authenticated: false,
      );

      await tester.pumpWidget(
        AppLocaleScope(
          controller: localeController,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: SettingsScreen(
              apiKeyController: apiKeyController,
              authController: authController,
              localeController: localeController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('settings_cat_appearance')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Kayıt olmayan kullanıcılar tema kullanamaz'),
        findsOneWidget,
      );
      expect(find.text('Üye olup temayı kullanabilirsiniz.'), findsOneWidget);
      expect(find.text("Premium'a özel"), findsOneWidget);

      // Hareketsiz temalara girip bir temaya basılsa bile aktif olmamalı
      await tester.tap(
        find.byKey(const ValueKey<String>('settings_theme_cat_static')),
      );
      await tester.pumpAndSettle();

      final electricCoralTile = find.byKey(
        const ValueKey<String>('settings_theme_electric_coral'),
      );
      await tester.scrollUntilVisible(
        electricCoralTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(electricCoralTile);
      await tester.pumpAndSettle();
      expect(AppThemeController.shared.preset, AppThemePreset.classic);

      // Kayıt Ol butonuna basınca AuthScreen açılmalı
      final signUpBtn = find.byKey(
        const ValueKey<String>('settings_theme_subpage_guest_signup_btn'),
      );
      await tester.scrollUntilVisible(
        signUpBtn,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(signUpBtn);
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);

      apiKeyController.dispose();
      localeController.dispose();
      authController.dispose();
    },
  );

  testWidgets(
    'Standard authenticated users see Premium-only lock on Animated Themes',
    (WidgetTester tester) async {
      AppThemeController.shared.resetForTesting();
      addTearDown(() => AppThemeController.shared.resetForTesting());

      final settingsRepo = _InMemorySettingsRepository();
      final localeController = AppLocaleController(
        store: SqliteAppLanguageStore(settingsRepo),
      );
      final apiKeyController = ApiKeyController(settingsRepo);
      final authController = await _createTestAuthController(
        authenticated: true,
        isPremium: false,
      );

      await tester.pumpWidget(
        AppLocaleScope(
          controller: localeController,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: SettingsScreen(
              apiKeyController: apiKeyController,
              authController: authController,
              localeController: localeController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('settings_cat_appearance')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('settings_theme_guest_banner')),
        findsNothing,
      );
      expect(find.text("Premium'a özel"), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('settings_theme_cat_animated')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('settings_theme_animated_premium_banner'),
        ),
        findsOneWidget,
      );
      expect(find.text("Premium'a özel"), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('settings_theme_pause_animation_switch')),
        findsNothing,
      );

      final oceanTile = find.byKey(
        const ValueKey<String>('settings_theme_ocean_depths'),
      );
      await tester.tap(oceanTile);
      await tester.pumpAndSettle();
      expect(AppThemeController.shared.preset, AppThemePreset.classic);

      apiKeyController.dispose();
      localeController.dispose();
      authController.dispose();
    },
  );
}
