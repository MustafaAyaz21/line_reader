import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linereader/features/articles/data/article_reader_repository.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/models/article_reader_models.dart';
import 'package:linereader/features/articles/screens/article_reader_screen.dart';
import 'package:linereader/features/articles/services/article_word_translation_service.dart';
import 'package:linereader/features/translation/models/word_meaning.dart';
import 'package:linereader/features/translation/services/browser_ai_translation_service.dart';
import 'package:linereader/features/translation/services/local_dictionary_service.dart';
import 'package:linereader/features/translation/services/word_translation_service.dart';
import 'package:linereader/features/translation/utils/english_morphology_resolver.dart';
import 'package:linereader/features/words/models/saved_word.dart';
import 'package:linereader/features/words/services/word_dictionary_search_service.dart';

class _StubRemoteTranslationService implements WordTranslationService {
  int callCount = 0;
  bool shouldFailOffline = false;

  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    callCount++;
    if (shouldFailOffline) {
      throw const TranslationException(
        type: TranslationErrorType.network,
        message: 'İnternet bağlantısı yok.',
      );
    }
    return WordMeaning.fromEntries(
      word: word,
      contextSentence: contextSentence,
      entries: const <MeaningEntry>[
        MeaningEntry(
          translation: 'uzak anlam',
          isContextual: true,
        ),
      ],
    );
  }

  @override
  void dispose() {}
}

class _InMemoryReaderStore implements ArticleReaderStore {
  @override
  Future<List<ArticleUnderline>> getUnderlinesForArticle(String articleId) async =>
      const <ArticleUnderline>[];

  @override
  Future<ArticleReaderPreferences> loadPreferences() async =>
      ArticleReaderPreferences.defaults;

  @override
  Future<void> savePreferences(ArticleReaderPreferences preferences) async {}

  @override
  Future<void> saveUnderlinesForArticle(
    String articleId,
    List<ArticleUnderline> underlines,
  ) async {}
}

void _tapFirstSpanMatching(WidgetTester tester, String targetText) {
  final richTexts = tester.widgetList<RichText>(find.byType(RichText));
  for (final richText in richTexts) {
    var tapped = false;
    richText.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text == targetText &&
          span.recognizer is TapGestureRecognizer) {
        (span.recognizer! as TapGestureRecognizer).onTap?.call();
        tapped = true;
        return false;
      }
      return true;
    });
    if (tapped) return;
  }
  fail('"$targetText" metnine sahip tıklanabilir TextSpan bulunamadı.');
}

void main() {
  group('EnglishMorphologyResolver', () {
    test('ekleri ve düzensiz biçimleri kök adaylarına indirger', () {
      expect(EnglishMorphologyResolver.resolveCandidates('rules'), contains('rule'));
      expect(EnglishMorphologyResolver.resolveCandidates('watches'), contains('watch'));
      expect(EnglishMorphologyResolver.resolveCandidates('stories'), contains('story'));
      expect(EnglishMorphologyResolver.resolveCandidates('studied'), contains('study'));
      expect(EnglishMorphologyResolver.resolveCandidates('stopped'), contains('stop'));
      expect(EnglishMorphologyResolver.resolveCandidates('making'), contains('make'));
      expect(EnglishMorphologyResolver.resolveCandidates('running'), contains('run'));
      expect(EnglishMorphologyResolver.resolveCandidates('closely'), contains('close'));
      expect(EnglishMorphologyResolver.resolveCandidates('easily'), contains('easy'));
      expect(EnglishMorphologyResolver.resolveCandidates('faster'), contains('fast'));
      expect(EnglishMorphologyResolver.resolveCandidates('biggest'), contains('big'));
      expect(EnglishMorphologyResolver.resolveCandidates('decision'), contains('decide'));
      expect(EnglishMorphologyResolver.resolveCandidates('exploration'), contains('explore'));
      expect(EnglishMorphologyResolver.resolveCandidates('protection'), contains('protect'));
      expect(EnglishMorphologyResolver.resolveCandidates('went'), contains('go'));
      expect(EnglishMorphologyResolver.resolveCandidates('written'), contains('write'));
      expect(EnglishMorphologyResolver.resolveCandidates('children'), contains('child'));
      expect(EnglishMorphologyResolver.resolveCandidates('better'), contains('good'));
    });
  });

  group('Article.wordMeanings & ArticleWordTranslationService', () {
    test('word_meanings JSON ve SQLite raw_json dönüşümünde korunur ve kök üzerinden eşleşir',
        () {
      final parsed = Article.tryFromJson(<String, Object?>{
        'id': 'art-1',
        'level': 'B1',
        'title': 'Strange Rules',
        'content': 'People were making rules.',
        'word_meanings': <String, Object?>{
          'Make': 'bu cümlede karar vermek anlamında',
          'rule': 'toplumsal kural',
        },
      });
      expect(parsed, isNotNull);
      expect(parsed!.wordMeanings['make'], 'bu cümlede karar vermek anlamında');

      // SQLite satırına yazıp geri okuduğumuzda word_meanings kaybolmamalı.
      final dbRow = parsed.toDbRow(cachedAtMillis: 123456);
      final restored = Article.fromDbRow(dbRow);
      expect(restored.findWordMeaning('making')?.meaning,
          'bu cümlede karar vermek anlamında');
      expect(restored.findWordMeaning('rules')?.meaning, 'toplumsal kural');
    });

    test('makale içi word_meanings varsa uzak servise gitmeden anında anlam döner',
        () async {
      final remote = _StubRemoteTranslationService();
      final localDict = LocalDictionaryService(
        sources: const <LocalDictionarySource>[BuiltInCoreDictionarySource()],
      );
      const article = Article(
        id: 'a1',
        title: 'Rules',
        wordMeanings: <String, String>{
          'make': 'bu cümlede karar vermek anlamında',
        },
      );

      final service = ArticleWordTranslationService(
        article: article,
        fallbackService: remote,
        localDictionary: localDict,
      );

      final result = await service.lookup(
        word: 'making',
        contextSentence: 'They are making a choice.',
      );

      expect(remote.callCount, 0);
      expect(result.orderedEntries.first.translation,
          'bu cümlede karar vermek anlamında');
      expect(result.orderedEntries.first.isContextual, isTrue);
      // Yerel çekirdek sözlükten ek anlamlarla zenginleştirilmiş olmalı.
      expect(result.orderedEntries.length, greaterThan(1));
    });

    test('çevrimdışı durumda yerel sözlük + kök çözümleyici devreye girer', () async {
      final remote = _StubRemoteTranslationService()..shouldFailOffline = true;
      final localDict = LocalDictionaryService(
        sources: const <LocalDictionarySource>[BuiltInCoreDictionarySource()],
      );
      const article = Article(id: 'a2', title: 'No Custom Meanings');

      final service = ArticleWordTranslationService(
        article: article,
        fallbackService: remote,
        localDictionary: localDict,
      );

      final result = await service.lookup(word: 'decisions');
      expect(remote.callCount, 1);
      expect(result.translation, contains('karar vermek'));
    });

    test('ExternalJsonDictionarySource harici sözlük dosyasını modüler olarak okur',
        () async {
      final externalSource = ExternalJsonDictionarySource(
        sourceId: 'custom_json_dict',
        loadRawJson: () async => jsonEncode(<String, Object?>{
          'ephemeral': <String>['kısa ömürlü', 'geçici'],
        }),
      );
      final localDict = LocalDictionaryService(
        sources: <LocalDictionarySource>[externalSource],
      );

      final lookup = await localDict.lookup('ephemeral');
      expect(lookup, isNotNull);
      expect(lookup!.sourceId, 'custom_json_dict');
      expect(lookup.meaning.orderedEntries.first.translation, 'kısa ömürlü');
    });
  });

  group('WordDictionarySearchService & ArticleReaderScreen', () {
    test('kelime ekleme araması çevrimdışıyken kök çözümleyip yerel sözlükten sonuç döner',
        () async {
      final offlineClient = MockClient((_) async {
        throw const SocketException('Offline');
      });
      final localDict = LocalDictionaryService(
        sources: const <LocalDictionarySource>[BuiltInCoreDictionarySource()],
      );

      final searchService = WordDictionarySearchService(
        httpClient: offlineClient,
        localDictionary: localDict,
      );

      final detail = await searchService.searchWord('studied');
      expect(detail.meanings, isNotEmpty);
      expect(
        detail.meanings.map((m) => m.translation),
        contains('çalışmak'),
      );

      searchService.dispose();
    });

    testWidgets('makale okuma ekranında dokunulan çekimli kelime word_meanings ile anında açılır',
        (tester) async {
      final remote = _StubRemoteTranslationService();
      const article = Article(
        id: 'art-live',
        title: 'Rules in Context',
        level: 'B1',
        content: 'People are making thoughtful choices every day.',
        wordMeanings: <String, String>{
          'make': 'bu cümlede karar vermek anlamında',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ArticleReaderScreen(
            article: article,
            readerStore: _InMemoryReaderStore(),
            translationService: remote,
            onAddWord: (_, __, ___, ____) async => SaveWordStatus.saved,
          ),
        ),
      );
      await tester.pumpAndSettle();

      _tapFirstSpanMatching(tester, 'making');
      await tester.pumpAndSettle();

      expect(remote.callCount, 0);
      expect(
        find.textContaining('bu cümlede karar vermek anlamında'),
        findsWidgets,
      );
    });

    test('BrowserAiTranslationService yalnızca kayıtlı kullanıcıda Bearer token gönderir, misafiri reddeder ve 429 kota hatasını raporlar',
        () async {
      Map<String, Object?>? sentBody;
      String? sentAuth;
      var httpCalls = 0;

      final client = MockClient((request) async {
        httpCalls++;
        sentAuth = request.headers['Authorization'];
        sentBody = Map<String, Object?>.from(
          jsonDecode(request.body) as Map,
        );
        if (sentBody?['word'] == 'quota') {
          return http.Response('{"error":"quota_exceeded"}', 429);
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'meanings': <Map<String, Object?>>[
              <String, Object?>{
                'translation': 'karar vermek',
                'partOfSpeech': 'verb',
                'isContextual': true,
              },
              <String, Object?>{
                'translation': 'yapmak',
                'partOfSpeech': 'verb',
              },
            ],
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      // 1) Misafir kullanıcıda AI Worker hiç çağrılmamalı.
      final guestAiService = BrowserAiTranslationService(
        proxyEndpoint: 'https://linereader-ai.workers.dev',
        isUserAuthenticatedProvider: () => false,
        authTokenProvider: () async => null,
        httpClient: client,
      );
      await expectLater(
        guestAiService.lookup(word: 'make', contextSentence: 'Make a choice.'),
        throwsA(
          isA<TranslationException>().having(
            (e) => e.type,
            'type',
            TranslationErrorType.unauthorized,
          ),
        ),
      );
      expect(httpCalls, 0);
      guestAiService.dispose();

      // 2) Kayıtlı kullanıcıda Firebase ID Token + bağlam cümlesi gönderilmeli.
      final authedAiService = BrowserAiTranslationService(
        proxyEndpoint: 'https://linereader-ai.workers.dev',
        isUserAuthenticatedProvider: () => true,
        authTokenProvider: () async => 'firebase-id-token-123',
        httpClient: client,
      );

      final result = await authedAiService.lookup(
        word: 'make',
        contextSentence: 'We need to make a decision today.',
      );

      expect(httpCalls, 1);
      expect(sentAuth, 'Bearer firebase-id-token-123');
      expect(sentBody?['word'], 'make');
      expect(sentBody?['context_sentence'], 'We need to make a decision today.');
      expect(result.orderedEntries.first.translation, 'karar vermek');
      expect(result.orderedEntries.first.isContextual, isTrue);

      // 3) 429 kota aşımında rateLimited hatası fırlatıp ücretsiz sözlüğe düşüşü tetiklemeli.
      await expectLater(
        authedAiService.lookup(word: 'quota'),
        throwsA(
          isA<TranslationException>().having(
            (e) => e.type,
            'type',
            TranslationErrorType.rateLimited,
          ),
        ),
      );

      authedAiService.dispose();
    });
  });
}
