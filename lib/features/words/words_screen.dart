import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_locale.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/web_back_bridge.dart';
import '../../core/settings/api_key_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/tts/tts_service.dart';
import '../../core/widgets/line_loading_indicator.dart';
import '../../core/widgets/line_refresh_indicator.dart';
import '../auth/controllers/auth_controller.dart';
import '../settings/widgets/api_key_dialog.dart';
import '../settings/widgets/settings_action_button.dart';
import '../translation/models/word_meaning.dart';
import '../translation/services/word_translation_service.dart';
import '../update/controllers/app_update_controller.dart';
import '../update/widgets/update_action_button.dart';
import 'controllers/words_controller.dart';
import 'learning/screens/word_learning_hub_screen.dart';
import 'list_words_screen.dart';
import 'models/saved_word.dart';
import 'models/word_list.dart';
import 'models/word_search_detail.dart';
import 'services/word_dictionary_search_service.dart';
import 'widgets/word_lexicon_widgets.dart';
import 'widgets/word_list_card.dart';
import 'widgets/word_list_editor_dialog.dart';

/// Dış kaynaklardan (örneğin Android "Line Reader ile arat" aksiyonundan)
/// Kelime Listeleri ekranındaki üst "Kelime Ara" alanına otomatik arama
/// tetiklemek için kullanılan hafif denetleyici.
class WordsSearchTriggerController extends ChangeNotifier {
  String? _pendingQuery;
  bool Function()? _backHandler;

  String? get pendingQuery => _pendingQuery;

  void attachBackHandler(bool Function()? handler) {
    _backHandler = handler;
  }

  /// Arama paneli açıksa kapatır ve `true` döner; kapalıysa `false` döner.
  bool handleSystemBack() {
    return _backHandler?.call() ?? false;
  }

  void triggerSearch(String rawQuery) {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) return;
    _pendingQuery = trimmed;
    notifyListeners();
  }

  String? consumePendingQuery() {
    final value = _pendingQuery;
    _pendingQuery = null;
    return value;
  }
}

enum _InlineExistingWordAction {
  overwrite,
  addAsNew,
}

/// Kullanıcının varsayılan "Favoriler" listesini ve özel kelime listelerini
/// yönetebildiği, üst kısımdan doğrudan kelime aratıp istediği listeye
/// ekleyebildiği "Kelimelerim" sekmesi.
class WordsScreen extends StatefulWidget {
  const WordsScreen({
    super.key,
    required this.controller,
    this.apiKeyController,
    this.localeController,
    this.authController,
    this.updateController,
    this.ttsService,
    this.onClearCache,
    this.searchTriggerController,
    this.searchService,
  });

  final WordsController controller;
  final ApiKeyController? apiKeyController;
  final AppLocaleController? localeController;
  final AuthController? authController;
  final AppUpdateController? updateController;
  final TtsService? ttsService;
  final Future<void> Function()? onClearCache;
  final WordsSearchTriggerController? searchTriggerController;
  final WordDictionarySearchService? searchService;

  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final WordDictionarySearchService _searchService;
  late final bool _ownsSearchService;

  int _searchGeneration = 0;
  Timer? _suggestDebounce;
  int _suggestGeneration = 0;
  List<WordPrefixSuggestion> _prefixSuggestions = const <WordPrefixSuggestion>[];
  final Set<String> _reportedMissingWords = <String>{};
  bool _isReportingMissing = false;
  bool _isSearchingWord = false;
  bool _isSavingWord = false;
  String? _searchError;
  WordSearchDetail? _searchDetail;
  SavedWord? _matchedExistingWord;
  int? _selectedTargetListId;
  final Set<int> _selectedMeaningIndices = <int>{};
  final Set<String> _selectedSynonyms = <String>{};
  final Set<String> _selectedAntonyms = <String>{};
  TtsService? _fallbackTtsService;
  Object? _searchHistoryToken;

  TtsService _resolveTtsService() {
    return widget.ttsService ?? (_fallbackTtsService ??= TtsService());
  }

  void _openLearningHub() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WordLearningHubScreen(
          controller: widget.controller,
          ttsService: _resolveTtsService(),
        ),
      ),
    );
  }

  bool get _isSearchPanelOpen =>
      _isSearchingWord || _searchDetail != null || _searchError != null;

  @override
  void initState() {
    super.initState();
    _ownsSearchService = widget.searchService == null;
    _searchService = widget.searchService ??
        WordDictionarySearchService(
          geminiApiKeyProvider: null,
          shouldAttemptGeminiProvider: () => false,
        );
    widget.searchTriggerController?.addListener(_handleExternalSearchTrigger);
    widget.searchTriggerController?.attachBackHandler(_handleBackFromHost);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _consumePendingExternalSearch();
      }
    });
  }

  @override
  void didUpdateWidget(covariant WordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchTriggerController != widget.searchTriggerController) {
      oldWidget.searchTriggerController
          ?.removeListener(_handleExternalSearchTrigger);
      oldWidget.searchTriggerController?.attachBackHandler(null);
      widget.searchTriggerController?.addListener(_handleExternalSearchTrigger);
      widget.searchTriggerController?.attachBackHandler(_handleBackFromHost);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _consumePendingExternalSearch();
        }
      });
    }
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    widget.searchTriggerController?.removeListener(_handleExternalSearchTrigger);
    widget.searchTriggerController?.attachBackHandler(null);
    _searchController.dispose();
    _searchFocusNode.dispose();
    if (_ownsSearchService) {
      _searchService.dispose();
    }
    _fallbackTtsService?.dispose();
    super.dispose();
  }

  bool _handleBackFromHost() {
    if (!mounted || !_isSearchPanelOpen) return false;
    _clearTopSearch();
    return true;
  }

  void _handleExternalSearchTrigger() {
    if (!mounted) return;
    _consumePendingExternalSearch();
  }

  void _consumePendingExternalSearch() {
    final query = widget.searchTriggerController?.consumePendingQuery();
    if (query == null || query.trim().isEmpty) return;
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );
    _performTopSearch(query, dismissKeyboard: true);
  }

  String _normalizeKey(String raw) {
    return raw.trim().replaceAll('İ', 'i').toLowerCase();
  }

  int? _resolveTargetListId(List<WordList> lists) {
    if (lists.isEmpty) return null;
    final current = _selectedTargetListId;
    if (current != null && lists.any((item) => item.id == current)) {
      return current;
    }
    final def = widget.controller.defaultList;
    return def?.id ?? lists.first.id;
  }

  void _clearTopSearch({bool keepText = false}) {
    final token = _searchHistoryToken;
    _searchHistoryToken = null;
    WebBackBridge.shared.popEntrySilently(token);
    _suggestDebounce?.cancel();
    _suggestGeneration++;
    _searchGeneration++;
    if (!keepText) {
      _searchController.clear();
    }
    _searchFocusNode.unfocus();
    setState(() {
      _prefixSuggestions = const <WordPrefixSuggestion>[];
      _isSearchingWord = false;
      _isSavingWord = false;
      _searchError = null;
      _searchDetail = null;
      _matchedExistingWord = null;
      _selectedMeaningIndices.clear();
      _selectedSynonyms.clear();
      _selectedAntonyms.clear();
    });
  }

  void _onTopSearchChanged(String value) {
    setState(() {});
    _suggestDebounce?.cancel();
    final trimmed = value.trim().toLowerCase();
    if (trimmed.length < 2 || !RegExp(r'^[a-z]+$').hasMatch(trimmed)) {
      if (_prefixSuggestions.isNotEmpty) {
        setState(() => _prefixSuggestions = const <WordPrefixSuggestion>[]);
      }
      return;
    }

    final gen = ++_suggestGeneration;
    _suggestDebounce = Timer(const Duration(milliseconds: 260), () async {
      final list = await _searchService.fetchPrefixSuggestions(trimmed);
      if (!mounted || gen != _suggestGeneration) return;
      if (_searchController.text.trim().toLowerCase() != trimmed) return;
      setState(() => _prefixSuggestions = list);
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
    _showSnack(
      ok
          ? context.l10n.t(
              '"$key" eksik kelime olarak bildirildi. Teşekkürler!',
              '"$key" has been reported as a missing word. Thank you!',
            )
          : context.l10n.t(
              'Bildirim gönderilemedi, lütfen bağlantınızı kontrol edin.',
              'Could not send report, please check your connection.',
            ),
    );
  }

  Future<void> _performTopSearch(
    String rawQuery, {
    bool dismissKeyboard = true,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      _showSnack(
        context.l10n.t(
          'Lütfen aramak istediğiniz İngilizce kelimeyi yazın.',
          'Please enter an English word to search.',
        ),
      );
      return;
    }

    if (dismissKeyboard) {
      _searchFocusNode.unfocus();
    }

    // Listeler henüz yüklenmediyse paralel olarak yükle.
    if (widget.controller.lists.isEmpty && !widget.controller.isLoading) {
      await widget.controller.loadLists();
    }
    if (!mounted) return;

    final targetListId = _resolveTargetListId(widget.controller.lists);
    final myGen = ++_searchGeneration;
    _suggestDebounce?.cancel();
    _suggestGeneration++;

    if (kIsWeb && _searchHistoryToken == null) {
      _searchHistoryToken = WebBackBridge.shared.pushEntry(
        hash: '#/words/search',
        onBack: () {
          if (mounted && _isSearchPanelOpen) {
            _searchHistoryToken = null;
            _clearTopSearch();
          }
        },
      );
    }

    setState(() {
      _prefixSuggestions = const <WordPrefixSuggestion>[];
      _selectedTargetListId = targetListId;
      _isSearchingWord = true;
      _searchError = null;
      _searchDetail = null;
      _matchedExistingWord = null;
      _selectedMeaningIndices.clear();
      _selectedSynonyms.clear();
      _selectedAntonyms.clear();
    });

    try {
      final existingFuture = targetListId != null
          ? widget.controller.findExistingWordsInList(
              listId: targetListId,
              word: query,
            )
          : Future<List<SavedWord>>.value(const <SavedWord>[]);

      final results = await Future.wait<Object?>(<Future<Object?>>[
        _searchService.searchWord(query),
        existingFuture,
      ]);
      if (!mounted || myGen != _searchGeneration) return;

      final detail = results[0] as WordSearchDetail;
      final existingList = results[1] as List<SavedWord>;
      _applySearchResult(detail, existingList);
    } on TranslationException catch (error) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _searchError = error.message;
        _isSearchingWord = false;
      });
    } catch (_) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _searchError = context.l10n.t(
          'Kelime aranırken bir sorun oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          'Could not look up the word. Please check your connection and try again.',
        );
        _isSearchingWord = false;
      });
    }
  }

  void _applySearchResult(
    WordSearchDetail detail,
    List<SavedWord> existingList,
  ) {
    if (detail.isMisspelled) {
      setState(() {
        _searchDetail = detail;
        _matchedExistingWord = null;
        _selectedMeaningIndices.clear();
        _selectedSynonyms.clear();
        _selectedAntonyms.clear();
        _isSearchingWord = false;
      });
      return;
    }

    final matched = existingList.isNotEmpty ? existingList.first : null;
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

      final fetchedKeys =
          mergedMeanings.map((e) => _normalizeKey(e.translation)).toSet();
      final missing = <MeaningEntry>[];
      for (final savedEntry in savedMeanings) {
        final key = _normalizeKey(savedEntry.translation);
        if (key.isEmpty ||
            savedEntry.translation == SavedWord.defaultPlaceholderMeaning) {
          continue;
        }
        if (!fetchedKeys.contains(key)) {
          missing.add(savedEntry);
          fetchedKeys.add(key);
        }
      }
      if (missing.isNotEmpty) {
        mergedMeanings.insertAll(0, missing);
      }

      for (var i = 0; i < mergedMeanings.length; i++) {
        if (savedKeys.contains(_normalizeKey(mergedMeanings[i].translation))) {
          preselected.add(i);
        }
      }
    } else if (mergedMeanings.isNotEmpty) {
      // Hızlı listeye ekleme akışı için ilk anlamı varsayılan olarak seçili getir.
      preselected.add(0);
    }

    final lexicon = detail.lexiconInfo;
    // Yeni aranan kelimede eş/zıt anlamlılar otomatik seçili gelmez;
    // kullanıcı yalnızca eklemek istediklerine tıklayarak tikler.
    // Daha önce kaydedilmiş bir kelimeyse mevcut seçimler korunur.
    final preselectedSynonyms = <String>{};
    final preselectedAntonyms = <String>{};
    if (matched != null) {
      final savedSynKeys = matched.synonyms.map(_normalizeKey).toSet();
      final savedAntKeys = matched.antonyms.map(_normalizeKey).toSet();
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
      _searchDetail = WordSearchDetail(
        word: detail.word,
        meanings: List<MeaningEntry>.unmodifiable(mergedMeanings),
        examples: detail.examples,
        lexiconInfo: lexicon,
      );
      _matchedExistingWord = matched;
      _selectedMeaningIndices
        ..clear()
        ..addAll(preselected);
      _selectedSynonyms
        ..clear()
        ..addAll(preselectedSynonyms);
      _selectedAntonyms
        ..clear()
        ..addAll(preselectedAntonyms);
      _isSearchingWord = false;
    });
  }

  Future<void> _handleTargetListChanged(int nextListId) async {
    if (nextListId == _selectedTargetListId) return;
    setState(() => _selectedTargetListId = nextListId);

    final detail = _searchDetail;
    if (detail == null) return;

    final existingList = await widget.controller.findExistingWordsInList(
      listId: nextListId,
      word: detail.word,
    );
    if (!mounted ||
        _selectedTargetListId != nextListId ||
        _searchDetail?.word != detail.word) {
      return;
    }

    setState(() {
      _matchedExistingWord =
          existingList.isNotEmpty ? existingList.first : null;
    });
  }

  Future<void> _handleCreateListForSearch() async {
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
      if (!mounted) return;
      _showSnack(
        context.l10n.t(
          '"${newlyCreated.name}" listesi oluşturuldu ve seçildi.',
          '"${newlyCreated.name}" list created and selected.',
        ),
      );
    }
  }

  Future<_InlineExistingWordAction?> _askExistingWordAction(
    String word,
    String listName,
    int selectedCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showModalBottomSheet<_InlineExistingWordAction>(
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
                '"$word" "$listName" listesinde zaten kayıtlı',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Seçtiğiniz anlamları mevcut kaydın üzerine güncelleyebilir veya ayrı bir kart olarak ekleyebilirsiniz.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(sheetContext)
                    .pop(_InlineExistingWordAction.overwrite),
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: Text(
                  selectedCount == 0
                      ? 'Üstüne ekle (kayıt kaldırılır)'
                      : 'Üstüne ekle ($selectedCount anlam)',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(sheetContext)
                    .pop(_InlineExistingWordAction.addAsNew),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Yeni kelime olarak ekle'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSaveSearchedWord() async {
    if (_isSavingWord) return;
    final detail = _searchDetail;
    if (detail == null) return;

    final targetListId = _resolveTargetListId(widget.controller.lists);
    final targetList = targetListId != null
        ? widget.controller.findListById(targetListId)
        : widget.controller.defaultList;
    final targetListName = targetList?.name ?? 'Favoriler';

    final sortedIndices = _selectedMeaningIndices.toList()..sort();
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

    final existing = _matchedExistingWord;

    if (existing == null) {
      if (selectedMeanings.isEmpty) {
        _showSnack('Lütfen kaydetmek için en az bir anlam seçin.');
        return;
      }

      setState(() => _isSavingWord = true);
      try {
        final status = await widget.controller.addWord(
          word: detail.word,
          meaning: selectedMeanings.first.baseFormatted,
          meanings: selectedMeanings,
          ipaUs: lexicon?.ipaUs,
          ipaUk: lexicon?.ipaUk,
          synonyms: chosenSynonyms,
          antonyms: chosenAntonyms,
          listId: targetList?.id,
          allowDuplicate: true,
        );
        if (!mounted) return;
        if (status == SaveWordStatus.saved) {
          _clearTopSearch();
          _showSnack('"${detail.word}" "$targetListName" listesine eklendi.');
          return;
        }
        setState(() => _isSavingWord = false);
        _showSnack('Kelime kaydedilirken bir sorun oluştu.');
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSavingWord = false);
        _showSnack('Kelime kaydedilirken beklenmeyen bir sorun oluştu.');
      }
      return;
    }

    final action = await _askExistingWordAction(
      detail.word,
      targetListName,
      selectedMeanings.length,
    );
    if (action == null || !mounted) return;

    if (action == _InlineExistingWordAction.addAsNew) {
      if (selectedMeanings.isEmpty) {
        _showSnack('Yeni kelime olarak eklemek için en az bir anlam seçin.');
        return;
      }
      setState(() => _isSavingWord = true);
      try {
        final status = await widget.controller.addWord(
          word: detail.word,
          meaning: selectedMeanings.first.baseFormatted,
          meanings: selectedMeanings,
          ipaUs: lexicon?.ipaUs,
          ipaUk: lexicon?.ipaUk,
          synonyms: chosenSynonyms,
          antonyms: chosenAntonyms,
          listId: targetList?.id,
          allowDuplicate: true,
        );
        if (!mounted) return;
        if (status == SaveWordStatus.saved) {
          _clearTopSearch();
          _showSnack(
            '"${detail.word}" "$targetListName" listesine yeni kayıt olarak eklendi.',
          );
          return;
        }
        setState(() => _isSavingWord = false);
        _showSnack('Kelime kaydedilirken bir sorun oluştu.');
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSavingWord = false);
        _showSnack('Kelime kaydedilirken beklenmeyen bir sorun oluştu.');
      }
      return;
    }

    setState(() => _isSavingWord = true);
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
        _clearTopSearch();
        _showSnack(
          selectedMeanings.isEmpty
              ? '"${detail.word}" "$targetListName" listesinden kaldırıldı.'
              : '"${detail.word}" "$targetListName" listesinde güncellendi.',
        );
        return;
      }
      setState(() => _isSavingWord = false);
      _showSnack('Kelime güncellenirken bir sorun oluştu.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSavingWord = false);
      _showSnack('Kelime güncellenirken beklenmeyen bir sorun oluştu.');
    }
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

  Future<void> _handleCreateList(BuildContext context) async {
    final created = await WordListEditorDialog.show(
      context,
      onSubmit: (name, colorValue, icon) {
        return widget.controller.createList(
          name: name,
          colorValue: colorValue,
          icon: icon,
        );
      },
    );
    if (created == true && context.mounted) {
      _showSnack('Yeni kelime listesi oluşturuldu.');
    }
  }

  Future<void> _handleEditList(BuildContext context, WordList list) async {
    final updated = await WordListEditorDialog.show(
      context,
      existingList: list,
      onSubmit: (name, colorValue, icon) {
        return widget.controller.updateList(
          list: list,
          name: name,
          colorValue: colorValue,
          icon: icon,
        );
      },
    );
    if (updated == true && context.mounted) {
      _showSnack('Liste güncellendi.');
    }
  }

  Future<void> _handleDeleteList(BuildContext context, WordList list) async {
    if (list.isDefault) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Listeyi Sil'),
        content: Text(
          '"${list.name}" listesini ve içindeki ${list.wordCount} kelimeyi silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await widget.controller.deleteList(list.id);

    if (context.mounted) {
      _showSnack('"${list.name}" listesi silindi.');
    }
  }

  void _openList(BuildContext context, WordList list) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListWordsScreen(
          listId: list.id,
          controller: widget.controller,
          apiKeyController: widget.apiKeyController,
          ttsService: widget.ttsService,
        ),
      ),
    );
  }

  Future<void> _handleSpeak(String text, TtsSpeakingTarget target) async {
    final tts = widget.ttsService;
    if (tts == null || text.trim().isEmpty) return;
    await tts.toggleSpeak(text: text, target: target);
  }

  Widget _buildTopSearchBar(ThemeData theme, ColorScheme colorScheme, bool isWideScreen) {
    final s = context.l10n;
    final isDark = theme.brightness == Brightness.dark;

    final searchField = Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey<String>('words_top_search_field'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              autocorrect: true,
              enableSuggestions: true,
              onChanged: _onTopSearchChanged,
              onSubmitted: (value) => _performTopSearch(value),
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: s.t(
                  'Kelime Ara (örn. resilient, make)...',
                  'Search Word (e.g. resilient, make)...',
                ),
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withAlpha(160),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty || _isSearchPanelOpen)
            IconButton(
              key: const ValueKey<String>('words_top_search_clear_button'),
              onPressed: _clearTopSearch,
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: s.t('Temizle', 'Clear'),
            ),
        ],
      ),
    );

    final searchButton = FilledButton(
      key: const ValueKey<String>('words_top_search_button'),
      onPressed: _isSearchingWord
          ? null
          : () => _performTopSearch(_searchController.text),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Text(s.t('Ara', 'Search')),
    );

    final suggestionsBox = (!_isSearchPanelOpen && _prefixSuggestions.isNotEmpty)
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: WordPrefixSuggestionsList(
              suggestions: _prefixSuggestions,
              onSelectWord: (word) {
                _searchController.text = word;
                _searchController.selection = TextSelection.collapsed(
                  offset: word.length,
                );
                _performTopSearch(word, dismissKeyboard: true);
              },
            ),
          )
        : const SizedBox.shrink();

    if (isWideScreen) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 10),
                    searchButton,
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _handleCreateList(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(s.t('Yeni Liste', 'New List')),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
                suggestionsBox,
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 8),
              searchButton,
            ],
          ),
          suggestionsBox,
        ],
      ),
    );
  }

  Widget _buildInlineSearchPanel(
    ThemeData theme,
    ColorScheme colorScheme,
    List<WordList> lists,
  ) {
    final s = context.l10n;

    if (_isSearchingWord) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              s.t(
                'Anlamlar ve örnek cümleler getiriliyor...',
                'Fetching meanings and example sentences...',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 40,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                _searchError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _performTopSearch(_searchController.text),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(s.retry),
                  ),
                  OutlinedButton(
                    onPressed: _clearTopSearch,
                    child: Text(s.t('Listelere Dön', 'Back to Lists')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final detail = _searchDetail;
    if (detail == null) {
      return const SizedBox.shrink();
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
          _performTopSearch(suggestion, dismissKeyboard: true);
        },
        onReportMissingWord: () => _handleReportMissingWord(detail.word),
        isReportingMissing: _isReportingMissing,
        hasReportedMissing:
            _reportedMissingWords.contains(detail.word.toLowerCase()),
      );
    }

    final resolvedTargetId = _resolveTargetListId(lists);
    final targetList = resolvedTargetId != null
        ? widget.controller.findListById(resolvedTargetId)
        : null;
    final targetListName = targetList?.name ?? 'Favoriler';
    final selectedCount = _selectedMeaningIndices.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hedef Liste Seçici + Yeni Liste Butonu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              if (lists.isNotEmpty) ...[
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey<String>('words_search_list_dropdown'),
                    value: resolvedTargetId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: s.t('Eklenecek Liste', 'Target List'),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: lists.map((list) {
                      return DropdownMenuItem<int>(
                        value: list.id,
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 15,
                              decoration: BoxDecoration(
                                color: list.color,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                list.name,
                                overflow: TextOverflow.ellipsis,
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
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                key: const ValueKey<String>('words_search_create_list_button'),
                onPressed: _handleCreateListForSearch,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(s.t('Yeni Liste', 'New List')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        // Anlamlar ve Örnek Cümleler
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            detail.word,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.ttsService != null)
                          IconButton(
                            onPressed: () => _handleSpeak(
                              detail.word,
                              TtsSpeakingTarget.word,
                            ),
                            icon: Icon(
                              Icons.volume_up_rounded,
                              size: 19,
                              color: colorScheme.primary,
                            ),
                            tooltip: s.t('Kelimeyi Dinle', 'Listen'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: selectedCount > 0
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$selectedCount/${detail.meanings.length} seçili',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selectedCount > 0
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _clearTopSearch,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(s.t('Listelere Dön', 'Lists')),
                  ),
                ],
              ),
              if (detail.lexiconInfo != null &&
                  detail.lexiconInfo!.hasAnyIpa) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: WordIpaBadge(lexiconInfo: detail.lexiconInfo),
                ),
              ],
              if (_matchedExistingWord != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withAlpha(150),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '"$targetListName" listesinde zaten kayıtlı • mevcut anlamlar seçili getirildi.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ...List<Widget>.generate(detail.meanings.length, (index) {
                final entry = detail.meanings[index];
                final isChecked = _selectedMeaningIndices.contains(index);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: isChecked
                        ? colorScheme.primaryContainer.withAlpha(120)
                        : colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (isChecked) {
                            _selectedMeaningIndices.remove(index);
                          } else {
                            _selectedMeaningIndices.add(index);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isChecked
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 21,
                              color: isChecked
                                  ? colorScheme.primary
                                  : colorScheme.outline,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: entry.translation,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        fontWeight: isChecked
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                    if (entry.partOfSpeech != null)
                                      TextSpan(
                                        text: ' (${entry.partOfSpeech!.label})',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (detail.lexiconInfo != null &&
                  detail.lexiconInfo!.hasRelations) ...[
                const SizedBox(height: 6),
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
                    final info = detail.lexiconInfo;
                    if (info == null) return;
                    setState(() {
                      _selectedSynonyms.clear();
                      _selectedAntonyms.clear();
                      if (selectAll) {
                        _selectedSynonyms.addAll(info.synonyms);
                        _selectedAntonyms.addAll(info.antonyms);
                      }
                    });
                  },
                ),
              ],
              if (detail.examples.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  s.t('Örnek Cümleler', 'Example Sentences'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final example in detail.examples)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withAlpha(150),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          example.english,
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (example.turkish != null &&
                            example.turkish!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            example.turkish!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        WordExampleSourceBadge(source: example.source),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        // Alt Kaydetme Çubuğu
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: FilledButton.icon(
            key: const ValueKey<String>('words_search_save_button'),
            onPressed: _isSavingWord ? null : _handleSaveSearchedWord,
            icon: _isSavingWord
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.bookmark_add_outlined, size: 20),
            label: Text(
              s.t(
                '"$targetListName" Listesine Ekle',
                'Add to "$targetListName"',
              ),
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visuals = AppThemeVisuals.of(context);
    final isWideScreen = MediaQuery.of(context).size.width >= 840;

    return Scaffold(
      backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
      appBar: isWideScreen
          ? null
          : AppBar(
              title: Text(s.myWordsTitle),
              actions: [
                IconButton(
                  onPressed: _openLearningHub,
                  icon: const Icon(Icons.school_outlined),
                  tooltip: 'Öğrenme Alanı',
                ),
                if (!kIsWeb && widget.updateController != null)
                  UpdateActionButton(controller: widget.updateController!),
                if (widget.apiKeyController != null &&
                    widget.localeController != null &&
                    widget.authController != null) ...[
                  SettingsActionButton(
                    apiKeyController: widget.apiKeyController!,
                    localeController: widget.localeController!,
                    authController: widget.authController!,
                    onClearCache: widget.onClearCache,
                  ),
                  const SizedBox(width: 4),
                ] else if (widget.apiKeyController != null) ...[
                  ApiKeyActionButton(
                    controller: widget.apiKeyController!,
                    onClearCache: widget.onClearCache,
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
      floatingActionButton: isWideScreen || _isSearchPanelOpen
          ? null
          : FloatingActionButton(
              onPressed: () => _handleCreateList(context),
              tooltip: s.t('Yeni Liste Oluştur', 'Create New List'),
              child: const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        top: isWideScreen,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final lists = widget.controller.lists;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopSearchBar(theme, colorScheme, isWideScreen),
                // "o çizgileri kaldır oradaki" - Removed divider line
                Expanded(
                  child: _isSearchPanelOpen
                      ? _buildInlineSearchPanel(theme, colorScheme, lists)
                      : _buildListsBody(context, lists, isWideScreen),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildListsBody(
    BuildContext context,
    List<WordList> lists,
    bool isWideScreen,
  ) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.controller.isLoading && lists.isEmpty) {
      return const Center(
        child: LineLoadingIndicator(message: 'Listeler yükleniyor...'),
      );
    }

    if (widget.controller.errorMessage != null && lists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.controller.errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: widget.controller.loadLists,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    final totalWords = lists.fold<int>(0, (sum, l) => sum + l.wordCount);

    final listView = ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 88),
      itemCount: lists.length,
      itemBuilder: (context, index) {
        final list = lists[index];
        return WordListCard(
          list: list,
          onTap: () => _openList(context, list),
          onEdit: () => _handleEditList(context, list),
          onDelete:
              list.isDefault ? null : () => _handleDeleteList(context, list),
        );
      },
    );

    if (isWideScreen) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Text(
                      s.myWordsTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${lists.length} liste • $totalWords kelime',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: _openLearningHub,
                      icon: const Icon(Icons.school_outlined, size: 18),
                      label: const Text('Öğrenme Alanı'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LineRefreshIndicator(
                  onRefresh: widget.controller.loadLists,
                  child: listView,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LineRefreshIndicator(
      onRefresh: widget.controller.loadLists,
      child: listView,
    );
  }
}
