import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linereader/features/articles/articles_screen.dart';
import 'package:linereader/features/articles/controllers/articles_controller.dart';
import 'package:linereader/features/articles/data/articles_cache_repository.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/services/articles_remote_service.dart';
import 'package:linereader/features/articles/services/articles_sync_service.dart';

class _InMemoryArticlesCacheStore implements ArticlesCacheStore {
  List<Article> _articles = const <Article>[];
  ArticleSyncMetadata _metadata = ArticleSyncMetadata.empty;
  int replaceCalls = 0;

  void seed(List<Article> articles, {ArticleSyncMetadata? metadata}) {
    _articles = List<Article>.unmodifiable(articles);
    if (metadata != null) {
      _metadata = metadata;
    }
  }

  @override
  Future<List<Article>> getCachedArticles() async => _articles;

  @override
  Future<ArticleSyncMetadata> getSyncMetadata() async => _metadata;

  @override
  Future<void> replaceArticles(
    List<Article> articles, {
    ArticleSyncMetadata? metadata,
  }) async {
    replaceCalls++;
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

void main() {
  group('ArticlesRemoteService & ArticlesSyncService', () {
    test('uzak JSON nesnesini çekip önbelleğe kaydeder', () async {
      final cacheStore = _InMemoryArticlesCacheStore();
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), contains('example.com/articles.json'));
        return http.Response(
          jsonEncode(<String, Object?>{
            'version': 2,
            'updated_at': '2026-11-22T10:00:00Z',
            'articles': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'art-1',
                'title': 'Daily Reading Habits',
                'summary': 'How 15 minutes a day improves vocabulary.',
                'content': 'Reading daily builds intuition.',
                'category': 'Learning',
                'level': 'B1',
                'reading_time_minutes': 4,
                'tags': <String>['reading', 'habits'],
              },
              <String, Object?>{
                'id': 'art-1',
                'title': 'Duplicate Should Be Skipped',
              },
              <String, Object?>{
                'id': 'invalid-no-title',
              },
            ],
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'etag': '"etag-v2"',
          },
        );
      });

      final remote = ArticlesRemoteService(
        httpClient: mockClient,
        remoteUrl: 'https://example.com/articles.json',
      );
      final syncService = ArticlesSyncService(
        cacheStore: cacheStore,
        remoteService: remote,
      );

      final result = await syncService.syncArticles();
      expect(result.status, ArticleSyncStatus.updated);
      expect(result.articles, hasLength(1));
      expect(result.articles.first.id, 'art-1');
      expect(result.articles.first.title, 'Daily Reading Habits');
      expect(result.articles.first.level, 'B1');
      expect(result.articles.first.readingTimeMinutes, 4);
      expect(result.metadata.etag, '"etag-v2"');
      expect(result.metadata.remoteVersion, '2');

      final cached = await cacheStore.getCachedArticles();
      expect(cached, hasLength(1));
      expect(cached.first.title, 'Daily Reading Habits');

      syncService.dispose();
    });

    test('ağ hatasında veya HTTP 500 durumunda mevcut önbelleği korur', () async {
      final cacheStore = _InMemoryArticlesCacheStore()
        ..seed(
          const <Article>[
            Article(
              id: 'cached-1',
              title: 'Offline Cached Article',
              summary: 'Still readable offline.',
            ),
          ],
          metadata: const ArticleSyncMetadata(etag: '"old-etag"'),
        );

      final offlineClient = MockClient((_) async {
        throw const SocketException('No internet');
      });

      final syncService = ArticlesSyncService(
        cacheStore: cacheStore,
        remoteService: ArticlesRemoteService(
          httpClient: offlineClient,
          remoteUrl: 'https://example.com/articles.json',
        ),
      );

      final result = await syncService.syncArticles();
      expect(result.status, ArticleSyncStatus.offlineFallback);
      expect(result.isOfflineFallback, isTrue);
      expect(result.articles, hasLength(1));
      expect(result.articles.first.id, 'cached-1');
      expect(cacheStore.replaceCalls, 0);

      final stillCached = await cacheStore.getCachedArticles();
      expect(stillCached, hasLength(1));
      expect(stillCached.first.title, 'Offline Cached Article');

      syncService.dispose();
    });

    test('bozuk JSON yanıtında mevcut önbelleği bozmaz', () async {
      final cacheStore = _InMemoryArticlesCacheStore()
        ..seed(const <Article>[
          Article(id: 'safe-1', title: 'Preserved Article'),
        ]);

      final malformedClient = MockClient((_) async {
        return http.Response('<html>502 Bad Gateway</html>', 200);
      });

      final syncService = ArticlesSyncService(
        cacheStore: cacheStore,
        remoteService: ArticlesRemoteService(
          httpClient: malformedClient,
          remoteUrl: 'https://example.com/articles.json',
        ),
      );

      final result = await syncService.syncArticles();
      expect(result.status, ArticleSyncStatus.offlineFallback);
      expect(result.articles, hasLength(1));
      expect(result.articles.first.id, 'safe-1');
      expect(cacheStore.replaceCalls, 0);

      syncService.dispose();
    });

    test('HTTP 304 Not Modified yanıtında önbelleği silmeden korur', () async {
      String? sentIfNoneMatch;
      final cacheStore = _InMemoryArticlesCacheStore()
        ..seed(
          const <Article>[
            Article(id: 'art-304', title: 'Unchanged Article'),
          ],
          metadata: const ArticleSyncMetadata(etag: '"same-etag"'),
        );

      final notModifiedClient = MockClient((request) async {
        sentIfNoneMatch = request.headers['If-None-Match'];
        return http.Response('', 304, headers: <String, String>{
          'etag': '"same-etag"',
        });
      });

      final syncService = ArticlesSyncService(
        cacheStore: cacheStore,
        remoteService: ArticlesRemoteService(
          httpClient: notModifiedClient,
          remoteUrl: 'https://example.com/articles.json',
        ),
      );

      final result = await syncService.syncArticles();
      expect(sentIfNoneMatch, '"same-etag"');
      expect(result.status, ArticleSyncStatus.notModified);
      expect(result.articles, hasLength(1));
      expect(result.articles.first.id, 'art-304');
      expect(result.metadata.lastSyncedAt, isNotNull);
      expect(cacheStore.replaceCalls, 0);

      syncService.dispose();
    });

    test('eşzamanlı yenileme isteklerini tek istekte birleştirir', () async {
      final cacheStore = _InMemoryArticlesCacheStore();
      var requestCount = 0;
      final completer = Completer<http.Response>();

      final slowClient = MockClient((_) {
        requestCount++;
        return completer.future;
      });

      final controller = ArticlesController(
        ArticlesSyncService(
          cacheStore: cacheStore,
          remoteService: ArticlesRemoteService(
            httpClient: slowClient,
            remoteUrl: 'https://example.com/articles.json',
          ),
        ),
      );

      final futureA = controller.refresh(silent: true, force: true);
      final futureB = controller.refresh(silent: true, force: true);

      completer.complete(
        http.Response(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{'id': 'a1', 'title': 'Array Root Article'},
          ]),
          200,
        ),
      );

      final results = await Future.wait<ArticleSyncResult>(<Future<ArticleSyncResult>>[
        futureA,
        futureB,
      ]);

      expect(requestCount, 1);
      expect(results[0].articles.first.title, 'Array Root Article');
      expect(results[1].articles.first.title, 'Array Root Article');
      expect(controller.articles, hasLength(1));

      controller.dispose();
    });
  });

  group('ArticlesScreen Widget', () {
    testWidgets('boş listede Yakında görünümünü korur ve çevrimdışı bozulmaz',
        (tester) async {
      final cacheStore = _InMemoryArticlesCacheStore();
      final offlineClient = MockClient((_) async {
        throw const SocketException('Offline');
      });

      final controller = ArticlesController(
        ArticlesSyncService(
          cacheStore: cacheStore,
          remoteService: ArticlesRemoteService(
            httpClient: offlineClient,
            remoteUrl: 'https://example.com/articles.json',
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ArticlesScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Makaleler'), findsOneWidget);
      expect(find.text('Yakında...'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      controller.dispose();
    });

    testWidgets('önbellekte makale varsa çevrimdışı durumda da göstermeye devam eder',
        (tester) async {
      final cacheStore = _InMemoryArticlesCacheStore()
        ..seed(const <Article>[
          Article(
            id: 'cached-ui-1',
            title: 'Exploring London',
            summary: 'A short reading passage for B1 learners.',
            level: 'B1',
            category: 'Travel',
            readingTimeMinutes: 3,
          ),
        ]);

      final offlineClient = MockClient((_) async {
        throw const SocketException('Offline');
      });

      final controller = ArticlesController(
        ArticlesSyncService(
          cacheStore: cacheStore,
          remoteService: ArticlesRemoteService(
            httpClient: offlineClient,
            remoteUrl: 'https://example.com/articles.json',
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ArticlesScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Exploring London'), findsOneWidget);
      expect(find.text('B1'), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);

      controller.dispose();
    });
  });
}
