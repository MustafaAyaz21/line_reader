import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linereader/features/articles/controllers/articles_controller.dart';
import 'package:linereader/features/articles/data/articles_cache_repository.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/services/articles_remote_service.dart';
import 'package:linereader/features/articles/services/articles_sync_service.dart';

class _InMemoryArticlesCacheStore implements ArticlesCacheStore {
  List<Article> _cached = const <Article>[];
  ArticleSyncMetadata _meta = ArticleSyncMetadata.empty;

  @override
  Future<List<Article>> getCachedArticles() async => _cached;

  @override
  Future<ArticleSyncMetadata> getSyncMetadata() async => _meta;

  @override
  Future<void> replaceArticles(
    List<Article> articles, {
    ArticleSyncMetadata? metadata,
  }) async {
    _cached = List<Article>.unmodifiable(articles);
    if (metadata != null) {
      _meta = metadata;
    }
  }

  @override
  Future<void> updateSyncMetadata(ArticleSyncMetadata metadata) async {
    _meta = metadata;
  }

  @override
  Future<void> clearCache() async {
    _cached = const <Article>[];
    _meta = ArticleSyncMetadata.empty;
  }
}

void main() {
  test(
    'Article parses is_hidden and publish_at from JSON and preserves them through SQLite row',
    () {
      final hidden = Article.tryFromJson(<String, Object?>{
        'id': 'b1-hidden',
        'level': 'B1',
        'title': 'Hidden Draft',
        'content': 'Secret text.',
        'is_hidden': true,
      });
      expect(hidden, isNotNull);
      expect(hidden!.isHidden, isTrue);
      expect(hidden.isVisibleAt(DateTime.utc(2030, 1, 1)), isFalse);

      final fromDbHidden = Article.fromDbRow(hidden.toDbRow(cachedAtMillis: 1));
      expect(fromDbHidden.isHidden, isTrue);

      final scheduled = Article.tryFromJson(<String, Object?>{
        'id': 'b1-sched',
        'level': 'B1',
        'title': 'Noon Release',
        'content': 'Scheduled text.',
        'publish_at': '2026-11-24T09:00:00Z', // 12:00 UTC+3
      });
      expect(scheduled, isNotNull);
      expect(scheduled!.isHidden, isFalse);
      expect(scheduled.publishAt, DateTime.utc(2026, 11, 24, 9, 0));
      expect(scheduled.isVisibleAt(DateTime.utc(2026, 11, 24, 8, 59)), isFalse);
      expect(scheduled.isVisibleAt(DateTime.utc(2026, 11, 24, 9, 0)), isTrue);

      final fromDbScheduled =
          Article.fromDbRow(scheduled.toDbRow(cachedAtMillis: 1));
      expect(fromDbScheduled.publishAt, DateTime.utc(2026, 11, 24, 9, 0));
    },
  );

  test(
    'ArticlesController hides is_hidden and future publish_at using server HTTP Date, and auto-reveals into pending banner when scheduled time arrives (even on HTTP 304)',
    () async {
      var serverNowUtc = DateTime.utc(2026, 11, 24, 8, 30); // 11:30 TR
      // Kullanıcı telefon saatini bilerek 2 saat ileri almış olsun (13:30 TR)!
      var fakeDeviceNowUtc = DateTime.utc(2026, 11, 24, 10, 30);
      var callCount = 0;

      final payloadJson = jsonEncode(<String, Object?>{
        'version': 2,
        'articles': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'a1-live',
            'level': 'A1',
            'title': 'Always Live',
            'content': 'Hello world.',
          },
          <String, Object?>{
            'id': 'a1-hidden',
            'level': 'A1',
            'title': 'Hidden Article',
            'content': 'Should never appear.',
            'is_hidden': true,
          },
          <String, Object?>{
            'id': 'b1-noon-1',
            'level': 'B1',
            'title': 'Scheduled Article 1',
            'content': 'Drops at noon.',
            'publish_at': '2026-11-24T09:00:00Z',
          },
          <String, Object?>{
            'id': 'b1-noon-2',
            'level': 'B1',
            'title': 'Scheduled Article 2',
            'content': 'Also drops at noon.',
            'publish_at': '2026-11-24T09:00:00Z',
          },
        ],
      });

      final client = MockClient((http.Request req) async {
        callCount++;
        final httpDate = HttpDate.format(serverNowUtc);
        if (callCount == 1) {
          return http.Response.bytes(
            utf8.encode(payloadJson),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
              'etag': '"v2"',
              'date': httpDate,
            },
          );
        }
        // Sonraki kontrolde bilgisayar kapalı, dosya değişmemiş -> HTTP 304!
        return http.Response(
          '',
          304,
          headers: <String, String>{
            'etag': '"v2"',
            'date': httpDate,
          },
        );
      });

      final cache = _InMemoryArticlesCacheStore();
      final remote = ArticlesRemoteService(
        httpClient: client,
        remoteUrl: 'https://example.test/articles.json',
      );
      final controller = ArticlesController(
        ArticlesSyncService(cacheStore: cache, remoteService: remote),
        nowProvider: () => fakeDeviceNowUtc,
      );

      // 11:30 TR sunucu saatinde (telefon saati 13:30 olsa bile!) yalnızca
      // "Always Live" görünmeli; gizli ve 12:00 planlılar görünmemeli!
      await controller.refresh(silent: false, force: true);
      expect(controller.articles.map((a) => a.id).toList(), <String>['a1-live']);
      expect(controller.hasPendingNewArticles, isFalse);

      // Şimdi sunucu saati 12:01 TR olsun (bilgisayar kapalı, sunucu 304 döner).
      serverNowUtc = DateTime.utc(2026, 11, 24, 9, 1);
      fakeDeviceNowUtc = DateTime.utc(2026, 11, 24, 11, 1);

      await controller.refresh(silent: true, force: true);
      expect(controller.hasPendingNewArticles, isTrue);
      expect(controller.pendingNewArticlesCount, 2);
      // Gizli makale hala hariç olmalı!
      controller.applyPendingArticles();
      expect(
        controller.articles.map((a) => a.id).toList(),
        <String>['a1-live', 'b1-noon-1', 'b1-noon-2'],
      );

      controller.dispose();
    },
  );
}
