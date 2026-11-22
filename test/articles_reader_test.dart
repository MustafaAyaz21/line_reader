import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:linereader/features/articles/articles_screen.dart';
import 'package:linereader/features/articles/controllers/articles_controller.dart';
import 'package:linereader/features/articles/data/article_reader_repository.dart';
import 'package:linereader/features/articles/data/articles_cache_repository.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/models/article_level.dart';
import 'package:linereader/features/articles/models/article_reader_models.dart';
import 'package:linereader/features/articles/screens/article_reader_screen.dart';
import 'package:linereader/features/articles/services/articles_remote_service.dart';
import 'package:linereader/features/articles/services/articles_sync_service.dart';
import 'package:linereader/features/articles/utils/article_text_parser.dart';
import 'package:linereader/features/translation/models/word_meaning.dart';
import 'package:linereader/features/translation/services/word_translation_service.dart';
import 'package:linereader/features/words/models/saved_word.dart';

class _InMemoryArticlesCacheStore implements ArticlesCacheStore {
  _InMemoryArticlesCacheStore([this._articles = const <Article>[]]);

  List<Article> _articles;
  ArticleSyncMetadata _metadata = ArticleSyncMetadata.empty;

  @override
  Future<void> clearCache() async {
    _articles = const <Article>[];
    _metadata = ArticleSyncMetadata.empty;
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
    _articles = List<Article>.unmodifiable(articles);
    if (metadata != null) _metadata = metadata;
  }

  @override
  Future<void> updateSyncMetadata(ArticleSyncMetadata metadata) async {
    _metadata = metadata;
  }
}

class _InMemoryReaderStore implements ArticleReaderStore {
  ArticleReaderPreferences preferences = ArticleReaderPreferences.defaults;
  final Map<String, List<ArticleUnderline>> underlinesByArticle =
      <String, List<ArticleUnderline>>{};

  @override
  Future<ArticleReaderPreferences> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(ArticleReaderPreferences next) async {
    preferences = next;
  }

  @override
  Future<List<ArticleUnderline>> getUnderlinesForArticle(
    String articleId,
  ) async {
    return List<ArticleUnderline>.unmodifiable(
      underlinesByArticle[articleId] ?? const <ArticleUnderline>[],
    );
  }

  @override
  Future<void> saveUnderlinesForArticle(
    String articleId,
    List<ArticleUnderline> underlines,
  ) async {
    underlinesByArticle[articleId] =
        List<ArticleUnderline>.unmodifiable(underlines);
  }
}

class _FakeTranslationService implements WordTranslationService {
  String? lastWord;
  String? lastSentence;

  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    lastWord = word;
    lastSentence = contextSentence;
    return WordMeaning.fromEntries(
      word: word,
      contextSentence: contextSentence,
      entries: const <MeaningEntry>[
        MeaningEntry(
          translation: 'okumak',
          partOfSpeech: WordPartOfSpeech.verb,
          isContextual: true,
        ),
        MeaningEntry(
          translation: 'incelemek',
          partOfSpeech: WordPartOfSpeech.verb,
        ),
      ],
    );
  }

  @override
  void dispose() {}
}

void _tapFirstSpanMatching(WidgetTester tester, String targetText) {
  final richTexts = tester.widgetList<RichText>(find.byType(RichText));
  for (final richText in richTexts) {
    var tapped = false;
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == targetText && span.recognizer is TapGestureRecognizer) {
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
  group('ArticleTextParser & Article.formattedReadingTime', () {
    test('okuma süresini aralık formatında döndürür', () {
      final explicit = Article.tryFromJson(<String, Object?>{
        'id': 'a1',
        'title': 'Morning Routine',
        'description': 'Simple habits for every morning.',
        'level': 'A2',
        'reading_time': '5 - 8 dk',
      });
      expect(explicit, isNotNull);
      expect(explicit!.description, 'Simple habits for every morning.');
      expect(explicit.formattedReadingTime, '5 - 8 dk');
      expect(explicit.parsedLevel, ArticleLevel.a2);

      const numeric = Article(
        id: 'a2',
        title: 'City Walk',
        readingTimeMinutes: 5,
      );
      expect(numeric.formattedReadingTime, '4 - 6 dk');
    });

    test('paragraf bölme, bağlam cümlesi çıkarma ve bitişik alt çizgi birleştirme', () {
      const text = 'First sentence here. Second sentence talks about reading!\n\nNext paragraph.';
      final paragraphs = ArticleTextParser.splitParagraphs(text);
      expect(paragraphs, hasLength(2));
      expect(
        ArticleTextParser.extractContextSentence(paragraphs.first, 30),
        'Second sentence talks about reading!',
      );

      const paragraph = 'Daily reading builds intuition';
      var underlines = ArticleTextParser.addAndMergeUnderline(
        existing: const <ArticleUnderline>[],
        incoming: const ArticleUnderline(
          articleId: 'art-1',
          paragraphIndex: 0,
          startOffset: 0,
          endOffset: 5,
        ),
        paragraphText: paragraph,
      );
      underlines = ArticleTextParser.addAndMergeUnderline(
        existing: underlines,
        incoming: const ArticleUnderline(
          articleId: 'art-1',
          paragraphIndex: 0,
          startOffset: 6,
          endOffset: 13,
        ),
        paragraphText: paragraph,
      );

      // "Daily" ve "reading" arasındaki boşlukla tek kesintisiz çizgide birleşmeli.
      expect(underlines, hasLength(1));
      expect(underlines.first.startOffset, 0);
      expect(underlines.first.endOffset, 13);
    });
  });

  group('ArticlesScreen & LevelArticlesScreen', () {
    testWidgets('A1-C2 seviyelerini sırayla gösterir ve boş seviyede temiz boş durum sunar',
        (tester) async {
      final cacheStore = _InMemoryArticlesCacheStore(const <Article>[
        Article(
          id: 'a2-1',
          title: 'A Day in Kyoto',
          summary: 'Explore peaceful streets and tea houses in Kyoto.',
          level: 'A2',
          readingTimeLabel: '5 - 8 dk',
        ),
        Article(
          id: 'a2-2',
          title: 'Coffee Culture',
          summary: 'How morning coffee became a global ritual.',
          level: 'A2',
          readingTimeMinutes: 5,
        ),
      ]);

      final controller = ArticlesController(
        ArticlesSyncService(
          cacheStore: cacheStore,
          remoteService: ArticlesRemoteService(
            httpClient: MockClient((_) async => throw const SocketException('Offline')),
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

      // Sıralı A1..C2 kart doğrulaması
      final a1Top = tester.getTopLeft(find.byKey(const ValueKey<String>('article_level_card_A1'))).dy;
      final a2Top = tester.getTopLeft(find.byKey(const ValueKey<String>('article_level_card_A2'))).dy;
      final b1Top = tester.getTopLeft(find.byKey(const ValueKey<String>('article_level_card_B1'))).dy;
      final b2Top = tester.getTopLeft(find.byKey(const ValueKey<String>('article_level_card_B2'))).dy;
      expect(a1Top, lessThan(a2Top));
      expect(a2Top, lessThan(b1Top));
      expect(b1Top, lessThan(b2Top));

      expect(find.text('2 makale'), findsOneWidget);

      // Boş seviyeye (A1) gir
      await tester.tap(find.byKey(const ValueKey<String>('article_level_card_A1')));
      await tester.pumpAndSettle();
      expect(find.text('Bu seviyede henüz makale yok'), findsOneWidget);

      // Geri dönüp A2 seviyesine gir
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('article_level_card_A2')));
      await tester.pumpAndSettle();

      expect(find.text('A Day in Kyoto'), findsOneWidget);
      expect(find.text('Explore peaceful streets and tea houses in Kyoto.'), findsOneWidget);
      expect(find.text('5 - 8 dk'), findsOneWidget);
      expect(find.text('Coffee Culture'), findsOneWidget);
      expect(find.text('4 - 6 dk'), findsOneWidget);

      controller.dispose();
    });
  });

  group('ArticleReaderScreen', () {
    testWidgets(
      'arka plan tonu, font boyutu, altını çizme kalemi ve kelime anlamı akışını çalıştırır',
      (tester) async {
        final readerStore = _InMemoryReaderStore();
        final translationService = _FakeTranslationService();
        const sampleArticle = Article(
          id: 'article-kyoto',
          title: 'A Day in Kyoto',
          summary: 'A gentle walk through historic temples.',
          level: 'A2',
          author: 'Line Reader Editorial',
          readingTimeLabel: '5 - 8 dk',
          content: 'Reading books brings calm. Quiet gardens inspire deep focus.',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ArticleReaderScreen(
              article: sampleArticle,
              readerStore: readerStore,
              translationService: translationService,
              onAddWord: (_, __, ___, ____) async => SaveWordStatus.saved,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Yazar profil ikonu görünmeli ve başlık/açıklama font boyutu sabit kalmalı.
        expect(find.byKey(const ValueKey<String>('reader_author_icon')), findsOneWidget);
        expect(find.text('Line Reader Editorial'), findsOneWidget);

        final initialTitleSize = tester
            .widget<Text>(find.byKey(const ValueKey<String>('reader_article_title')))
            .style!
            .fontSize;
        final initialDescSize = tester
            .widget<Text>(find.byKey(const ValueKey<String>('reader_article_description')))
            .style!
            .fontSize;

        // 1) Görünüm ayarlarını aç -> Beyaz ton ve A+ seç -> yerel depoya kaydedilsin.
        await tester.tap(find.byKey(const ValueKey<String>('reader_appearance_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('reader_tone_white')));
        await tester.pumpAndSettle();
        expect(readerStore.preferences.tone, ArticleReaderTone.white);

        await tester.tap(find.byKey(const ValueKey<String>('reader_font_increase')));
        await tester.pumpAndSettle();
        expect(readerStore.preferences.fontSize, 19.0);

        // Ayar alt panelini kapat
        Navigator.of(tester.element(find.byKey(const ValueKey<String>('reader_tone_white')))).pop();
        await tester.pumpAndSettle();

        // Başlık ve açıklama yazı boyutu A+ sonrası değişmemeli.
        final afterTitleSize = tester
            .widget<Text>(find.byKey(const ValueKey<String>('reader_article_title')))
            .style!
            .fontSize;
        final afterDescSize = tester
            .widget<Text>(find.byKey(const ValueKey<String>('reader_article_description')))
            .style!
            .fontSize;
        expect(afterTitleSize, initialTitleSize);
        expect(afterDescSize, initialDescSize);

        // 2) Altını çizme kalemini aç -> "Reading" kelimesine dokun -> kaydedilsin.
        await tester.tap(find.byKey(const ValueKey<String>('reader_underline_pen_button')));
        await tester.pumpAndSettle();

        _tapFirstSpanMatching(tester, 'Reading');
        await tester.pumpAndSettle();

        final savedUnderlines =
            await readerStore.getUnderlinesForArticle('article-kyoto');
        expect(savedUnderlines, hasLength(1));
        expect(savedUnderlines.first.startOffset, 0);
        expect(savedUnderlines.first.endOffset, 7);

        // 3) Çizili alana tekrar dokun -> alt çizgi kaldırılsın.
        _tapFirstSpanMatching(tester, 'Reading');
        await tester.pumpAndSettle();

        final clearedUnderlines =
            await readerStore.getUnderlinesForArticle('article-kyoto');
        expect(clearedUnderlines, isEmpty);

        // 4) Kalemi kapat -> "Reading" kelimesine dokun -> WordPreviewSheet açılsın.
        await tester.tap(find.byKey(const ValueKey<String>('reader_underline_pen_button')));
        await tester.pumpAndSettle();

        _tapFirstSpanMatching(tester, 'Reading');
        await tester.pumpAndSettle();

        expect(translationService.lastWord, 'reading');
        expect(translationService.lastSentence, 'Reading books brings calm.');
        expect(find.textContaining('okumak'), findsWidgets);
      },
    );
  });
}
