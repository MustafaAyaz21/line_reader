import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/settings/api_key_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_backdrop.dart';
import '../../../core/tts/tts_service.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/services/word_translation_service.dart';
import '../controllers/words_controller.dart';
import '../models/saved_word.dart';
import '../models/word_list.dart';
import '../models/word_search_detail.dart';
import '../services/word_dictionary_search_service.dart';
import '../widgets/word_lexicon_widgets.dart';
import '../widgets/word_list_editor_dialog.dart';

enum _ExistingWordSaveAction {
  overwrite,
  addAsNew,
}

/// Kelime listesi içindeki `+` veya karttaki düzenleme (`Icons.edit_outlined`)
/// butonundan açılan manuel kelime arama, 10–15 anlam arasından çoklu seçim
/// (tik ✓), 3 kısa örnek cümle ve "Üstüne ekle / Yeni kelime olarak ekle" ekranı.
class AddWordSearchScreen extends StatefulWidget {
  const AddWordSearchScreen({
    super.key,
    required this.listId,
    required this.controller,
    this.wordList,
    this.initialWord,
    this.editingWord,
    this.apiKeyController,
    this.ttsService,
    this.searchService,
  });

  final int listId;
  final WordsController controller;
  final WordList? wordList;
  final String? initialWord;
  final SavedWord? editingWord;
  final ApiKeyController? apiKeyController;
  final TtsService? ttsService;
  final WordDictionarySearchService? searchService;

  @override
  State<AddWordSearchScreen> createState() => _AddWordSearchScreenState();
}

class _AddWordSearchScreenState extends State<AddWordSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final WordDictionarySearchService _searchService;
  late final bool _ownsSearchService;
  late int _selectedListId;
  Timer? _debounceTimer;
  Timer? _suggestDebounce;
  int _suggestGeneration = 0;
  int _searchGeneration = 0;
  List<WordPrefixSuggestion> _prefixSuggestions = const <WordPrefixSuggestion>[];
  final Set<String> _reportedMissingWords = <String>{};
  bool _isReportingMissing = false;

  bool _isLoading = false;
  bool _isLoadingExamples = false;
  bool _isSaving = false;
  String? _errorMessage;
  WordSearchDetail? _detail;
  SavedWord? _matchedExistingWord;
  final Set<int> _selectedIndices = <int>{};
  final Set<String> _selectedSynonyms = <String>{};
  final Set<String> _selectedAntonyms = <String>{};
  bool _showAllMeanings = false;

  bool get _hasInitialWord =>
      widget.initialWord != null && widget.initialWord!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedListId = widget.listId;
    _ownsSearchService = widget.searchService == null;
    // Kelime listesine ekleme akışında gereksiz AI çağrısı yapılmaz;
    // doğrudan ücretsiz çoklu sözlük + hafif yerel sözlük/kök çözümleyici kullanılır.
    _searchService = widget.searchService ??
        WordDictionarySearchService(
          geminiApiKeyProvider: null,
          shouldAttemptGeminiProvider: () => false,
        );

    if (_hasInitialWord) {
      final initial = widget.initialWord!.trim();
      _searchController.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _performSearch(initial, dismissKeyboard: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _suggestDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    if (_ownsSearchService) {
      _searchService.dispose();
    }
    super.dispose();
  }

  String _normalizeKey(String raw) {
    return raw.trim().replaceAll('İ', 'i').toLowerCase();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounceTimer?.cancel();
    _suggestDebounce?.cancel();

    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (lower.length < 2 || !RegExp(r'^[a-z]+$').hasMatch(lower)) {
      if (_prefixSuggestions.isNotEmpty) {
        setState(() => _prefixSuggestions = const <WordPrefixSuggestion>[]);
      }
    } else {
      final sGen = ++_suggestGeneration;
      _suggestDebounce = Timer(const Duration(milliseconds: 250), () async {
        final list = await _searchService.fetchPrefixSuggestions(lower);
        if (!mounted || sGen != _suggestGeneration) return;
        if (_searchController.text.trim().toLowerCase() != lower) return;
        setState(() => _prefixSuggestions = list);
      });
    }

    if (trimmed.length < 2) return;

    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_searchController.text.trim() == trimmed &&
          _detail?.word != _normalizeKey(trimmed)) {
        _performSearch(trimmed, dismissKeyboard: false);
      }
    });
  }

  Future<void> _handleReportMissingWord(String word) async {
    final key = word.trim().toLowerCase();
    if (key.isEmpty || _isReportingMissing || _reportedMissingWords.contains(key)) {
      return;
    }
    setState(() => _isReportingMissing = true);
    final ok = await _searchService.reportMissingWord(key);
    if (!mounted) return;
    setState(() {
      _isReportingMissing = false;
      if (ok) {
        _reportedMissingWords.add(key);
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '"$key" eksik kelime olarak bildirildi. Teşekkürler!'
                : 'Bildirim gönderilemedi, lütfen bağlantınızı kontrol edin.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _performSearch(
    String rawQuery, {
    bool dismissKeyboard = true,
  }) async {
    _debounceTimer?.cancel();
    final query = rawQuery.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Lütfen aramak istediğiniz İngilizce kelimeyi yazın.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    if (dismissKeyboard) {
      _searchFocusNode.unfocus();
    }

    final myGen = ++_searchGeneration;
    _suggestDebounce?.cancel();
    _suggestGeneration++;
    setState(() {
      _prefixSuggestions = const <WordPrefixSuggestion>[];
      _isLoading = true;
      _isLoadingExamples = true;
      _errorMessage = null;
      _detail = null;
      _matchedExistingWord = null;
      _selectedIndices.clear();
      _selectedSynonyms.clear();
      _selectedAntonyms.clear();
      _showAllMeanings = false;
    });

    try {
      // Sözlük araması ile bu kelimenin listede zaten kayıtlı olup olmadığını paralel kontrol et.
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _searchService.searchWord(
          query,
          onExamplesUpdated: (examples) {
            if (!mounted || myGen != _searchGeneration) return;
            setState(() {
              _isLoadingExamples = false;
              final current = _detail;
              if (current != null &&
                  !current.isMisspelled &&
                  examples.isNotEmpty) {
                _detail = WordSearchDetail(
                  word: current.word,
                  meanings: current.meanings,
                  examples: examples,
                  lexiconInfo: current.lexiconInfo,
                );
              }
            });
          },
        ),
        widget.controller.findExistingWordsInList(
          listId: _selectedListId,
          word: query,
        ),
      ]);
      if (!mounted || myGen != _searchGeneration) return;

      final detail = results[0] as WordSearchDetail;
      final existingList = results[1] as List<SavedWord>;

      if (detail.isMisspelled) {
        setState(() {
          _detail = detail;
          _matchedExistingWord = null;
          _selectedIndices.clear();
          _selectedSynonyms.clear();
          _selectedAntonyms.clear();
          _isLoading = false;
          _isLoadingExamples = false;
        });
        return;
      }

      // Düzenleme ikonundan gelindiyse ve aranan kelime aynıysa o spesifik kaydı seç;
      // aksi halde aynı listedeki en güncel mevcut kaydı eşleştir.
      SavedWord? matched;
      final editing = widget.editingWord;
      if (editing != null &&
          _normalizeKey(editing.word) == _normalizeKey(detail.word)) {
        matched = editing;
        for (final item in existingList) {
          if (item.id == editing.id) {
            matched = item;
            break;
          }
        }
      } else if (existingList.isNotEmpty) {
        matched = existingList.first;
      }

      final mergedMeanings = List<MeaningEntry>.from(detail.meanings);
      final preselected = <int>{};

      if (matched != null) {
        final savedMeanings = matched.allMeanings;
        final savedKeys = <String>{};
        for (final savedEntry in savedMeanings) {
          final key = _normalizeKey(savedEntry.translation);
          if (key.isEmpty ||
              savedEntry.translation == SavedWord.defaultPlaceholderMeaning) {
            continue;
          }
          savedKeys.add(key);
        }

        // Daha önce kayıtlı olup sözlük sonuçlarında olmayan anlam varsa en başa ekle.
        final missingFromFetched = <MeaningEntry>[];
        final fetchedKeys =
            mergedMeanings.map((e) => _normalizeKey(e.translation)).toSet();
        for (final savedEntry in savedMeanings) {
          final key = _normalizeKey(savedEntry.translation);
          if (key.isEmpty ||
              savedEntry.translation == SavedWord.defaultPlaceholderMeaning) {
            continue;
          }
          if (!fetchedKeys.contains(key)) {
            missingFromFetched.add(savedEntry);
            fetchedKeys.add(key);
          }
        }
        if (missingFromFetched.isNotEmpty) {
          mergedMeanings.insertAll(0, missingFromFetched);
        }

        // Mevcut kayıtlı tüm anlamları otomatik olarak tikli (checked = true) getir.
        for (var i = 0; i < mergedMeanings.length; i++) {
          if (savedKeys.contains(_normalizeKey(mergedMeanings[i].translation))) {
            preselected.add(i);
          }
        }
      }

      final lexicon = detail.lexiconInfo;
      // Yeni aranan kelimede eş/zıt anlamlılar otomatik seçili gelmez;
      // kullanıcı yalnızca eklemek istediklerine tıklayarak tikler.
      // Daha önce kaydedilmiş bir kelime düzenleniyorsa mevcut seçimler korunur.
      final preselectedSynonyms = <String>{};
      final preselectedAntonyms = <String>{};
      if (matched != null) {
        final savedSynKeys =
            matched.synonyms.map(_normalizeKey).toSet();
        final savedAntKeys =
            matched.antonyms.map(_normalizeKey).toSet();
        for (final s in lexicon?.synonyms ?? const <String>[]) {
          if (savedSynKeys.contains(_normalizeKey(s))) {
            preselectedSynonyms.add(s);
          }
        }
        for (final a in lexicon?.antonyms ?? const <String>[]) {
          if (savedAntKeys.contains(_normalizeKey(a))) {
            preselectedAntonyms.add(a);
          }
        }
      }

      setState(() {
        _detail = WordSearchDetail(
          word: detail.word,
          meanings: List<MeaningEntry>.unmodifiable(mergedMeanings),
          examples: detail.examples,
          lexiconInfo: lexicon,
        );
        _matchedExistingWord = matched;
        _selectedIndices
          ..clear()
          ..addAll(preselected);
        _selectedSynonyms
          ..clear()
          ..addAll(preselectedSynonyms);
        _selectedAntonyms
          ..clear()
          ..addAll(preselectedAntonyms);
        _isLoading = false;
        if (detail.examples.isNotEmpty) {
          _isLoadingExamples = false;
        }
      });
    } on TranslationException catch (error) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
        _isLoadingExamples = false;
      });
    } catch (_) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _errorMessage =
            'Kelime aranırken bir sorun oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.';
        _isLoading = false;
        _isLoadingExamples = false;
      });
    }
  }

  Future<void> _handleTargetListChanged(int nextListId) async {
    if (nextListId == _selectedListId) return;
    setState(() => _selectedListId = nextListId);
    final detail = _detail;
    if (detail == null) return;

    final existingList = await widget.controller.findExistingWordsInList(
      listId: nextListId,
      word: detail.word,
    );
    if (!mounted || _selectedListId != nextListId || _detail?.word != detail.word) {
      return;
    }

    setState(() {
      _matchedExistingWord =
          existingList.isNotEmpty ? existingList.first : null;
    });
  }

  Future<void> _handleCreateNewList() async {
    WordList? createdList;
    final created = await WordListEditorDialog.show(
      context,
      onSubmit: (name, colorValue, icon) async {
        final result = await widget.controller.createListWithResult(
          name: name,
          colorValue: colorValue,
          icon: icon,
        );
        if (result.error != null) {
          return result.error;
        }
        createdList = result.list;
        return null;
      },
    );

    if (created != true || !mounted) return;
    final newlyCreated = createdList;
    if (newlyCreated != null) {
      await _handleTargetListChanged(newlyCreated.id);
      _showSnack('"${newlyCreated.name}" listesi oluşturuldu ve seçildi.');
    }
  }

  void _toggleMeaningSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _clearAllSelections() {
    if (_selectedIndices.isEmpty) return;
    setState(() => _selectedIndices.clear());
  }

  Future<void> _showAddCustomMeaningDialog() async {
    final currentDetail = _detail;
    if (currentDetail == null) return;

    final defaultPos = currentDetail.meanings.isNotEmpty
        ? (currentDetail.meanings.first.partOfSpeech ?? WordPartOfSpeech.verb)
        : WordPartOfSpeech.noun;

    final addedEntry = await showDialog<MeaningEntry>(
      context: context,
      builder: (dialogContext) => _CustomMeaningDialog(
        word: currentDetail.word,
        initialPartOfSpeech: defaultPos,
      ),
    );

    if (addedEntry == null || !mounted) return;

    final addedKey = _normalizeKey(addedEntry.translation);
    final existingIndex = currentDetail.meanings.indexWhere(
      (entry) =>
          _normalizeKey(entry.translation) == addedKey &&
          entry.partOfSpeech == addedEntry.partOfSpeech,
    );

    if (existingIndex >= 0) {
      setState(() {
        _selectedIndices.add(existingIndex);
      });
      _showSnack('"${addedEntry.baseFormatted}" seçili anlamlara eklendi.');
      return;
    }

    final updatedMeanings = <MeaningEntry>[
      addedEntry.copyWith(isContextual: false),
      ...currentDetail.meanings,
    ];
    final shiftedSelections = <int>{
      0,
      for (final idx in _selectedIndices) idx + 1,
    };

    setState(() {
      _detail = WordSearchDetail(
        word: currentDetail.word,
        meanings: List<MeaningEntry>.unmodifiable(updatedMeanings),
        examples: currentDetail.examples,
        lexiconInfo: currentDetail.lexiconInfo,
      );
      _selectedIndices
        ..clear()
        ..addAll(shiftedSelections);
    });
    _showSnack('"${addedEntry.baseFormatted}" eklendi ve tiklendi.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<_ExistingWordSaveAction?> _askExistingWordAction(
    String word,
    int selectedCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showModalBottomSheet<_ExistingWordSaveAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '"$word" listede zaten kayıtlı',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Seçtiğiniz anlamları mevcut kaydın üzerine güncelleyebilir veya ayrı bir yeni kart olarak ekleyebilirsiniz.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // Seçenek 1: Üstüne ekle
              Material(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_ExistingWordSaveAction.overwrite),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.playlist_add_check_rounded,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Üstüne ekle',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selectedCount == 0
                                    ? 'Hiç anlam seçili olmadığı için mevcut kayıt listeden kaldırılır.'
                                    : 'Mevcut kaydın anlamlarını seçili $selectedCount anlamla senkronize eder.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer
                                      .withAlpha(210),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Seçenek 2: Yeni kelime olarak ekle
              Material(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_ExistingWordSaveAction.addAsNew),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Yeni kelime olarak ekle',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Aynı kelimeden seçili anlamlarla bağımsız yeni bir kart oluşturur.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSaveSelected() async {
    if (_isSaving) return;

    final detail = _detail;
    if (detail == null || detail.isMisspelled) {
      _showSnack('Önce geçerli bir kelime arayıp anlam seçin.');
      return;
    }

    final existing = _matchedExistingWord;
    final sortedIndices = _selectedIndices.toList()..sort();
    final selectedMeanings = <MeaningEntry>[
      for (final idx in sortedIndices)
        detail.meanings[idx].copyWith(isContextual: false),
    ];
    final lexicon = detail.lexiconInfo;
    final chosenSynonyms = lexicon == null
        ? const <String>[]
        : lexicon.synonyms
            .where(_selectedSynonyms.contains)
            .toList(growable: false);
    final chosenAntonyms = lexicon == null
        ? const <String>[]
        : lexicon.antonyms
            .where(_selectedAntonyms.contains)
            .toList(growable: false);

    // Kelime listede henüz yoksa doğrudan yeni kayıt olarak ekle.
    if (existing == null) {
      if (selectedMeanings.isEmpty) {
        _showSnack('Lütfen kaydetmek için en az bir anlam seçin.');
        return;
      }

      setState(() => _isSaving = true);
      try {
        final status = await widget.controller.addWord(
          word: detail.word,
          meaning: selectedMeanings.first.baseFormatted,
          meanings: selectedMeanings,
          ipaUs: lexicon?.ipaUs,
          ipaUk: lexicon?.ipaUk,
          synonyms: chosenSynonyms,
          antonyms: chosenAntonyms,
          listId: _selectedListId,
          allowDuplicate: true,
        );
        if (!mounted) return;
        if (status == SaveWordStatus.saved) {
          final targetListName =
              widget.controller.findListById(_selectedListId)?.name;
          final msg = targetListName != null && targetListName.isNotEmpty
              ? '"${detail.word}" "$targetListName" listesine eklendi.'
              : '"${detail.word}" listeye eklendi.';
          Navigator.of(context).pop(msg);
          return;
        }
        setState(() => _isSaving = false);
        _showSnack('Kelime kaydedilirken bir sorun oluştu.');
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        _showSnack('Kelime kaydedilirken beklenmeyen bir sorun oluştu.');
      }
      return;
    }

    // Kelime zaten kayıtlıysa kullanıcıya iki net seçenek sun:
    // "Üstüne ekle" veya "Yeni kelime olarak ekle".
    final chosenAction = await _askExistingWordAction(
      detail.word,
      selectedMeanings.length,
    );
    if (chosenAction == null || !mounted) return;

    if (chosenAction == _ExistingWordSaveAction.addAsNew) {
      if (selectedMeanings.isEmpty) {
        _showSnack('Yeni kelime olarak eklemek için en az bir anlam seçin.');
        return;
      }
      setState(() => _isSaving = true);
      try {
        final status = await widget.controller.addWord(
          word: detail.word,
          meaning: selectedMeanings.first.baseFormatted,
          meanings: selectedMeanings,
          ipaUs: lexicon?.ipaUs,
          ipaUk: lexicon?.ipaUk,
          synonyms: chosenSynonyms,
          antonyms: chosenAntonyms,
          listId: _selectedListId,
          allowDuplicate: true,
        );
        if (!mounted) return;
        if (status == SaveWordStatus.saved) {
          Navigator.of(context)
              .pop('"${detail.word}" yeni kayıt olarak eklendi.');
          return;
        }
        setState(() => _isSaving = false);
        _showSnack('Yeni kayıt eklenirken bir sorun oluştu.');
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        _showSnack('Yeni kayıt eklenirken beklenmeyen bir sorun oluştu.');
      }
      return;
    }

    // "Üstüne ekle": mevcut kaydı seçili anlamlarla güncelle/senkronize et.
    setState(() => _isSaving = true);
    try {
      final status = await widget.controller.updateWordMeanings(
        existingWord: existing,
        meanings: selectedMeanings,
        ipaUs: lexicon?.ipaUs,
        ipaUk: lexicon?.ipaUk,
        synonyms: chosenSynonyms,
        antonyms: chosenAntonyms,
      );
      if (!mounted) return;
      if (status == SaveWordStatus.saved) {
        final msg = selectedMeanings.isEmpty
            ? '"${detail.word}" tüm anlamları kaldırıldığı için listeden çıkarıldı.'
            : '"${detail.word}" anlamları güncellendi.';
        Navigator.of(context).pop(msg);
        return;
      }
      setState(() => _isSaving = false);
      _showSnack('Kelime güncellenirken bir sorun oluştu.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack('Kelime güncellenirken beklenmeyen bir sorun oluştu.');
    }
  }

  Future<void> _handleSpeak(String text, TtsSpeakingTarget target) async {
    final tts = widget.ttsService;
    if (tts == null || text.trim().isEmpty) return;
    await tts.toggleSpeak(text: text, target: target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allLists = widget.controller.lists;
    final list = widget.controller.findListById(_selectedListId) ??
        (_selectedListId == widget.listId ? widget.wordList : null);
    final selectedCount = _selectedIndices.length;
    final visuals = AppThemeVisuals.of(context);
    final detail = _detail;
    final hasValidDetail = detail != null && !detail.isMisspelled;

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
        appBar: AppBar(
          title: Row(
            children: [
              if (list != null) ...[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: list.color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: list.color.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: list.icon != null && list.icon!.isNotEmpty
                      ? Text(list.icon!, style: const TextStyle(fontSize: 14))
                      : Icon(
                          list.isDefault
                              ? Icons.star_rounded
                              : Icons.folder_rounded,
                          color: list.color,
                          size: 16,
                        ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  list != null ? 'Kelime Ekle • ${list.name}' : 'Kelime Ekle',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: hasValidDetail
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Align(
                    alignment: Alignment.center,
                    heightFactor: 1.0,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey<String>('add_word_save_button'),
                          onPressed: _isSaving ? null : _handleSaveSelected,
                          icon: _isSaving
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.bookmark_add_rounded),
                          label: Text(
                            _isSaving
                                ? 'Kaydediliyor...'
                                : (list != null
                                    ? '"${list.name}" Listesine Kaydet ($selectedCount Anlam)'
                                    : 'Listeye Kaydet ($selectedCount Anlam)'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Üst Arama Çubuğu
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          autofocus: !_hasInitialWord,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.search,
                          autocorrect: true,
                          enableSuggestions: true,
                          onChanged: _onSearchChanged,
                          onSubmitted: (value) => _performSearch(value),
                          decoration: InputDecoration(
                            hintText: 'İngilizce kelime yazın (örn. make, run)...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      _debounceTimer?.cancel();
                                      _searchController.clear();
                                      setState(() {
                                        _detail = null;
                                        _matchedExistingWord = null;
                                        _errorMessage = null;
                                        _selectedIndices.clear();
                                        _selectedSynonyms.clear();
                                        _selectedAntonyms.clear();
                                        _showAllMeanings = false;
                                      });
                                      _searchFocusNode.requestFocus();
                                    },
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    tooltip: 'Temizle',
                                  )
                                : null,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withAlpha(120),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant.withAlpha(80),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant.withAlpha(80),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 120,
                        height: 46,
                        child: FilledButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => _performSearch(_searchController.text),
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: const Text('Ara'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_prefixSuggestions.isNotEmpty &&
                    !_isLoading &&
                    _detail == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: WordPrefixSuggestionsList(
                      suggestions: _prefixSuggestions,
                      onSelectWord: (word) {
                        _searchController.text = word;
                        _searchController.selection = TextSelection.collapsed(
                          offset: word.length,
                        );
                        _performSearch(word, dismissKeyboard: true);
                      },
                    ),
                  ),
                if (widget.editingWord == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: Row(
                      children: [
                        if (allLists.isNotEmpty) ...[
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              key: const ValueKey<String>('add_word_list_dropdown'),
                              value: allLists.any((item) => item.id == _selectedListId)
                                  ? _selectedListId
                                  : allLists.first.id,
                              isExpanded: true,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withAlpha(120),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.outlineVariant.withAlpha(80),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.outlineVariant.withAlpha(80),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.primary,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                              items: allLists.map((item) {
                                return DropdownMenuItem<int>(
                                  value: item.id,
                                  child: Row(
                                    children: [
                                      if (item.icon != null && item.icon!.isNotEmpty) ...[
                                        Text(item.icon!, style: const TextStyle(fontSize: 14)),
                                        const SizedBox(width: 8),
                                      ] else ...[
                                        Container(
                                          width: 8,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: item.color,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  _handleTargetListChanged(value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        SizedBox(
                          width: 120,
                          height: 46,
                          child: OutlinedButton.icon(
                            key: const ValueKey<String>('add_word_create_list_button'),
                            onPressed: _handleCreateNewList,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Yeni Liste'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withOpacity(0.3),
                ),
                // İçerik Alanı: Tek parça, akıcı kaydırılabilir görünüm
                Expanded(
                  child: _buildBody(theme, colorScheme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              'Anlamlar ve örnek cümleler getiriliyor...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 40,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => _performSearch(_searchController.text),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.translate_rounded,
                size: 44,
                color: colorScheme.primary.withAlpha(170),
              ),
              const SizedBox(height: 14),
              Text(
                'İngilizce kelime arayın',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Yukarıdaki arama çubuğuna bir kelime yazın; anlamlarını, eş ve zıt anlamlarını tek dokunuşla seçip listenize kaydedin.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (detail.isMisspelled) {
      return DidYouMeanCard(
        misspelledWord: detail.word,
        suggestions: detail.suggestions,
        onSelectSuggestion: (suggestion) {
          _searchController.text = suggestion;
          _searchController.selection = TextSelection.collapsed(
            offset: suggestion.length,
          );
          _performSearch(suggestion, dismissKeyboard: true);
        },
        onReportMissingWord: () => _handleReportMissingWord(detail.word),
        isReportingMissing: _isReportingMissing,
        hasReportedMissing:
            _reportedMissingWords.contains(detail.word.toLowerCase()),
      );
    }

    final isExisting = _matchedExistingWord != null;
    final totalMeanings = detail.meanings.length;
    final displayedCount = _showAllMeanings
        ? totalMeanings
        : (totalMeanings > 6 ? 6 : totalMeanings);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1) Kelime Başlığı, Telaffuz & Ses
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      detail.word,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (detail.lexiconInfo != null &&
                        detail.lexiconInfo!.hasAnyIpa)
                      WordIpaBadge(lexiconInfo: detail.lexiconInfo, compact: true),
                  ],
                ),
              ),
              if (widget.ttsService != null)
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    onPressed: () => _handleSpeak(
                      detail.word,
                      TtsSpeakingTarget.word,
                    ),
                    icon: Icon(
                      Icons.volume_up_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    tooltip: 'Kelimeyi Dinle',
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),

          if (isExisting) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withAlpha(140),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 15,
                    color: colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Listede kayıtlı • mevcut anlamlar seçili getirildi',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // 2) Bölüm 1: Türkçe Anlamlar Başlığı & Butonlar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Türkçe Anlamlar',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _selectedIndices.isNotEmpty
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_selectedIndices.length}/$totalMeanings seçili',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _selectedIndices.isNotEmpty
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_selectedIndices.isNotEmpty)
                    TextButton(
                      onPressed: _clearAllSelections,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Temizle', style: TextStyle(fontSize: 12)),
                    ),
                  TextButton.icon(
                    onPressed: _showAddCustomMeaningDialog,
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Anlam Ekle', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Akıllı Anlam Hapları (Wrap Chips)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < displayedCount; i++)
                _buildMeaningChip(
                  theme: theme,
                  colorScheme: colorScheme,
                  index: i,
                  entry: detail.meanings[i],
                  isSelected: _selectedIndices.contains(i),
                ),
            ],
          ),

          if (totalMeanings > 6) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _showAllMeanings = !_showAllMeanings),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _showAllMeanings
                          ? 'Daha Az Anlam Göster'
                          : 'Diğer ${totalMeanings - 6} Anlamı Göster',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _showAllMeanings
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 3) Bölüm 2: Eş & Zıt Anlamlar (WordRelationsSection)
          if (detail.lexiconInfo != null && detail.lexiconInfo!.hasRelations) ...[
            const SizedBox(height: 18),
            WordRelationsSection(
              synonyms: detail.lexiconInfo!.synonyms,
              antonyms: detail.lexiconInfo!.antonyms,
              selectedSynonyms: _selectedSynonyms,
              selectedAntonyms: _selectedAntonyms,
              onToggleSynonym: (term) {
                setState(() {
                  if (!_selectedSynonyms.remove(term)) {
                    _selectedSynonyms.add(term);
                  }
                });
              },
              onToggleAntonym: (term) {
                setState(() {
                  if (!_selectedAntonyms.remove(term)) {
                    _selectedAntonyms.add(term);
                  }
                });
              },
              onToggleAll: (selectAll) {
                setState(() {
                  _selectedSynonyms.clear();
                  _selectedAntonyms.clear();
                  if (selectAll) {
                    _selectedSynonyms.addAll(detail.lexiconInfo!.synonyms);
                    _selectedAntonyms.addAll(detail.lexiconInfo!.antonyms);
                  }
                });
              },
            ),
          ],

          // 4) Bölüm 3: Örnek Cümleler
          if (detail.examples.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Örnek Cümleler (${detail.examples.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < detail.examples.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _buildExampleSentenceCard(
                theme,
                colorScheme,
                i,
                detail.examples[i],
                detail.word,
              ),
            ],
          ] else if (_isLoadingExamples) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withAlpha(70),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Örnek cümleler yükleniyor...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMeaningChip({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required int index,
    required MeaningEntry entry,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleMeaningSelection(index),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHigh.withOpacity(0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withAlpha(120),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_rounded : Icons.add_rounded,
                size: 15,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  entry.translation,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                  ),
                ),
              ),
              if (entry.partOfSpeech != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withOpacity(0.2)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.partOfSpeech!.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExampleSentenceCard(
    ThemeData theme,
    ColorScheme colorScheme,
    int index,
    WordExampleSentence example,
    String word,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(140),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSecondaryContainer,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HighlightedSentenceText(
                  sentence: example.english,
                  highlightWord: word,
                  baseStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                  highlightColor: colorScheme.primary,
                ),
                if (example.turkish != null && example.turkish!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    example.turkish!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
                WordExampleSourceBadge(source: example.source),
              ],
            ),
          ),
          if (widget.ttsService != null)
            IconButton(
              onPressed: () => _handleSpeak(
                example.english,
                TtsSpeakingTarget.sentence,
              ),
              icon: Icon(
                Icons.volume_up_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Cümleyi Dinle',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
        ],
      ),
    );
  }
}

/// Örnek cümle içinde aranan İngilizce kelimeyi kalın ve vurgulu gösterir.
class _HighlightedSentenceText extends StatelessWidget {
  const _HighlightedSentenceText({
    required this.sentence,
    required this.highlightWord,
    required this.baseStyle,
    required this.highlightColor,
  });

  final String sentence;
  final String highlightWord;
  final TextStyle? baseStyle;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    final escaped = RegExp.escape(highlightWord.trim());
    if (escaped.isEmpty) {
      return Text(sentence, style: baseStyle);
    }

    final regex = RegExp(escaped, caseSensitive: false);
    final matches = regex.allMatches(sentence).toList();
    if (matches.isEmpty) {
      return Text(sentence, style: baseStyle);
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: sentence.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: sentence.substring(match.start, match.end),
          style: baseStyle?.copyWith(
            fontWeight: FontWeight.w700,
            color: highlightColor,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(cursor)));
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}

/// Kullanıcının aranan kelime için kendi özel anlamını ve türünü
/// (noun, verb, adjective, adverb, phrase vb.) seçerek ekleyebildiği pencere.
class _CustomMeaningDialog extends StatefulWidget {
  const _CustomMeaningDialog({
    required this.word,
    required this.initialPartOfSpeech,
  });

  final String word;
  final WordPartOfSpeech? initialPartOfSpeech;

  @override
  State<_CustomMeaningDialog> createState() => _CustomMeaningDialogState();
}

class _CustomMeaningDialogState extends State<_CustomMeaningDialog> {
  final TextEditingController _meaningController = TextEditingController();
  WordPartOfSpeech? _selectedPos;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedPos = widget.initialPartOfSpeech;
  }

  @override
  void dispose() {
    _meaningController.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _meaningController.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorText = 'Lütfen bir anlam yazın.');
      return;
    }

    Navigator.of(context).pop(
      MeaningEntry(
        translation: trimmed,
        partOfSpeech: _selectedPos,
        isContextual: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentText = _meaningController.text.trim();
    final preview = currentText.isNotEmpty
        ? MeaningEntry(
            translation: currentText,
            partOfSpeech: _selectedPos,
          ).baseFormatted
        : null;

    return AlertDialog(
      title: Text(
        '"${widget.word}" için anlam ekle',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _meaningController,
              autofocus: true,
              autocorrect: true,
              enableSuggestions: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                setState(() {
                  if (_errorText != null) _errorText = null;
                });
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Anlam',
                hintText: 'Örn: koşmak, çalıştırmak, yürütmek',
                errorText: _errorText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Kelime Türü',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: WordPartOfSpeech.values.map((pos) {
                final isSelected = _selectedPos == pos;
                return ChoiceChip(
                  label: Text(pos.label),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedPos = selected ? pos : null;
                    });
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            if (preview != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(150),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        preview,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
