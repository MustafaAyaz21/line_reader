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
import 'package:linereader/features/settings/screens/settings_screen.dart';

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
    final authController = AuthController();

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
      final authController = AuthController();

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

      // Ayarlar > Görünüm / Temalar alt sayfasını aç
      await tester.tap(
        find.byKey(const ValueKey<String>('settings_cat_appearance')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hareketsiz Temalar'), findsOneWidget);

      final pauseSwitch = find.byKey(
        const ValueKey<String>('settings_theme_pause_animation_switch'),
      );
      await tester.scrollUntilVisible(
        pauseSwitch,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Hareketli Temalar'), findsOneWidget);

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

      // Yetkisiz / misafir kullanıcıda Özel Temalar ve Sakura Bahçesi tamamen gizli olmalı
      expect(find.text('Özel Temalar'), findsNothing);
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
}
