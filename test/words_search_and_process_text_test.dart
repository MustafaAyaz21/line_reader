import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linereader/core/platform/process_text_channel.dart';
import 'package:linereader/features/browser/widgets/word_preview_sheet.dart';
import 'package:linereader/features/translation/models/word_meaning.dart';
import 'package:linereader/features/translation/services/word_translation_service.dart';
import 'package:linereader/features/words/controllers/words_controller.dart';
import 'package:linereader/features/words/data/word_repository.dart';
import 'package:linereader/features/words/models/saved_word.dart';
import 'package:linereader/features/words/models/word_list.dart';
import 'package:linereader/features/words/models/word_search_detail.dart';
import 'package:linereader/features/words/screens/add_word_search_screen.dart';
import 'package:linereader/features/words/services/word_dictionary_search_service.dart';
import 'package:linereader/features/words/words_screen.dart';

class _InMemoryWordRepository implements WordRepository {
  _InMemoryWordRepository() {
    _lists.addAll(<WordList>[
      WordList(
        id: 1,
        name: 'Favoriler',
        colorValue: WordListColors.palette[0],
        isDefault: true,
        createdAt: DateTime(2026, 1, 1),
      ),
      WordList(
        id: 2,
        name: 'IELTS',
        colorValue: WordListColors.palette[1],
        isDefault: false,
        createdAt: DateTime(2026, 1, 2),
      ),
    ]);
  }

  final List<WordList> _lists = <WordList>[];
  final List<SavedWord> _words = <SavedWord>[];
  int _nextListId = 3;
  int _nextWordId = 1;

  List<SavedWord> get savedWords => List<SavedWord>.unmodifiable(_words);

  @override
  Future<List<WordList>> getAllLists() async {
    return _lists.map((list) {
      final count = _words.where((w) => w.listId == list.id).length;
      return list.copyWith(wordCount: count);
    }).toList();
  }

  @override
  Future<int> getDefaultFavoritesListId() async => 1;

  @override
  Future<WordList> createList({
    required String name,
    required int colorValue,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Liste adı boş olamaz.');
    }
    if (_lists.any((l) => l.name.toLowerCase() == trimmed.toLowerCase())) {
      throw const FormatException('Bu isimde bir kelime listesi zaten var.');
    }
    final created = WordList(
      id: _nextListId++,
      name: trimmed,
      colorValue: colorValue,
      isDefault: false,
      createdAt: DateTime.now(),
      wordCount: 0,
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
  }) async {
    final idx = _lists.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    _lists[idx] = _lists[idx].copyWith(
      name: isDefault ? _lists[idx].name : name.trim(),
      colorValue: colorValue,
    );
  }

  @override
  Future<void> deleteList(int id) async {
    _lists.removeWhere((l) => l.id == id && !l.isDefault);
    _words.removeWhere((w) => w.listId == id);
  }

  @override
  Future<List<SavedWord>> getWordsByList(int listId) async {
    return _words.where((w) => w.listId == listId).toList();
  }

  @override
  Future<List<SavedWord>> findWordsInList({
    required int listId,
    required String word,
  }) async {
    final needle = word.trim().toLowerCase();
    return _words
        .where((w) => w.listId == listId && w.word.toLowerCase() == needle)
        .toList();
  }

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
    if (!allowDuplicate &&
        _words.any(
          (w) =>
              w.listId == listId &&
              w.word.toLowerCase() == word.trim().toLowerCase(),
        )) {
      return SaveWordStatus.alreadyExists;
    }
    _words.add(
      SavedWord(
        id: _nextWordId++,
        listId: listId,
        word: word.trim(),
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
  }) async {
    final idx = _words.indexWhere((w) => w.id == existingWord.id);
    if (idx < 0) return SaveWordStatus.error;
    if (meanings.isEmpty) {
      _words.removeAt(idx);
      return SaveWordStatus.saved;
    }
    _words[idx] = _words[idx].copyWith(
      meaning: meanings.first.baseFormatted,
      meanings: meanings,
      ipaUs: ipaUs ?? _words[idx].ipaUs,
      ipaUk: ipaUk ?? _words[idx].ipaUk,
      synonyms: synonyms ?? _words[idx].synonyms,
      antonyms: antonyms ?? _words[idx].antonyms,
    );
    return SaveWordStatus.saved;
  }

  @override
  Future<void> deleteWord(int id) async {
    _words.removeWhere((w) => w.id == id);
  }
}

class _FakeDictionarySearchService extends WordDictionarySearchService {
  final List<String> searchedQueries = <String>[];

  @override
  Future<WordSearchDetail> searchWord(String rawQuery) async {
    final normalized = rawQuery.trim().toLowerCase();
    searchedQueries.add(normalized);
    return WordSearchDetail(
      word: normalized,
      meanings: const <MeaningEntry>[
        MeaningEntry(
          translation: 'dayanıklı',
          partOfSpeech: WordPartOfSpeech.adjective,
        ),
        MeaningEntry(
          translation: 'dirençli',
          partOfSpeech: WordPartOfSpeech.adjective,
        ),
        MeaningEntry(
          translation: 'esnek',
          partOfSpeech: WordPartOfSpeech.adjective,
        ),
      ],
      examples: const <WordExampleSentence>[
        WordExampleSentence(
          english: 'She is resilient under pressure.',
          turkish: 'Baskı altında dayanıklıdır.',
        ),
      ],
    );
  }
}

class _FakeWordTranslationService implements WordTranslationService {
  @override
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  }) async {
    return WordMeaning.fromEntries(
      word: word,
      entries: const <MeaningEntry>[
        MeaningEntry(
          translation: 'dayanıklı',
          partOfSpeech: WordPartOfSpeech.adjective,
          isContextual: true,
        ),
        MeaningEntry(
          translation: 'esnek',
          partOfSpeech: WordPartOfSpeech.adjective,
        ),
      ],
    );
  }

  @override
  void dispose() {}
}

void main() {
  tearDown(() {
    ProcessTextChannel.resetForTest();
  });

  testWidgets(
    'WordsScreen top "Kelime Ara" searches without opening a list and saves to chosen list',
    (WidgetTester tester) async {
      final repo = _InMemoryWordRepository();
      final controller = WordsController(repo);
      await controller.loadLists();
      final searchService = _FakeDictionarySearchService();

      await tester.pumpWidget(
        MaterialApp(
          home: WordsScreen(
            controller: controller,
            searchService: searchService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Üst "Kelime Ara" alanı görünür olmalı.
      final searchField = find.byKey(const ValueKey<String>('words_top_search_field'));
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'resilient');
      await tester.tap(find.byKey(const ValueKey<String>('words_top_search_button')));
      await tester.pumpAndSettle();

      expect(searchService.searchedQueries, contains('resilient'));
      expect(find.textContaining('dayanıklı'), findsAtLeastNWidgets(1));

      // Hedef listeyi "IELTS" olarak değiştir.
      await tester.tap(
        find.byKey(const ValueKey<String>('words_search_list_dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('IELTS').last);
      await tester.pumpAndSettle();

      // Seçilen listeye kaydet.
      await tester.tap(
        find.byKey(const ValueKey<String>('words_search_save_button')),
      );
      await tester.pumpAndSettle();

      expect(repo.savedWords.length, 1);
      expect(repo.savedWords.first.word, 'resilient');
      expect(repo.savedWords.first.listId, 2);
      expect(controller.findListById(2)?.wordCount, 1);
    },
  );

  testWidgets(
    'WordPreviewSheet allows creating a new word list on the spot and auto-selects it',
    (WidgetTester tester) async {
      final repo = _InMemoryWordRepository();
      final controller = WordsController(repo);
      await controller.loadLists();

      int? addedListId;
      String? addedListName;
      String? addedWord;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordPreviewSheet(
              word: 'resilient',
              translationService: _FakeWordTranslationService(),
              wordLists: controller.lists,
              loadWordLists: controller.loadLists,
              onCreateWordList: (name, colorValue) =>
                  controller.createListWithResult(
                name: name,
                colorValue: colorValue,
              ),
              onAddWord: (word, meaning, meanings, listId, listName) {
                addedWord = word;
                addedListId = listId;
                addedListName = listName;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Yeni Liste" butonuna basıp yeni liste oluştur.
      final createListBtn = find.byKey(
        const ValueKey<String>('sheet_create_word_list_button'),
      );
      expect(createListBtn, findsOneWidget);
      await tester.tap(createListBtn);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('word_list_name_field')),
        'Seyahat',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('word_list_save_button')),
      );
      await tester.pumpAndSettle();

      // Yeni liste otomatik seçilmiş olmalı; "Kelimelerime Ekle" basıldığında ona gitmeli.
      expect(controller.lists.any((l) => l.name == 'Seyahat'), isTrue);
      await tester.tap(find.text('Kelimelerime Ekle'));
      await tester.pumpAndSettle();

      expect(addedWord, 'resilient');
      expect(addedListName, 'Seyahat');
      expect(addedListId, isNotNull);
    },
  );

  testWidgets(
    'AddWordSearchScreen allows creating a new word list and saving into it',
    (WidgetTester tester) async {
      final repo = _InMemoryWordRepository();
      final controller = WordsController(repo);
      await controller.loadLists();
      final searchService = _FakeDictionarySearchService();

      await tester.pumpWidget(
        MaterialApp(
          home: AddWordSearchScreen(
            listId: 1,
            controller: controller,
            initialWord: 'resilient',
            searchService: searchService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('add_word_create_list_button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('word_list_name_field')),
        'Akademik',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('word_list_save_button')),
      );
      await tester.pumpAndSettle();

      // Bir anlam seç ve FAB (+) ile kaydet.
      await tester.tap(find.textContaining('dayanıklı').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final academicList = controller.lists.firstWhere((l) => l.name == 'Akademik');
      expect(repo.savedWords.length, 1);
      expect(repo.savedWords.first.listId, academicList.id);
    },
  );

  testWidgets(
    'External search trigger ("Line Reader ile arat") fills top search field and searches automatically',
    (WidgetTester tester) async {
      final repo = _InMemoryWordRepository();
      final controller = WordsController(repo);
      await controller.loadLists();
      final searchService = _FakeDictionarySearchService();
      final trigger = WordsSearchTriggerController();

      await tester.pumpWidget(
        MaterialApp(
          home: WordsScreen(
            controller: controller,
            searchTriggerController: trigger,
            searchService: searchService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dış uygulamadan "Line Reader ile arat" ile metin geldiğini simüle et.
      final cleaned = ProcessTextChannel.sanitizeExternalQuery('"resilient,"');
      expect(cleaned, 'resilient');
      trigger.triggerSearch(cleaned!);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('words_top_search_field')),
      );
      expect(textField.controller?.text, 'resilient');
      expect(searchService.searchedQueries, contains('resilient'));
      expect(find.textContaining('dayanıklı'), findsAtLeastNWidgets(1));
    },
  );

  test(
    'ProcessTextChannel sanitizes external queries and AndroidManifest/Activities register "Line\'da Bak"',
    () {
      expect(
        ProcessTextChannel.sanitizeExternalQuery('  (take off!)  '),
        'take off',
      );
      expect(
        ProcessTextChannel.sanitizeExternalQuery('   '),
        isNull,
      );

      ProcessTextChannel.dispatchExternalTextForTest('“perseverance.”');
      expect(ProcessTextChannel.hasPendingText, isTrue);
      expect(ProcessTextChannel.consumePendingText(), 'perseverance');
      expect(ProcessTextChannel.hasPendingText, isFalse);

      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android.intent.action.PROCESS_TEXT'));
      expect(manifest, contains('android:name=".ProcessTextOverlayActivity"'));
      expect(manifest, contains('android:label="Line&apos;da Bak"'));
      expect(manifest, contains('android:mimeType="text/plain"'));

      final overlayActivity = File(
        'android/app/src/main/kotlin/com/lineapps/linereader/ProcessTextOverlayActivity.kt',
      ).readAsStringSync();
      expect(overlayActivity, contains('BackgroundMode.transparent'));
      expect(overlayActivity, contains('processTextOverlayMain'));
      expect(overlayActivity, contains('com.lineapps.linereader/lookup_overlay'));

      final mainActivity = File(
        'android/app/src/main/kotlin/com/lineapps/linereader/MainActivity.kt',
      ).readAsStringSync();
      expect(mainActivity, contains('com.lineapps.linereader/process_text'));
      expect(mainActivity, contains('ACTION_OPEN_WORD_SEARCH'));
      expect(mainActivity, contains('consumeInitialProcessText'));
      expect(mainActivity, contains('onProcessText'));
    },
  );
}
