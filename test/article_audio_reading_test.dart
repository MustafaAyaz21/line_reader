import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linereader/features/articles/controllers/article_audio_controller.dart';
import 'package:linereader/features/articles/data/article_reader_repository.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/models/article_reader_models.dart';
import 'package:linereader/features/articles/screens/article_reader_screen.dart';
import 'package:linereader/features/articles/utils/article_text_parser.dart';

class _FakeTtsEngine implements ArticleTtsEngine {
  final List<String> spokenTexts = <String>[];
  String lastLanguage = 'en-US';
  double lastRate = 0.48;
  VoidCallback? _onCompleted;

  @override
  Future<void> configure({
    required String language,
    required double speechRate,
    required VoidCallback onCompleted,
    required void Function(String message) onError,
  }) async {
    lastLanguage = language;
    lastRate = speechRate;
    _onCompleted = onCompleted;
  }

  @override
  Future<void> setLanguage(String language) async {
    lastLanguage = language;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    lastRate = rate;
  }

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {}

  void simulateComplete() {
    _onCompleted?.call();
  }

  @override
  void dispose() {}
}

class _FakePodcastPlayer implements ArticlePodcastPlayer {
  _FakePodcastPlayer({this.shouldFailLoad = false});

  final bool shouldFailLoad;
  final StreamController<Duration> _posCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<void> _doneCtrl = StreamController<void>.broadcast();

  final List<Duration> seeks = <Duration>[];
  double lastPlaybackRate = 1.0;
  bool isPlaying = false;

  @override
  Stream<Duration> get onPositionChanged => _posCtrl.stream;

  @override
  Stream<Duration> get onDurationChanged => _durCtrl.stream;

  @override
  Stream<void> get onPlayerComplete => _doneCtrl.stream;

  void emitDuration(Duration d) => _durCtrl.add(d);
  void emitPosition(Duration p) => _posCtrl.add(p);

  @override
  Future<void> setSourceFile(String filePath) async {
    if (shouldFailLoad) throw Exception('Simulated file failure');
  }

  @override
  Future<void> setSourceUrl(String url) async {
    if (shouldFailLoad) throw Exception('Simulated network failure');
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    lastPlaybackRate = rate;
  }

  @override
  Future<void> resume() async {
    isPlaying = true;
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _posCtrl.add(position);
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
  }

  @override
  void dispose() {
    _posCtrl.close();
    _durCtrl.close();
    _doneCtrl.close();
  }
}

class _MemoryReaderStore implements ArticleReaderStore {
  @override
  Future<List<ArticleUnderline>> getUnderlinesForArticle(
    String articleId,
  ) async =>
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

void main() {
  group('ArticleTextParser • Cümle Bölme & Model Audio Alanları', () {
    test('kısaltmaları ve ondalık sayıları bölmeden cümlelere ayırır', () {
      const paragraphs = <String>[
        'Dr. Smith visited the U.S. in 2025. He walked 3.5 miles every morning!',
        'Was it relaxing? Yes, it truly was.',
      ];

      final sentences = ArticleTextParser.splitParagraphSentences(paragraphs);
      expect(sentences, hasLength(4));
      expect(sentences[0].paragraphIndex, 0);
      expect(sentences[0].text, 'Dr. Smith visited the U.S. in 2025.');
      expect(sentences[1].paragraphIndex, 0);
      expect(sentences[1].text, 'He walked 3.5 miles every morning!');
      expect(sentences[2].paragraphIndex, 1);
      expect(sentences[2].text, 'Was it relaxing?');
      expect(sentences[3].paragraphIndex, 1);
      expect(sentences[3].text, 'Yes, it truly was.');
    });

    test('Article JSON ve SQLite rawJson dönüşümü audio_url ve audio_segments korur',
        () {
      final parsed = Article.tryFromJson(<String, Object?>{
        'id': 'b1-podcast-1',
        'level': 'B1',
        'title': 'The Art of Walking',
        'content': 'First sentence. Second sentence.',
        'audio_url': 'https://line-reader.pages.dev/audio/b1-podcast-1.m4a',
        'audio_segments': <Map<String, Object?>>[
          <String, Object?>{'p': 0, 's': 0, 'start_ms': 0, 'end_ms': 2400},
          <String, Object?>{'p': 0, 's': 1, 'start_ms': 2400, 'end_ms': 5100},
        ],
      });

      expect(parsed, isNotNull);
      expect(parsed!.hasPodcastAudio, isTrue);
      expect(parsed.audioSegments, hasLength(2));

      final row = parsed.toDbRow(cachedAtMillis: 123456);
      final fromDb = Article.fromDbRow(row);
      expect(fromDb.audioUrl, parsed.audioUrl);
      expect(fromDb.audioSegments, hasLength(2));
      expect(fromDb.audioSegments[1].startMs, 2400);
    });
  });

  group('ArticleAudioController • Çift Motor (Cihaz TTS + Podcast AI)', () {
    test(
      'Cihaz TTS modunda cümle-cümle ilerler, geri/ileri cümle ve paragraf atlar, hız ve aksan değiştirir',
      () async {
        const article = Article(
          id: 'a2-tts-only',
          level: 'A2',
          title: 'Simple Story',
          content:
              'Sentence one. Sentence two.\n\nParagraph two first. Paragraph two second.',
        );
        final paragraphs = ArticleTextParser.splitParagraphs(article.content);
        final fakeTts = _FakeTtsEngine();
        final controller = ArticleAudioController(
          article: article,
          paragraphs: paragraphs,
          ttsEngine: fakeTts,
          podcastPlayer: _FakePodcastPlayer(),
        );

        expect(controller.mode, ArticleAudioMode.deviceTts);
        expect(controller.totalSentences, 4);
        expect(controller.totalParagraphs, 2);

        await controller.togglePlayerVisibility();
        expect(controller.isVisible, isTrue);
        expect(controller.isPlaying, isTrue);
        expect(fakeTts.spokenTexts.last, 'Sentence one.');

        // Cümle bitince otomatik 2. cümleye geçmeli
        fakeTts.simulateComplete();
        await Future<void>.delayed(Duration.zero);
        expect(controller.currentSentenceIndex, 1);
        expect(fakeTts.spokenTexts.last, 'Sentence two.');

        // Geriye basınca bir önceki cümleye (0) dönmeli
        await controller.previousSentence();
        expect(controller.currentSentenceIndex, 0);
        expect(fakeTts.spokenTexts.last, 'Sentence one.');

        // Sonraki paragrafa atlayınca 2. paragrafın ilk cümlesine (2) geçmeli
        await controller.nextParagraph();
        expect(controller.currentParagraphIndex, 1);
        expect(controller.currentSentenceIndex, 2);
        expect(fakeTts.spokenTexts.last, 'Paragraph two first.');

        // Hız ve aksan değişimi
        await controller.cycleSpeed();
        expect(controller.playbackSpeed, 1.25);
        await controller.toggleAccent();
        expect(controller.accent, ArticleTtsAccent.uk);
        expect(fakeTts.lastLanguage, 'en-GB');

        controller.dispose();
      },
    );

    test(
      'Podcast AI modunda zaman damgalarıyla cümle takibi ve geri/ileri cümle atlama çalışır',
      () async {
        const article = Article(
          id: 'b1-podcast',
          level: 'B1',
          title: 'Podcast Story',
          content:
              'Intro sentence. Second thought.\n\nSecond paragraph starts here.',
          audioUrl: 'https://line-reader.pages.dev/audio/b1-podcast.m4a',
          audioSegments: <ArticleAudioSegment>[
            ArticleAudioSegment(
              paragraphIndex: 0,
              sentenceIndex: 0,
              startMs: 0,
              endMs: 3000,
            ),
            ArticleAudioSegment(
              paragraphIndex: 0,
              sentenceIndex: 1,
              startMs: 3000,
              endMs: 6500,
            ),
            ArticleAudioSegment(
              paragraphIndex: 1,
              sentenceIndex: 2,
              startMs: 6500,
              endMs: 11000,
            ),
          ],
        );
        final paragraphs = ArticleTextParser.splitParagraphs(article.content);
        final fakePodcast = _FakePodcastPlayer();
        final controller = ArticleAudioController(
          article: article,
          paragraphs: paragraphs,
          ttsEngine: _FakeTtsEngine(),
          podcastPlayer: fakePodcast,
          audioFileResolver: (_) async => '/tmp/fake.m4a',
        );

        expect(controller.mode, ArticleAudioMode.podcastAudio);
        await controller.togglePlayerVisibility();
        expect(controller.isPlaying, isTrue);

        fakePodcast.emitDuration(const Duration(milliseconds: 11000));
        fakePodcast.emitPosition(const Duration(milliseconds: 4200));
        await Future<void>.delayed(Duration.zero);
        expect(controller.currentSentenceIndex, 1);

        // Geriye basınca 1. cümlenin (0ms) başına sarmalı
        await controller.previousSentence();
        expect(controller.currentSentenceIndex, 0);
        expect(fakePodcast.seeks.last, Duration.zero);

        // Sonraki paragrafa basınca 6500ms'ye atlamalı
        await controller.nextParagraph();
        expect(controller.currentParagraphIndex, 1);
        expect(fakePodcast.seeks.last, const Duration(milliseconds: 6500));

        await controller.cycleSpeed();
        expect(fakePodcast.lastPlaybackRate, 1.25);

        controller.dispose();
      },
    );

    test(
      'Podcast AI dosyası yüklenemezse otomatik olarak Cihaz TTS yedeğine düşer',
      () async {
        const article = Article(
          id: 'b1-offline-fallback',
          level: 'B1',
          title: 'Offline Fallback',
          content: 'First sentence. Second sentence.',
          audioUrl: 'https://line-reader.pages.dev/audio/missing.m4a',
        );
        final paragraphs = ArticleTextParser.splitParagraphs(article.content);
        final fakeTts = _FakeTtsEngine();
        final controller = ArticleAudioController(
          article: article,
          paragraphs: paragraphs,
          ttsEngine: fakeTts,
          podcastPlayer: _FakePodcastPlayer(shouldFailLoad: true),
          audioFileResolver: (_) async => null,
        );

        await controller.togglePlayerVisibility();
        expect(controller.mode, ArticleAudioMode.deviceTts);
        expect(controller.isPlaying, isTrue);
        expect(fakeTts.spokenTexts.first, 'First sentence.');

        controller.dispose();
      },
    );
  });

  group('ArticleReaderScreen • Sesli Okuma Arayüzü', () {
    testWidgets('kulaklık butonuna basınca oynatıcı açılır ve ileri/geri cümle çalışır',
        (tester) async {
      const article = Article(
        id: 'ui-audio-1',
        level: 'B1',
        title: 'Listening Practice',
        author: 'Line Reader',
        content: 'First line here. Second line here.\n\nAnother paragraph.',
      );
      final paragraphs = ArticleTextParser.splitParagraphs(article.content);
      final fakeTts = _FakeTtsEngine();
      final audioController = ArticleAudioController(
        article: article,
        paragraphs: paragraphs,
        ttsEngine: fakeTts,
        podcastPlayer: _FakePodcastPlayer(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ArticleReaderScreen(
            article: article,
            readerStore: _MemoryReaderStore(),
            audioController: audioController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('article_audio_player_bar')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('reader_audio_listen_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('article_audio_player_bar')),
        findsOneWidget,
      );
      expect(find.textContaining('Cümle 1/3'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('audio_next_sentence_button')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Cümle 2/3'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('audio_prev_sentence_button')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Cümle 1/3'), findsOneWidget);

      audioController.dispose();
    });
  });
}
