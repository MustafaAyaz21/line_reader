import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linereader/features/articles/articles_screen.dart';
import 'package:linereader/features/articles/controllers/articles_controller.dart';
import 'package:linereader/features/articles/data/article_reader_repository.dart';
import 'package:linereader/features/articles/data/articles_cache_repository.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/models/article_level.dart';
import 'package:linereader/features/articles/models/article_reader_models.dart';
import 'package:linereader/features/articles/screens/article_reader_screen.dart';
import 'package:linereader/features/articles/services/article_passage_translation_service.dart';
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

      // Çok kelimelik çizgiden tek kelime çıkarılınca kalan kelimeler korunmalı.
      underlines = ArticleTextParser.addAndMergeUnderline(
        existing: underlines,
        incoming: const ArticleUnderline(
          articleId: 'art-1',
          paragraphIndex: 0,
          startOffset: 14,
          endOffset: 20,
        ),
        paragraphText: paragraph,
      );
      expect(underlines, hasLength(1));
      expect(underlines.first.endOffset, 20); // "Daily reading builds"

      final afterRemoveMiddle = ArticleTextParser.removeWordRangeFromUnderlines(
        existing: underlines,
        paragraphIndex: 0,
        wordStart: 6,
        wordEnd: 13, // "reading"
        paragraphText: paragraph,
      );
      expect(afterRemoveMiddle, hasLength(2));
      expect(
        paragraph.substring(
          afterRemoveMiddle[0].startOffset,
          afterRemoveMiddle[0].endOffset,
        ),
        'Daily',
      );
      expect(
        paragraph.substring(
          afterRemoveMiddle[1].startOffset,
          afterRemoveMiddle[1].endOffset,
        ),
        'builds',
      );
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

    testWidgets(
      'sürükleyerek alt çizme, tek tıkla tek kelime kaldırma, fosforlu/üstü çizili/renk değişimi ve sistem Kopyala/Tümünü Seç engeli çalışır',
      (tester) async {
        final readerStore = _InMemoryReaderStore();
        final translationService = _FakeTranslationService();
        const paragraphText =
            'Reading books brings calm. Quiet gardens inspire deep focus.';
        const sampleArticle = Article(
          id: 'article-markup-test',
          title: 'Markup & Gesture Test',
          summary: 'Testing drag underline, styles, and no system copy menu.',
          level: 'B1',
          author: 'Line Reader',
          content: paragraphText,
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

        // Sistem Kopyala / Tümünü Seç sağlayan SelectionArea / SelectableText olmamalı.
        expect(find.byType(SelectionArea), findsNothing);
        expect(find.byType(SelectableText), findsNothing);

        final paragraphGestureFinder =
            find.byKey(const ValueKey<String>('reader_paragraph_gesture_0'));
        expect(paragraphGestureFinder, findsOneWidget);

        // RenderParagraph üzerinden "Reading" ve "brings" kelimelerinin gerçek ekran koordinatlarını bul.
        final richTextFinder = find.descendant(
          of: paragraphGestureFinder,
          matching: find.byType(RichText),
        );
        final renderParagraph =
            tester.renderObject<RenderParagraph>(richTextFinder);

        Offset centerOfChar(int offset) {
          final box = renderParagraph
              .getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
              )
              .first;
          return renderParagraph.localToGlobal(box.toRect().center);
        }

        final readingCenter = centerOfChar(2); // "Reading"

        // 1) Altını Çiz modu KAPALI iken "Reading" üzerine basılı tut:
        //    tüm cümle seçilmemeli, sistem Kopyala/Tümünü Seç çıkmamalı,
        //    yalnızca "Reading" seçilip "Anlamına Bak" çıkmalı.
        final normalGesture = await tester.startGesture(readingCenter);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await normalGesture.up();
        await tester.pumpAndSettle();

        expect(find.text('Kopyala'), findsNothing);
        expect(find.text('Copy'), findsNothing);
        expect(find.text('Tümünü Seç'), findsNothing);
        expect(find.text('Select All'), findsNothing);
        expect(find.text('Anlamına Bak'), findsOneWidget);

        await tester.tap(find.text('Anlamına Bak'));
        await tester.pumpAndSettle();
        expect(translationService.lastWord, 'reading');

        // WordPreviewSheet'i kapat
        Navigator.of(tester.element(find.text('Kelimelerime Ekle'))).pop();
        await tester.pumpAndSettle();

        // 2) Altını Çiz modunu AÇ (AppBar alt şeridi açılınca paragraf konumu kayar;
        //    güncel ekran koordinatlarını yeniden okuyup "Reading" -> "brings" boyunca sürükle).
        await tester.tap(
          find.byKey(const ValueKey<String>('reader_underline_pen_button')),
        );
        await tester.pumpAndSettle();

        final dragStartCenter = centerOfChar(2); // "Reading"
        final dragEndCenter = centerOfChar(16); // "brings"

        final dragGesture = await tester.startGesture(dragStartCenter);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await dragGesture.moveTo(dragEndCenter);
        await tester.pump();
        await dragGesture.up();
        await tester.pumpAndSettle();

        var underlines =
            await readerStore.getUnderlinesForArticle('article-markup-test');
        expect(underlines, hasLength(1));
        expect(
          paragraphText.substring(
            underlines.first.startOffset,
            underlines.first.endOffset,
          ),
          'Reading books brings',
        );

        // 3) Ortadaki altı çizili kelimeye ("books") TEK TIK -> yalnızca "books" kalkmalı,
        //    "Reading" ve "brings" çizili kalmalı.
        _tapFirstSpanMatching(tester, 'books');
        await tester.pumpAndSettle();

        underlines =
            await readerStore.getUnderlinesForArticle('article-markup-test');
        expect(underlines, hasLength(2));
        expect(
          paragraphText.substring(
            underlines[0].startOffset,
            underlines[0].endOffset,
          ),
          'Reading',
        );
        expect(
          paragraphText.substring(
            underlines[1].startOffset,
            underlines[1].endOffset,
          ),
          'brings',
        );

        // 4) Sağ üst Görünüm (Aa) menüsünden Fosforlu Kalem + Mavi seç -> metinde anında yansımalı.
        await tester.tap(
          find.byKey(const ValueKey<String>('reader_appearance_button')),
        );
        await tester.pumpAndSettle();

        final highlightBtn =
            find.byKey(const ValueKey<String>('reader_mark_style_highlight'));
        await tester.ensureVisible(highlightBtn);
        await tester.tap(highlightBtn);
        await tester.pumpAndSettle();

        final blueColorBtn =
            find.byKey(const ValueKey<String>('reader_mark_color_blue'));
        await tester.ensureVisible(blueColorBtn);
        await tester.tap(blueColorBtn);
        await tester.pumpAndSettle();

        expect(readerStore.preferences.markStyle, ArticleMarkStyle.highlight);
        expect(readerStore.preferences.markColor, ArticleMarkColor.blue);

        // Metindeki "Reading" span'ı anında Mavi Fosforlu Kalem rengine geçmiş olmalı.
        TextSpan? findSpanStyle(String text) {
          TextSpan? matched;
          tester.widget<RichText>(richTextFinder).text.visitChildren((span) {
            if (span is TextSpan && span.text == text) {
              matched = span;
              return false;
            }
            return true;
          });
          return matched;
        }

        final highlightedSpan = findSpanStyle('Reading');
        expect(highlightedSpan, isNotNull);
        expect(
          highlightedSpan!.style?.backgroundColor,
          ArticleMarkColor.blue.highlightFillForTone(readerStore.preferences.tone),
        );
        expect(highlightedSpan.style?.decoration, isNull);

        // 5) Üstü Çizili + Pembe/Kırmızı seç -> metinde anında lineThrough + rose rengi görünmeli.
        final strikeBtn = find.byKey(
          const ValueKey<String>('reader_mark_style_strikethrough'),
        );
        await tester.ensureVisible(strikeBtn);
        await tester.tap(strikeBtn);
        await tester.pumpAndSettle();

        final roseBtn =
            find.byKey(const ValueKey<String>('reader_mark_color_rose'));
        await tester.ensureVisible(roseBtn);
        await tester.tap(roseBtn);
        await tester.pumpAndSettle();

        expect(
          readerStore.preferences.markStyle,
          ArticleMarkStyle.strikethrough,
        );
        expect(readerStore.preferences.markColor, ArticleMarkColor.rose);

        final struckSpan = findSpanStyle('Reading');
        expect(struckSpan, isNotNull);
        expect(struckSpan!.style?.decoration, TextDecoration.lineThrough);
        expect(
          struckSpan.style?.decorationColor,
          ArticleMarkColor.rose.accentForTone(readerStore.preferences.tone),
        );
      },
    );

    testWidgets(
      'çizme kapalıyken seçilen cümle ve tam paragraf hazır çeviriden veya canlı yedekten hatasız çevrilir',
      (tester) async {
        // 1) JSON ve SQLite round-trip + hazır çeviri önceliği testi
        final parsed = Article.tryFromJson(<String, Object?>{
          'id': 'art-preset-tr',
          'level': 'B1',
          'title': 'Calm Reading',
          'author': 'Line Reader',
          'content':
              'Reading books brings calm. Quiet gardens inspire deep focus.',
          'sentence_translations': <String, Object?>{
            'Reading books brings calm.': 'Kitap okumak huzur verir.',
            'Quiet gardens inspire deep focus.':
                'Sessiz bahçeler derin odaklanmaya ilham verir.',
          },
          'paragraph_translations': <String>[
            'Kitap okumak huzur verir. Sessiz bahçeler derin odaklanmaya ilham verir.',
          ],
        });
        expect(parsed, isNotNull);

        final fromDb = Article.fromDbRow(
          parsed!.toDbRow(cachedAtMillis: 99999),
        );
        expect(fromDb.sentenceTranslations, hasLength(2));
        expect(fromDb.paragraphTranslations, hasLength(1));

        var networkCalls = 0;
        final mockClient = MockClient((_) async {
          networkCalls++;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<Object?>[
                <Object?>[
                  <Object?>['Canlı çevrilen cümle.', 'Live translated sentence.'],
                ],
              ]),
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        });
        final passageService = ArticlePassageTranslationService(
          httpClient: mockClient,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ArticleReaderScreen(
              article: fromDb,
              readerStore: _InMemoryReaderStore(),
              translationService: _FakeTranslationService(),
              passageTranslator: passageService,
              onAddWord: (_, __, ___, ____) async => SaveWordStatus.saved,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final paragraphGestureFinder =
            find.byKey(const ValueKey<String>('reader_paragraph_gesture_0'));
        final richTextFinder = find.descendant(
          of: paragraphGestureFinder,
          matching: find.byType(RichText),
        );
        final renderParagraph =
            tester.renderObject<RenderParagraph>(richTextFinder);

        Offset centerOfChar(int offset) {
          final box = renderParagraph
              .getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
              )
              .first;
          return renderParagraph.localToGlobal(box.toRect().center);
        }

        // A) "Reading books brings calm" cümlesini basılı tutup sürükleyerek seç -> "Çevir" butonuna bas.
        final startPos = centerOfChar(2); // "Reading"
        final endPos = centerOfChar(23); // "calm"
        final sentenceDrag = await tester.startGesture(startPos);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await sentenceDrag.moveTo(endPos);
        await tester.pump();
        await sentenceDrag.up();
        await tester.pumpAndSettle();

        final lookupBtn =
            find.byKey(const ValueKey<String>('reader_selection_lookup_button'));
        expect(lookupBtn, findsOneWidget);
        await tester.tap(lookupBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('article_passage_translation_sheet')),
          findsOneWidget,
        );
        expect(find.text('Kitap okumak huzur verir.'), findsOneWidget);
        expect(find.text('Hazır Çeviri'), findsOneWidget);
        // Hazır çeviri kullanıldığı için hiç ağ isteği atılmamalı!
        expect(networkCalls, 0);

        // Paneli kapat
        Navigator.of(
          tester.element(
            find.byKey(
              const ValueKey<String>('article_passage_translation_sheet'),
            ),
          ),
        ).pop();
        await tester.pumpAndSettle();

        // B) Kelimeye basılı tut -> "Paragrafı Çevir" butonuna bas -> tüm paragraf çevirisi gelmeli.
        final paraGesture = await tester.startGesture(startPos);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await paraGesture.up();
        await tester.pumpAndSettle();

        final translateParaBtn = find.byKey(
          const ValueKey<String>('reader_selection_translate_paragraph_button'),
        );
        expect(translateParaBtn, findsOneWidget);
        await tester.tap(translateParaBtn);
        await tester.pumpAndSettle();

        expect(find.text('Paragraf Çevirisi'), findsOneWidget);
        expect(
          find.text(
            'Kitap okumak huzur verir. Sessiz bahçeler derin odaklanmaya ilham verir.',
          ),
          findsOneWidget,
        );
        expect(networkCalls, 0);

        // C) Hazır çevirisi olmayan makalede canlı yedek çeviri çalışmalı.
        const noPresetArticle = Article(
          id: 'art-no-preset',
          level: 'B1',
          title: 'Live Fallback',
          content: 'Live translated sentence works cleanly here.',
        );
        final liveResult = await passageService.translate(
          article: noPresetArticle,
          selectedText: 'Live translated sentence works cleanly here.',
          paragraphIndex: 0,
          fullParagraphText: 'Live translated sentence works cleanly here.',
        );
        expect(liveResult.isFromArticlePreset, isFalse);
        expect(liveResult.translatedText, 'Canlı çevrilen cümle.');
        expect(networkCalls, 1);

        passageService.dispose();
      },
    );
  });
}
