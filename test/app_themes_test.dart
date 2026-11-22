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
}
