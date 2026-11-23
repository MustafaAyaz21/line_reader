import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/display_preferences_controller.dart';
import '../../../core/tts/tts_service.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/screens/auth_screen.dart';
import '../../translation/models/word_lexicon_info.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/services/word_lexicon_service.dart';
import '../../translation/services/word_translation_service.dart';
import '../../words/data/word_repository.dart';
import '../../words/models/saved_word.dart';
import '../../words/models/word_list.dart';
import '../../words/widgets/word_lexicon_widgets.dart';
import '../../words/widgets/word_list_editor_dialog.dart';

/// Seçilen kelimeyi, sesli dinleme (kelime ve bağlam cümlesi) kontrollerini,
/// 1. sırada bağlamdaki anlam (`(cümledeki anlam)` etiketli) ve 2–4. sıralarda
/// en sık kullanılan diğer anlamlarla birlikte gösteren, kullanıcının
/// sürükleyerek yüksekliğini rahatça ayarlayabildiği alt panel.
class WordPreviewSheet extends StatefulWidget {
  const WordPreviewSheet({
    super.key,
    required this.word,
    required this.translationService,
    this.lexiconService,
    this.wordLists = const <WordList>[],
    this.loadWordLists,
    this.onCreateWordList,
    required this.onAddWord,
    this.onAddWordWithLexicon,
    this.contextSentence,
    this.ttsService,
    this.authController,
  });

  final String word;
  final String? contextSentence;
  final WordTranslationService translationService;
  final WordLexiconService? lexiconService;
  final List<WordList> wordLists;
  final Future<List<WordList>> Function()? loadWordLists;
  final CreateWordListCallback? onCreateWordList;
  final TtsService? ttsService;
  final AuthController? authController;
  final void Function(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
    String? listName,
  ) onAddWord;
  final void Function(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
    String? listName,
    WordLexiconInfo? selectedLexicon,
  )? onAddWordWithLexicon;

  static Future<void> show(
    BuildContext context, {
    required String word,
    required WordTranslationService translationService,
    WordLexiconService? lexiconService,
    List<WordList> wordLists = const <WordList>[],
    Future<List<WordList>> Function()? loadWordLists,
    CreateWordListCallback? onCreateWordList,
    required void Function(
      String word,
      String meaning,
      List<MeaningEntry> meanings,
      int? listId,
      String? listName,
    ) onAddWord,
    void Function(
      String word,
      String meaning,
      List<MeaningEntry> meanings,
      int? listId,
      String? listName,
      WordLexiconInfo? selectedLexicon,
    )? onAddWordWithLexicon,
    String? contextSentence,
    TtsService? ttsService,
    AuthController? authController,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return WordPreviewSheet(
          word: word,
          contextSentence: contextSentence,
          translationService: translationService,
          lexiconService: lexiconService,
          wordLists: wordLists,
          loadWordLists: loadWordLists,
          onCreateWordList: onCreateWordList,
          ttsService: ttsService,
          authController: authController,
          onAddWord: (
            selectedWord,
            selectedMeaning,
            meanings,
            listId,
            listName,
          ) {
            Navigator.of(sheetContext).pop();
            onAddWord(
              selectedWord,
              selectedMeaning,
              meanings,
              listId,
              listName,
            );
          },
          onAddWordWithLexicon: onAddWordWithLexicon == null
              ? null
              : (
                  selectedWord,
                  selectedMeaning,
                  meanings,
                  listId,
                  listName,
                  selectedLexicon,
                ) {
                  Navigator.of(sheetContext).pop();
                  onAddWordWithLexicon(
                    selectedWord,
                    selectedMeaning,
                    meanings,
                    listId,
                    listName,
                    selectedLexicon,
                  );
                },
        );
      },
    );
  }

  @override
  State<WordPreviewSheet> createState() => _WordPreviewSheetState();
}

class _WordPreviewSheetState extends State<WordPreviewSheet> {
  WordMeaning? _meaning;
  WordLexiconInfo? _lexiconInfo;
  final Set<String> _selectedSynonyms = <String>{};
  final Set<String> _selectedAntonyms = <String>{};
  String? _errorMessage;
  TranslationErrorType? _errorType;
  bool _isLoading = true;
  int? _selectedListId;
  late List<WordList> _wordLists;

  TtsService? _ttsService;
  bool _ownsTtsService = false;

  bool get _hasContextSentence {
    final sentence = widget.contextSentence?.trim();
    return sentence != null && sentence.isNotEmpty;
  }

  TtsService _resolveTtsService() {
    final existing = _ttsService;
    if (existing != null) return existing;

    final provided = widget.ttsService;
    if (provided != null) {
      _ttsService = provided;
      _ownsTtsService = false;
      return provided;
    }

    final created = TtsService();
    _ttsService = created;
    _ownsTtsService = true;
    return created;
  }

  @override
  void initState() {
    super.initState();
    _wordLists = List<WordList>.from(widget.wordLists);
    _resolveTtsService().clearError(notify: false);
    _selectedListId = _resolveInitialListId();
    _loadWordListsAsync();
    _fetchMeaning();
    _fetchLexiconAsync();
  }

  Future<void> _fetchLexiconAsync() async {
    try {
      final service = widget.lexiconService ?? WordLexiconService.shared;
      final info = await service.lookup(widget.word);
      if (!mounted || info == null) return;
      setState(() {
        _lexiconInfo = info;
        _selectedSynonyms
          ..clear()
          ..addAll(info.synonyms);
        _selectedAntonyms
          ..clear()
          ..addAll(info.antonyms);
      });
    } catch (_) {}
  }

  Future<void> _loadWordListsAsync() async {
    final loader = widget.loadWordLists;
    if (loader == null) return;
    try {
      final loaded = await loader();
      if (!mounted || loaded.isEmpty) return;
      setState(() {
        _wordLists = loaded;
        _selectedListId ??= _resolveInitialListId();
      });
    } catch (_) {
      // Liste yüklenemezse varsayılan Favoriler ile devam et.
    }
  }

  @override
  void dispose() {
    final tts = _ttsService;
    if (tts != null) {
      tts.stop(notify: false);
      tts.clearError(notify: false);
      if (_ownsTtsService) {
        tts.dispose();
      }
    }
    super.dispose();
  }

  int? _resolveInitialListId() {
    if (_wordLists.isEmpty) return null;
    for (final list in _wordLists) {
      if (list.isDefault) return list.id;
    }
    return _wordLists.first.id;
  }

  WordList? _findSelectedList() {
    if (_selectedListId == null) return null;
    for (final list in _wordLists) {
      if (list.id == _selectedListId) return list;
    }
    return null;
  }

  Future<void> _fetchMeaning() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorType = null;
    });

    try {
      final result = await widget.translationService.lookup(
        word: widget.word,
        contextSentence: widget.contextSentence,
      );
      if (!mounted) return;
      setState(() {
        _meaning = result;
        _isLoading = false;
      });
    } on TranslationException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _errorType = error.type;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = context.l10n.t(
          'Anlam getirilirken beklenmeyen bir sorun oluştu.',
          'An unexpected error occurred while fetching meanings.',
        );
        _errorType = TranslationErrorType.unknown;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleOpenAuthForQuota() async {
    final authController = widget.authController;
    if (authController == null) return;
    final signedIn = await AuthScreen.show(
      context,
      controller: authController,
      initialSignUpTab: true,
    );
    if (signedIn == true && mounted) {
      await _fetchMeaning();
    }
  }

  Future<void> _handleRedeemCodeForQuota() async {
    final authController = widget.authController;
    if (authController == null) return;
    final s = context.l10n;
    final codeCtrl = TextEditingController();

    final enteredCode = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(s.redeemCodeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                s.t(
                  'Aktivasyon kodunuzu girerek sınırsız kelime çevirisi, tarayıcı AI ve reklamsız kullanımı hemen etkinleştirebilirsiniz.',
                  'Enter your activation code to unlock unlimited translations, Browser AI, and ad-free reading.',
                ),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: s.redeemCodeHint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (value) =>
                    Navigator.of(dialogContext).pop(value.trim()),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(codeCtrl.text.trim()),
              child: Text(s.redeemCodeApply),
            ),
          ],
        );
      },
    );
    codeCtrl.dispose();

    if (enteredCode == null || enteredCode.isEmpty || !mounted) return;

    final result = await authController.redeemAccessCode(enteredCode);
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );

    if (result.isSuccess) {
      await _fetchMeaning();
    }
  }

  Future<void> _handleSpeakWord() async {
    await _resolveTtsService().toggleSpeak(
      text: widget.word,
      target: TtsSpeakingTarget.word,
    );
  }

  Future<void> _handleSpeakSentence() async {
    final sentence = widget.contextSentence?.trim();
    if (sentence == null || sentence.isEmpty) return;

    await _resolveTtsService().toggleSpeak(
      text: sentence,
      target: TtsSpeakingTarget.sentence,
    );
  }

  Future<({WordList? list, String? error})> _createListFallback(
    String name,
    int colorValue,
  ) async {
    try {
      final created = await WordRepository(AppDatabase.instance).createList(
        name: name,
        colorValue: colorValue,
      );
      return (list: created, error: null);
    } on FormatException catch (error) {
      return (list: null, error: error.message);
    } catch (_) {
      return (
        list: null,
        error: context.l10n.t(
          'Liste oluşturulurken bir sorun oluştu.',
          'Could not create the word list.',
        ),
      );
    }
  }

  Future<void> _handleCreateNewList() async {
    WordList? createdList;
    final created = await WordListEditorDialog.show(
      context,
      onSubmit: (name, colorValue) async {
        final callback = widget.onCreateWordList;
        final result = callback != null
            ? await callback(name, colorValue)
            : await _createListFallback(name, colorValue);
        if (result.error != null) {
          return result.error;
        }
        createdList = result.list;
        return null;
      },
    );

    if (created != true || !mounted) return;

    List<WordList> updatedLists = List<WordList>.from(_wordLists);
    final loader = widget.loadWordLists;
    if (loader != null) {
      try {
        final reloaded = await loader();
        if (reloaded.isNotEmpty) {
          updatedLists = List<WordList>.from(reloaded);
        }
      } catch (_) {}
    }

    final newlyCreated = createdList;
    if (newlyCreated != null &&
        !updatedLists.any((item) => item.id == newlyCreated.id)) {
      updatedLists.add(newlyCreated);
    }

    if (!mounted) return;
    setState(() {
      _wordLists = updatedLists;
      if (newlyCreated != null) {
        _selectedListId = newlyCreated.id;
      } else if (_wordLists.isNotEmpty) {
        _selectedListId = _wordLists.last.id;
      }
    });

    if (newlyCreated != null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.t(
                '"${newlyCreated.name}" listesi oluşturuldu ve seçildi.',
                '"${newlyCreated.name}" list created and selected.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  void _handleAddPressed() {
    _resolveTtsService().stop();
    final meaningToSave =
        _meaning?.formattedMeaning ?? SavedWord.defaultPlaceholderMeaning;
    final allMeanings = _meaning?.orderedEntries ?? const <MeaningEntry>[];
    final selectedList = _findSelectedList();
    final lexicon = _lexiconInfo;
    final selectedLexicon = lexicon == null
        ? null
        : WordLexiconInfo(
            word: widget.word,
            ipaUs: lexicon.ipaUs,
            ipaUk: lexicon.ipaUk,
            synonyms: lexicon.synonyms
                .where(_selectedSynonyms.contains)
                .toList(growable: false),
            antonyms: lexicon.antonyms
                .where(_selectedAntonyms.contains)
                .toList(growable: false),
          );

    if (widget.onAddWordWithLexicon != null) {
      widget.onAddWordWithLexicon!(
        widget.word,
        meaningToSave,
        allMeanings,
        selectedList?.id,
        selectedList?.name,
        selectedLexicon,
      );
      return;
    }

    widget.onAddWord(
      widget.word,
      meaningToSave,
      allMeanings,
      selectedList?.id,
      selectedList?.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ttsService = _resolveTtsService();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.54,
      minChildSize: 0.30,
      maxChildSize: 0.86,
      snap: true,
      snapSizes: const <double>[0.32, 0.54, 0.82],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    // Sürüklenebilir belirgin üst tutamaç
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: ttsService,
                      builder: (context, _) {
                        return _buildHeaderAndAudioControls(
                          theme: theme,
                          colorScheme: colorScheme,
                          ttsService: ttsService,
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildMeaningsSection(theme, colorScheme),
                    if (_lexiconInfo != null &&
                        _lexiconInfo!.hasRelations) ...<Widget>[
                      ListenableBuilder(
                        listenable: DisplayPreferencesController.shared,
                        builder: (context, _) {
                          final prefs = DisplayPreferencesController.shared;
                          final visibleSyn = prefs.appShowSynonyms
                              ? _lexiconInfo!.synonyms
                              : const <String>[];
                          final visibleAnt = prefs.appShowAntonyms
                              ? _lexiconInfo!.antonyms
                              : const <String>[];
                          if (visibleSyn.isEmpty && visibleAnt.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: WordRelationsSection(
                              synonyms: visibleSyn,
                              antonyms: visibleAnt,
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
                                final info = _lexiconInfo;
                                if (info == null) return;
                                setState(() {
                                  _selectedSynonyms.clear();
                                  _selectedAntonyms.clear();
                                  if (selectAll) {
                                    _selectedSynonyms.addAll(visibleSyn);
                                    _selectedAntonyms.addAll(visibleAnt);
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant,
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildListSelectorRow(theme),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _handleAddPressed,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                        label: Text(
                          context.l10n.t('Kelimelerime Ekle', 'Add to My Words'),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderAndAudioControls({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required TtsService ttsService,
  }) {
    final isWordActive = ttsService.speakingTarget == TtsSpeakingTarget.word;
    final isWordLoading = isWordActive && ttsService.isLoadingAudio;
    final isSentenceActive =
        ttsService.speakingTarget == TtsSpeakingTarget.sentence;
    final isSentenceLoading = isSentenceActive && ttsService.isLoadingAudio;
    final ttsError = ttsService.errorMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.word,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            isWordActive
                ? IconButton.filled(
                    onPressed: _handleSpeakWord,
                    icon: isWordLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.stop_rounded, size: 20),
                    tooltip: isWordLoading ? 'Hazırlanıyor • İptal' : 'Durdur',
                    visualDensity: VisualDensity.compact,
                  )
                : IconButton.filledTonal(
                    onPressed: _handleSpeakWord,
                    icon: const Icon(Icons.volume_up_rounded, size: 20),
                    tooltip: 'Oku',
                    visualDensity: VisualDensity.compact,
                  ),
            const SizedBox(width: 2),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Kapat',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (_hasContextSentence ||
            (_lexiconInfo != null && _lexiconInfo!.hasAnyIpa)) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_hasContextSentence)
                ActionChip(
                  onPressed: _handleSpeakSentence,
                  avatar: isSentenceLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        )
                      : Icon(
                          isSentenceActive
                              ? Icons.stop_circle_outlined
                              : Icons.record_voice_over_outlined,
                          size: 17,
                          color: isSentenceActive
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.primary,
                        ),
                  label: Text(
                    isSentenceLoading
                        ? 'Ses hazırlanıyor...'
                        : (isSentenceActive
                            ? 'Cümle Okunuyor • Durdur'
                            : 'Cümleyi Dinle'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isSentenceActive
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                      fontWeight:
                          isSentenceActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  backgroundColor: isSentenceActive
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerLow,
                  side: BorderSide(
                    color: isSentenceActive
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              if (_lexiconInfo != null && _lexiconInfo!.hasAnyIpa)
                WordIpaBadge(lexiconInfo: _lexiconInfo),
            ],
          ),
        ],
        if (ttsError != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.volume_off_rounded,
                  size: 16,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ttsError,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: ttsService.clearError,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: colorScheme.onErrorContainer,
                  ),
                  tooltip: 'Kapat',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildListSelectorRow(ThemeData theme) {
    final s = context.l10n;
    if (_wordLists.isEmpty) {
      return OutlinedButton.icon(
        key: const ValueKey<String>('sheet_create_word_list_button'),
        onPressed: _handleCreateNewList,
        icon: const Icon(Icons.create_new_folder_outlined, size: 18),
        label: Text(
          s.t('Yeni Kelime Listesi Oluştur', 'Create New Word List'),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildListSelector(theme)),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const ValueKey<String>('sheet_create_word_list_button'),
          onPressed: _handleCreateNewList,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(s.t('Yeni Liste', 'New List')),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListSelector(ThemeData theme) {
    final safeValue =
        _wordLists.any((list) => list.id == _selectedListId)
            ? _selectedListId
            : (_wordLists.isNotEmpty ? _wordLists.first.id : null);

    return DropdownButtonFormField<int>(
      key: const ValueKey<String>('sheet_word_list_dropdown'),
      value: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.l10n.t('Liste Seç', 'Select List'),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      items: _wordLists.map((list) {
        return DropdownMenuItem<int>(
          value: list.id,
          child: Row(
            children: [
              Container(
                width: 6,
                height: 16,
                decoration: BoxDecoration(
                  color: list.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  list.name,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedListId = value);
      },
    );
  }

  Widget _buildMeaningsSection(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.t(
                  'Bağlama göre anlamlar getiriliyor...',
                  'Fetching contextual meanings...',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final meaning = _meaning;
    if (meaning != null) {
      final entries = meaning.orderedEntries;
      final primary = entries.first;
      final others = entries.skip(1).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. anlam: bağlamdaki anlam (her zaman en üstte ve etiketli)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildMeaningRow(
              theme: theme,
              colorScheme: colorScheme,
              number: 1,
              entry: primary,
              highlighted: true,
            ),
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < others.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 14,
                        endIndent: 14,
                        color: colorScheme.outlineVariant,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: _buildMeaningRow(
                        theme: theme,
                        colorScheme: colorScheme,
                        number: i + 2,
                        entry: others[i],
                        highlighted: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    }

    if (_errorType == TranslationErrorType.guestLimitReached) {
      final s = context.l10n;
      final isStandardUser = (widget.authController?.isAuthenticated ?? false) &&
          !(widget.authController?.isUnlimited ?? false);
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withAlpha(180),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isStandardUser
                  ? s.standardQuotaReachedMessage(
                      AuthController.standardUserDailyTranslationLimit,
                    )
                  : s.guestQuotaReachedMessage(
                      AuthController.guestDailyTranslationLimit,
                    ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
                height: 1.4,
              ),
            ),
            if (widget.authController != null) ...[
              const SizedBox(height: 10),
              if (isStandardUser)
                FilledButton.icon(
                  key: const ValueKey<String>(
                    'sheet_standard_limit_redeem_button',
                  ),
                  onPressed: _handleRedeemCodeForQuota,
                  icon: const Icon(Icons.vpn_key_rounded, size: 18),
                  label: Text(s.redeemCodeTitle),
                )
              else
                FilledButton.icon(
                  key: const ValueKey<String>(
                    'sheet_guest_limit_signin_button',
                  ),
                  onPressed: _handleOpenAuthForQuota,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text(
                    s.t('Giriş Yap / Kayıt Ol', 'Sign In / Sign Up'),
                  ),
                ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _errorMessage ?? SavedWord.defaultPlaceholderMeaning,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _fetchMeaning,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(context.l10n.retry),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeaningRow({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required int number,
    required MeaningEntry entry,
    required bool highlighted,
  }) {
    final badgeBg =
        highlighted ? colorScheme.primary : colorScheme.outlineVariant;
    final badgeFg =
        highlighted ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    final mainTextColor =
        highlighted ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
    final posColor =
        highlighted ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: badgeBg,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelSmall?.copyWith(
              color: badgeFg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: entry.translation,
                  style: (highlighted
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.bodyLarge)
                      ?.copyWith(
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                    color: mainTextColor,
                  ),
                ),
                if (entry.partOfSpeech != null)
                  TextSpan(
                    text: ' (${entry.partOfSpeech!.label})',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: posColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (entry.isContextual)
                  TextSpan(
                    text: ' ${MeaningEntry.contextualTag}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
