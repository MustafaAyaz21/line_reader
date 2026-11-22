import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linereader/core/localization/app_locale.dart';
import 'package:linereader/features/articles/models/article.dart';
import 'package:linereader/features/articles/services/article_passage_translation_service.dart';
import 'package:linereader/features/lookup_overlay/quick_lookup_overlay_app.dart';
import 'package:linereader/features/translation/models/word_meaning.dart';
import 'package:linereader/features/translation/services/word_translation_service.dart';
import 'package:linereader/features/words/controllers/words_controller.dart';
import 'package:linereader/features/words/data/word_repository.dart';
import 'package:linereader/features/words/models/saved_word.dart';
import 'package:linereader/features/words/models/word_list.dart';

class _OverlayFakeWordRepository implements WordRepository {
  _OverlayFakeWordRepository() {
    _lists.add(
      WordList(
        id: 1,
        name: 'Favoriler',
        colorValue: WordListColors.palette[0],
        isDefault: true,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  }

  final List<WordList> _lists = <WordList>[];
  final List<SavedWord> savedWords = <SavedWord>[];
  int _nextListId = 2;
  int _nextWordId = 1;

  @override
  Future<List<WordList>> getAllLists() async {
    return _lists
        .map(
          (l) => l.copyWith(
            wordCount: savedWords.where((w) => w.listId == l.id).length,
          ),
        )
        .toList();
  }

  @override
  Future<int> getDefaultFavoritesListId() async => 1;

  @override
  Future<WordList> createList({
    required String name,
    required int colorValue,
  }) async {
    final created = WordList(
      id: _nextListId++,
      name: name.trim(),
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
      savedWords.where((w) => w.listId == listId).toList();

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
    savedWords.add(
      SavedWord(
        id: _nextWordId++,
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

class _OverlayFakeTranslationService implements WordTranslationService {
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

class _OverlayFakePassageTranslator implements ArticlePassageTranslator {
  @override
  Future<PassageTranslationResult> translate({
    required Article article,
    required String selectedText,
    int? paragraphIndex,
    String? fullParagraphText,
  }) async {
    return PassageTranslationResult(
      originalText: selectedText,
      translatedText: 'Her gün İngilizce öğrenmek seni daha özgüvenli yapar.',
      isFromArticlePreset: false,
    );
  }

  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'QuickLookupOverlayApp shows translucent mini card, creates new list, saves word, opens app, and closes on backdrop tap',
    (WidgetTester tester) async {
      final repo = _OverlayFakeWordRepository();
      final wordsController = WordsController(repo);
      final localeController = AppLocaleController();

      var closeCount = 0;
      String? openedInAppWord;

      await tester.pumpWidget(
        QuickLookupOverlayApp(
          initialText: '"resilient,"',
          translationService: _OverlayFakeTranslationService(),
          passageTranslator: _OverlayFakePassageTranslator(),
          wordsController: wordsController,
          localeController: localeController,
          onClose: () async => closeCount++,
          onOpenInMainApp: (word) async => openedInAppWord = word,
        ),
      );
      await tester.pumpAndSettle();

      // Şeffaf mini kart ve "Line'da Bak" rozeti görünmeli.
      expect(find.text("Line'da Bak"), findsOneWidget);
      expect(find.text('resilient'), findsOneWidget);
      expect(find.textContaining('dayanıklı'), findsOneWidget);
      expect(find.textContaining('esnek'), findsOneWidget);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.transparent);

      // Yeni liste oluştur ve kelimeyi yeni listeye kaydet.
      await tester.tap(
        find.byKey(const ValueKey<String>('quick_lookup_create_list_button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('word_list_name_field')),
        'Haberler',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('word_list_save_button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('quick_lookup_save_button')),
      );
      await tester.pumpAndSettle();

      final newsList = wordsController.lists.firstWhere(
        (l) => l.name == 'Haberler',
      );
      expect(repo.savedWords.length, 1);
      expect(repo.savedWords.first.word, 'resilient');
      expect(repo.savedWords.first.listId, newsList.id);

      // "Detaylı Aç" ana uygulamayı o kelimeyle açmalı.
      await tester.tap(
        find.byKey(const ValueKey<String>('quick_lookup_open_app_button')),
      );
      await tester.pumpAndSettle();
      expect(openedInAppWord, 'resilient');

      // Kartın dışına (şeffaf arka plana) dokununca overlay kapanmalı.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(closeCount, 1);

      wordsController.dispose();
      localeController.dispose();
    },
  );

  testWidgets(
    'QuickLookupOverlayApp translates multi-word sentence directly in mini card',
    (WidgetTester tester) async {
      final repo = _OverlayFakeWordRepository();
      final wordsController = WordsController(repo);
      final localeController = AppLocaleController();

      await tester.pumpWidget(
        QuickLookupOverlayApp(
          initialText: 'Learning English every day makes you more confident.',
          translationService: _OverlayFakeTranslationService(),
          passageTranslator: _OverlayFakePassageTranslator(),
          wordsController: wordsController,
          localeController: localeController,
          onClose: () async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Line'da Bak"), findsOneWidget);
      expect(
        find.text('Her gün İngilizce öğrenmek seni daha özgüvenli yapar.'),
        findsOneWidget,
      );

      wordsController.dispose();
      localeController.dispose();
    },
  );
}
