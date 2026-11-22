import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linereader/core/database/app_database.dart';
import 'package:linereader/core/localization/app_locale.dart';
import 'package:linereader/core/settings/api_key_controller.dart';
import 'package:linereader/core/settings/settings_repository.dart';
import 'package:linereader/features/articles/controllers/article_reading_progress_controller.dart';
import 'package:linereader/features/articles/controllers/articles_controller.dart';
import 'package:linereader/features/articles/data/articles_cache_repository.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/services/articles_remote_service.dart';
import 'package:linereader/features/articles/services/articles_sync_service.dart';
import 'package:linereader/features/home/widgets/main_menu_screen.dart';

class _InMemorySettingsRepository extends SettingsRepository {
  _InMemorySettingsRepository() : super(AppDatabase.instance);

  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> saveString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async {
    _values.remove(key);
  }
}

class _InMemoryArticlesCacheStore implements ArticlesCacheStore {
  _InMemoryArticlesCacheStore(this._articles);

  List<Article> _articles;
  ArticleSyncMetadata _metadata = ArticleSyncMetadata.empty;

  @override
  Future<List<Article>> getCachedArticles() async => _articles;

  @override
  Future<ArticleSyncMetadata> getSyncMetadata() async => _metadata;

  @override
  Future<void> replaceArticles(
    List<Article> articles, {
    ArticleSyncMetadata? metadata,
  }) async {
    _articles = List<Article>.unmodifiable(articles);
    if (metadata != null) {
      _metadata = metadata;
    }
  }

  @override
  Future<void> updateSyncMetadata(ArticleSyncMetadata metadata) async {
    _metadata = metadata;
  }

  @override
  Future<void> clearCache() async {
    _articles = const <Article>[];
    _metadata = ArticleSyncMetadata.empty;
  }
}

class _NoopRemoteService extends ArticlesRemoteService {
  @override
  Future<ArticleFeedPayload> fetchArticles({
    String? etag,
    bool bypassCdnCache = false,
  }) async {
    return ArticleFeedPayload.notModified(etag: etag);
  }
}

Article _sampleArticle({
  required String id,
  required String title,
  String level = 'B1',
}) {
  return Article(
    id: id,
    title: title,
    summary: 'Sample description',
    level: level,
    readingTimeMinutes: 4,
    content: List<String>.generate(
      12,
      (index) => 'Paragraph ${index + 1}. Learning English through daily '
          'articles improves vocabulary and reading comprehension steadily.',
    ).join('\n\n'),
  );
}

void main() {
  test('ArticleReadingProgressController persists and reloads latest progress',
      () async {
    final settings = _InMemorySettingsRepository();
    final firstController = ArticleReadingProgressController(
      repository: settings,
    );
    final article = _sampleArticle(id: 'art-1', title: 'Morning Habits');

    await firstController.recordProgress(
      article: article,
      progress: 0.42,
      scrollOffset: 320,
      persist: true,
    );

    expect(firstController.lastProgress?.articleId, 'art-1');
    expect(firstController.lastProgress?.progressPercent, 42);

    final reloaded = ArticleReadingProgressController(repository: settings);
    await reloaded.load();
    expect(reloaded.lastProgress?.articleId, 'art-1');
    expect(reloaded.lastProgress?.progressPercent, 42);
    expect(reloaded.progressForArticle('art-1')?.scrollOffset, 320);
  });

  testWidgets(
      'MainMenuScreen shows Continue Reading card in Turkish and switches to English when locale changes',
      (WidgetTester tester) async {
    final settings = _InMemorySettingsRepository();
    final localeController = AppLocaleController(
      store: SqliteAppLanguageStore(settings),
    );
    final apiKeyController = ApiKeyController(settings);
    final progressController = ArticleReadingProgressController(
      repository: settings,
    );

    final article = _sampleArticle(
      id: 'art-habits',
      title: 'How Small Habits Change Your Day',
      level: 'B2',
    );
    final articlesController = ArticlesController(
      ArticlesSyncService(
        cacheStore: _InMemoryArticlesCacheStore(<Article>[article]),
        remoteService: _NoopRemoteService(),
      ),
    );
    await articlesController.loadCache();
    await progressController.recordProgress(
      article: article,
      progress: 0.64,
      scrollOffset: 410,
      persist: true,
    );

    await tester.pumpWidget(
      AppLocaleScope(
        controller: localeController,
        child: ListenableBuilder(
          listenable: localeController,
          builder: (context, _) {
            return MaterialApp(
              home: MainMenuScreen(
                onOpenBrowser: () {},
                apiKeyController: apiKeyController,
                localeController: localeController,
                articlesController: articlesController,
                readingProgressController: progressController,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('main_menu_continue_reading_card')),
      findsOneWidget,
    );
    expect(find.text('Kaldığın yerden devam et'), findsOneWidget);
    expect(find.text('How Small Habits Change Your Day'), findsOneWidget);
    expect(find.text('%64'), findsOneWidget);
    expect(find.text('%64 tamamlandı'), findsOneWidget);

    await localeController.setLanguage(AppLanguage.en);
    await tester.pumpAndSettle();

    expect(find.text('Continue where you left off'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('64% completed'), findsOneWidget);
    expect(find.text('Kaldığın yerden devam et'), findsNothing);

    articlesController.dispose();
    apiKeyController.dispose();
    localeController.dispose();
    progressController.dispose();
  });

  testWidgets(
      'MainMenuScreen hides Continue Reading card when article is no longer visible',
      (WidgetTester tester) async {
    final settings = _InMemorySettingsRepository();
    final localeController = AppLocaleController(
      store: SqliteAppLanguageStore(settings),
    );
    final apiKeyController = ApiKeyController(settings);
    final progressController = ArticleReadingProgressController(
      repository: settings,
    );

    final hiddenArticle = _sampleArticle(
      id: 'art-hidden',
      title: 'Hidden Draft',
      level: 'A2',
    );
    final articlesController = ArticlesController(
      ArticlesSyncService(
        cacheStore: _InMemoryArticlesCacheStore(const <Article>[]),
        remoteService: _NoopRemoteService(),
      ),
    );
    await articlesController.loadCache();
    await progressController.recordProgress(
      article: hiddenArticle,
      progress: 0.35,
      persist: true,
    );

    await tester.pumpWidget(
      AppLocaleScope(
        controller: localeController,
        child: MaterialApp(
          home: MainMenuScreen(
            onOpenBrowser: () {},
            apiKeyController: apiKeyController,
            localeController: localeController,
            articlesController: articlesController,
            readingProgressController: progressController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('main_menu_continue_reading_card')),
      findsNothing,
    );

    articlesController.dispose();
    apiKeyController.dispose();
    localeController.dispose();
    progressController.dispose();
  });
}
