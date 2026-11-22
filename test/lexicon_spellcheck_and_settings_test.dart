import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linereader/core/settings/ipa_accent_controller.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/services/article_word_translation_service.dart';
import 'package:linereader/features/browser/widgets/word_preview_sheet.dart';
import 'package:linereader/features/translation/models/word_lexicon_info.dart';
import 'package:linereader/features/translation/models/word_meaning.dart';
import 'package:linereader/features/translation/services/local_dictionary_service.dart';
import 'package:linereader/features/translation/services/word_lexicon_service.dart';
import 'package:linereader/features/translation/services/word_translation_service.dart';
import 'package:linereader/features/words/controllers/words_controller.dart';
import 'package:linereader/features/words/data/word_repository.dart';
import 'package:linereader/features/words/models/saved_word.dart';
import 'package:linereader/features/words/models/word_list.dart';
import 'package:linereader/features/words/models/word_search_detail.dart';
import 'package:linereader/features/words/services/word_dictionary_search_service.dart';
import 'package:linereader/features/words/widgets/word_list_tile.dart';
import 'package:linereader/features/words/words_screen.dart';

class _StubFallbackTranslationService implements WordTranslationService {
  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    return WordMeaning.fromEntries(
      word: word,
      entries: const <MeaningEntry>[
        MeaningEntry(
          translation: 'öğrenmek',
          partOfSpeech: WordPartOfSpeech.verb,
          isContextual: true,
        ),
        MeaningEntry(
          translation: 'haberdar olmak',
          partOfSpeech: WordPartOfSpeech.verb,
        ),
        MeaningEntry(
          translation: 'bilgi edinmek',
          partOfSpeech: WordPartOfSpeech.verb,
        ),
        MeaningEntry(
          translation: 'ezberlemek',
          partOfSpeech: WordPartOfSpeech.verb,
        ),
      ],
    );
  }

  @override
  void dispose() {}
}

class _FakeMemoryWordRepo implements WordRepository {
  final List<WordList> _lists = <WordList>[
    WordList(
      id: 1,
      name: 'Favoriler',
      colorValue: WordListColors.palette[0],
      isDefault: true,
      createdAt: DateTime(2026, 1, 1),
    ),
  ];
  final List<SavedWord> saved = <SavedWord>[];
  int _nextId = 1;

  @override
  Future<List<WordList>> getAllLists() async => _lists;

  @override
  Future<int> getDefaultFavoritesListId() async => 1;

  @override
  Future<WordList> createList({
    required String name,
    required int colorValue,
  }) async {
    final created = WordList(
      id: _lists.length + 1,
      name: name,
      colorValue: colorValue,
      isDefault: false,
      createdAt: DateTime.now(),
    );
    _lists.add(created);
    return created;
  }

  @override
  Future<void> updateList({
    required int id,
    required String name,
    required int colorValue,
    required bool isDefault,
  }) async {}

  @override
  Future<void> deleteList(int id) async {}

  @override
  Future<List<SavedWord>> getWordsByList(int listId) async =>
      saved.where((w) => w.listId == listId).toList();

  @override
  Future<List<SavedWord>> findWordsInList({
    required int listId,
    required String word,
  }) async =>
      const <SavedWord>[];

  @override
  Future<SaveWordStatus> saveWord({
    required int listId,
    required String word,
    required String meaning,
    List<MeaningEntry> meanings = const <MeaningEntry>[],
    String? ipaUs,
    String? ipaUk,
    List<String> synonyms = const <String>[],
    List<String> antonyms = const <String>[],
    bool allowDuplicate = false,
  }) async {
    saved.add(
      SavedWord(
        id: _nextId++,
        listId: listId,
        word: word,
        meaning: meaning,
        meanings: meanings,
        ipaUs: ipaUs,
        ipaUk: ipaUk,
        synonyms: synonyms,
        antonyms: antonyms,
        createdAt: DateTime.now(),
      ),
    );
    return SaveWordStatus.saved;
  }

  @override
  Future<SaveWordStatus> updateWordMeanings({
    required SavedWord existingWord,
    required List<MeaningEntry> meanings,
    String? ipaUs,
    String? ipaUk,
    List<String>? synonyms,
    List<String>? antonyms,
  }) async =>
      SaveWordStatus.saved;

  @override
  Future<void> deleteWord(int id) async {}
}

class _FakeSpellSearchService extends WordDictionarySearchService {
  final List<String> queries = <String>[];

  @override
  Future<WordSearchDetail> searchWord(String rawQuery) async {
    final q = rawQuery.trim().toLowerCase();
    queries.add(q);
    if (q == 'elone') {
      return const WordSearchDetail(
        word: 'elone',
        meanings: <MeaningEntry>[],
        examples: <WordExampleSentence>[],
        isMisspelled: true,
        suggestions: <String>['alone'],
      );
    }
    return const WordSearchDetail(
      word: 'alone',
      meanings: <MeaningEntry>[
        MeaningEntry(
          translation: 'yalnız',
          partOfSpeech: WordPartOfSpeech.adjective,
        ),
        MeaningEntry(
          translation: 'tek başına',
          partOfSpeech: WordPartOfSpeech.adverb,
        ),
      ],
      examples: <WordExampleSentence>[
        WordExampleSentence(
          english: 'She walked alone through the park.',
          turkish: 'Parkta tek başına yürüdü.',
        ),
      ],
      lexiconInfo: WordLexiconInfo(
        word: 'alone',
        ipaUs: '/əˈɫoʊn/',
        ipaUk: '/ɐlˈəʊn/',
        synonyms: <String>['solo'],
        antonyms: <String>['together'],
      ),
    );
  }
}

void main() {
  test(
    'Bundled gzipped offline lexicon contains verified US & UK IPA for core words under 200 KB',
    () {
      final file = File('assets/lexicon_core.json.gz');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), lessThan(200 * 1024));

      final decoded = jsonDecode(
        utf8.decode(gzip.decode(file.readAsBytesSync())),
      ) as Map<String, Object?>;
      expect(decoded.length, greaterThan(5000));

      final learn = decoded['learn'] as Map<String, Object?>;
      expect(learn['u'], isNotNull);
      expect(learn['k'], isNotNull);
      expect((learn['s'] as List).isNotEmpty, isTrue);
      expect((learn['a'] as List).isNotEmpty, isTrue);

      final schedule = decoded['schedule'] as Map<String, Object?>;
      expect(schedule['u'], contains('sk'));
      expect(schedule['k'], contains('ʃ'));
    },
  );

  test(
    'ArticleWordTranslationService preserves 1st contextual meaning and enriches up to 4 meanings',
    () async {
      const article = Article(
        id: 'b1-learn',
        level: 'B1',
        title: 'Learning',
        content: 'We learn every day.',
        wordMeanings: <String, String>{'learn': 'öğrenmek'},
      );
      final service = ArticleWordTranslationService(
        article: article,
        fallbackService: _StubFallbackTranslationService(),
      );

      final result = await service.lookup(
        word: 'learn',
        contextSentence: 'We learn every day.',
      );
      expect(result.orderedEntries.length, 4);
      expect(result.orderedEntries.first.translation, 'öğrenmek');
      expect(result.orderedEntries.first.isContextual, isTrue);
      expect(
        result.orderedEntries.map((e) => e.translation),
        containsAll(<String>['öğrenmek', 'haberdar olmak', 'bilgi edinmek']),
      );
    },
  );

  test(
    'WordDictionarySearchService flags misspelled "elone" with Google didYouMean ("alone") and zero garbage translations',
    () async {
      final client = MockClient((http.Request req) async {
        final url = req.url.toString();
        if (url.contains('translate.googleapis.com')) {
          // Google gtx response with empty bilingual dict (root[1]=null) and didYouMean (root[7])
          final body = jsonEncode(<Object?>[
            <Object?>[
              <Object?>['yalnız', 'elone', null, null, 1],
            ],
            null,
            'en',
            null,
            null,
            null,
            null,
            <Object?>['<b><i>alone</i></b>', 'alone', <int>[1], null, null, null, null, null],
          ]);
          return http.Response.bytes(
            utf8.encode(body),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (url.contains('dictionaryapi.dev')) {
          return http.Response('{"title":"No Definitions Found"}', 404);
        }
        if (url.contains('datamuse.com')) {
          return http.Response('[{"word":"alone"}]', 200);
        }
        return http.Response('{}', 404);
      });

      final lexicon = WordLexiconService(
        httpClient: client,
        enableOnlineEnrichment: false,
        testBundledEntries: const <String, WordLexiconInfo>{
          'alone': WordLexiconInfo(
            word: 'alone',
            ipaUs: '/əˈɫoʊn/',
            ipaUk: '/ɐlˈəʊn/',
            synonyms: <String>['solo'],
            antonyms: <String>['together'],
          ),
        },
      );
      final searchService = WordDictionarySearchService(
        httpClient: client,
        localDictionary: LocalDictionaryService(sources: const []),
        lexiconService: lexicon,
      );

      final detail = await searchService.searchWord('elone');
      expect(detail.isMisspelled, isTrue);
      expect(detail.meanings, isEmpty);
      expect(detail.suggestions, contains('alone'));
    },
  );

  testWidgets(
    'WordPreviewSheet displays US/UK IPA beside Listen Sentence, lets user deselect a synonym/antonym, and saves remaining items',
    (WidgetTester tester) async {
      await IpaAccentController.shared.setAccent(IpaAccent.us);
      addTearDown(() => IpaAccentController.shared.setAccent(IpaAccent.us));

      final fakeLexicon = WordLexiconService(
        enableOnlineEnrichment: false,
        testBundledEntries: const <String, WordLexiconInfo>{
          'learn': WordLexiconInfo(
            word: 'learn',
            ipaUs: '/ˈɫɝn/',
            ipaUk: '/lˈɜːn/',
            synonyms: <String>['study', 'discover'],
            antonyms: <String>['forget'],
          ),
        },
      );

      WordLexiconInfo? savedLexicon;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordPreviewSheet(
              word: 'learn',
              contextSentence: 'We learn something new every day.',
              translationService: _StubFallbackTranslationService(),
              lexiconService: fakeLexicon,
              wordLists: <WordList>[
                WordList(
                  id: 1,
                  name: 'Favoriler',
                  colorValue: WordListColors.palette[0],
                  isDefault: true,
                  createdAt: DateTime(2026, 1, 1),
                ),
              ],
              onAddWord: (_, __, ___, ____, _____) {},
              onAddWordWithLexicon: (_, __, ___, ____, _____, lexicon) {
                savedLexicon = lexicon;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // US IPA görünmeli; dokununca UK IPA'ya geçmeli!
      expect(find.text('/ˈɫɝn/'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('word_ipa_badge')));
      await tester.pumpAndSettle();
      expect(find.text('/lˈɜːn/'), findsOneWidget);

      // 'discover' eş anlamlısını görünür yap ve tek dokunuşla çıkar.
      final discoverChip = find.byKey(
        const ValueKey<String>('syn_chip_discover'),
      );
      await tester.scrollUntilVisible(
        discoverChip,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(discoverChip);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kelimelerime Ekle'));
      await tester.pumpAndSettle();

      expect(savedLexicon, isNotNull);
      expect(savedLexicon!.ipaUs, '/ˈɫɝn/');
      expect(savedLexicon!.ipaUk, '/lˈɜːn/');
      expect(savedLexicon!.synonyms, <String>['study']);
      expect(savedLexicon!.antonyms, <String>['forget']);

      // SavedWord SQLite toMap/fromMap ve WordListTile doğrulaması
      final savedWord = SavedWord(
        id: 1,
        listId: 1,
        word: 'learn',
        meaning: 'öğrenmek (verb)',
        meanings: const <MeaningEntry>[
          MeaningEntry(
            translation: 'öğrenmek',
            partOfSpeech: WordPartOfSpeech.verb,
          ),
        ],
        ipaUs: savedLexicon!.ipaUs,
        ipaUk: savedLexicon!.ipaUk,
        synonyms: savedLexicon!.synonyms,
        antonyms: savedLexicon!.antonyms,
        createdAt: DateTime(2026, 1, 1),
      );
      final roundTrip = SavedWord.fromMap(savedWord.toMap());
      expect(roundTrip.ipaUs, '/ˈɫɝn/');
      expect(roundTrip.ipaUk, '/lˈɜːn/');
      expect(roundTrip.synonyms, <String>['study']);
      expect(roundTrip.antonyms, <String>['forget']);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordListTile(item: roundTrip, onDelete: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('/lˈɜːn/'), findsOneWidget);

      await IpaAccentController.shared.setAccent(IpaAccent.us);
    },
  );

  testWidgets(
    'WordsScreen renders Google-style DidYouMeanCard for "elone" and searches "alone" on tap',
    (WidgetTester tester) async {
      final repo = _FakeMemoryWordRepo();
      final controller = WordsController(repo);
      await controller.loadLists();
      final searchService = _FakeSpellSearchService();

      await tester.pumpWidget(
        MaterialApp(
          home: WordsScreen(
            controller: controller,
            searchService: searchService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('words_top_search_field')),
        'elone',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('words_top_search_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('did_you_mean_card')),
        findsOneWidget,
      );
      expect(find.text('Bunu mu aratmak istediniz?'), findsOneWidget);

      // Önerilen "alone" çipine tıkla -> otomatik olarak "alone" aratılmalı!
      await tester.tap(
        find.byKey(const ValueKey<String>('suggestion_chip_alone')),
      );
      await tester.pumpAndSettle();

      expect(searchService.queries, <String>['elone', 'alone']);
      expect(find.textContaining('yalnız'), findsAtLeastNWidgets(1));
      expect(find.text('/əˈɫoʊn/'), findsOneWidget);
    },
  );

  test(
    'AndroidManifest and ProcessTextOverlayActivity enforce singleTask + noHistory + finishAndRemoveTask to prevent background app duplication',
    () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:launchMode="singleTask"'));
      expect(manifest, contains('android:noHistory="true"'));
      expect(manifest, contains('android:autoRemoveFromRecents="true"'));

      final overlayKt = File(
        'android/app/src/main/kotlin/com/lineapps/linereader/ProcessTextOverlayActivity.kt',
      ).readAsStringSync();
      expect(overlayKt, contains('finishAndRemoveTask()'));
      expect(overlayKt, contains('onUserLeaveHint()'));
    },
  );
}
