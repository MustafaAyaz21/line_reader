import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/localization/app_locale.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/lookup_overlay_channel.dart';
import '../../core/platform/process_text_channel.dart';
import '../../core/settings/display_preferences_controller.dart';
import '../../core/settings/ipa_accent_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_theme_controller.dart';
import '../../core/tts/tts_service.dart';
import '../../core/utils/word_sanitizer.dart';
import '../articles/models/article.dart';
import '../articles/services/article_passage_translation_service.dart';
import '../translation/data/translation_cache_repository.dart';
import '../translation/models/word_lexicon_info.dart';
import '../translation/models/word_meaning.dart';
import '../translation/services/cached_translation_service.dart';
import '../translation/services/word_lexicon_service.dart';
import '../translation/services/word_translation_service.dart';
import '../words/controllers/words_controller.dart';
import '../words/data/word_repository.dart';
import '../words/models/saved_word.dart';
import '../words/models/word_list.dart';
import '../words/widgets/word_lexicon_widgets.dart';
import '../words/widgets/word_list_editor_dialog.dart';

/// Başka bir uygulamada kelime veya cümle seçilip "Line'da Bak" seçildiğinde
/// arkadaki uygulamanın üzerinde şeffaf arka planla açılan hafif mini kart.
class QuickLookupOverlayApp extends StatefulWidget {
  const QuickLookupOverlayApp({
    super.key,
    this.initialText,
    this.translationService,
    this.lexiconService,
    this.passageTranslator,
    this.wordsController,
    this.ttsService,
    this.localeController,
    this.onClose,
    this.onOpenInMainApp,
  });

  final String? initialText;
  final WordTranslationService? translationService;
  final WordLexiconService? lexiconService;
  final ArticlePassageTranslator? passageTranslator;
  final WordsController? wordsController;
  final TtsService? ttsService;
  final AppLocaleController? localeController;
  final Future<void> Function()? onClose;
  final Future<void> Function(String word)? onOpenInMainApp;

  @override
  State<QuickLookupOverlayApp> createState() => _QuickLookupOverlayAppState();
}

class _QuickLookupOverlayAppState extends State<QuickLookupOverlayApp> {
  late final AppLocaleController _localeController;
  late final bool _ownsLocaleController;

  @override
  void initState() {
    super.initState();
    _ownsLocaleController = widget.localeController == null;
    _localeController = widget.localeController ?? (AppLocaleController()..load());
    IpaAccentController.shared.load();
    DisplayPreferencesController.shared.load(force: true);
    AppThemeController.shared.load();
  }

  @override
  void dispose() {
    if (_ownsLocaleController) {
      _localeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLocaleScope(
      controller: _localeController,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          _localeController,
          AppThemeController.shared,
          DisplayPreferencesController.shared,
        ]),
        builder: (context, _) {
          final preset = AppThemeController.shared.preset;
          return MaterialApp(
            title: "Line'da Bak",
            debugShowCheckedModeBanner: false,
            theme: AppTheme.forPreset(
              preset,
              classicBrightness: Brightness.light,
            ).copyWith(
              scaffoldBackgroundColor: Colors.transparent,
            ),
            darkTheme: AppTheme.forPreset(
              preset,
              classicBrightness: Brightness.dark,
            ).copyWith(
              scaffoldBackgroundColor: Colors.transparent,
            ),
            themeMode: preset.themeMode,
            home: _QuickLookupOverlayScreen(
              initialText: widget.initialText,
              translationService: widget.translationService,
              lexiconService: widget.lexiconService,
              passageTranslator: widget.passageTranslator,
              wordsController: widget.wordsController,
              ttsService: widget.ttsService,
              onClose: widget.onClose,
              onOpenInMainApp: widget.onOpenInMainApp,
            ),
          );
        },
      ),
    );
  }
}

class _QuickLookupOverlayScreen extends StatefulWidget {
  const _QuickLookupOverlayScreen({
    this.initialText,
    this.translationService,
    this.lexiconService,
    this.passageTranslator,
    this.wordsController,
    this.ttsService,
    this.onClose,
    this.onOpenInMainApp,
  });

  final String? initialText;
  final WordTranslationService? translationService;
  final WordLexiconService? lexiconService;
  final ArticlePassageTranslator? passageTranslator;
  final WordsController? wordsController;
  final TtsService? ttsService;
  final Future<void> Function()? onClose;
  final Future<void> Function(String word)? onOpenInMainApp;

  @override
  State<_QuickLookupOverlayScreen> createState() =>
      _QuickLookupOverlayScreenState();
}

class _QuickLookupOverlayScreenState extends State<_QuickLookupOverlayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _backdropOpacity;
  late final Animation<Offset> _cardOffset;

  late final WordTranslationService _translationService;
  late final bool _ownsTranslationService;
  late final ArticlePassageTranslator _passageTranslator;
  late final bool _ownsPassageTranslator;
  late final WordsController _wordsController;
  late final bool _ownsWordsController;
  late final TtsService _ttsService;
  late final bool _ownsTtsService;

  String _queryText = '';
  bool _isPassageMode = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _savedJustNow = false;
  String? _statusMessage;
  String? _errorMessage;
  WordMeaning? _wordMeaning;
  WordLexiconInfo? _lexiconInfo;
  final Set<String> _selectedSynonyms = <String>{};
  final Set<String> _selectedAntonyms = <String>{};
  String? _passageTranslation;
  int? _selectedListId;
  int _lookupGeneration = 0;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _backdropOpacity = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );
    _cardOffset = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOutCubic,
      ),
    );
    _entryController.forward();

    _ownsTranslationService = widget.translationService == null;
    _translationService = widget.translationService ??
        CachedTranslationService(
          cacheRepository: TranslationCacheRepository(AppDatabase.instance),
          geminiApiKeyProvider: null,
          shouldAttemptGeminiProvider: () => false,
        );

    _ownsPassageTranslator = widget.passageTranslator == null;
    _passageTranslator =
        widget.passageTranslator ?? ArticlePassageTranslationService();

    _ownsWordsController = widget.wordsController == null;
    _wordsController = widget.wordsController ??
        WordsController(WordRepository(AppDatabase.instance));

    _ownsTtsService = widget.ttsService == null;
    _ttsService = widget.ttsService ??
        TtsService(
          geminiApiKeyProvider: () => null,
          shouldUseGeminiProvider: () => false,
        );

    LookupOverlayChannel.setOnLookupTextListener(_handleNewLookupText);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _loadWordLists();

    final provided = widget.initialText?.trim();
    String? resolved;
    if (provided != null && provided.isNotEmpty) {
      resolved = ProcessTextChannel.sanitizeExternalQuery(provided) ?? provided;
    } else {
      resolved = await LookupOverlayChannel.getLookupText();
    }

    if (!mounted) return;
    if (resolved == null || resolved.trim().isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = context.l10n.t(
          'Seçili metin alınamadı. Lütfen bir kelime seçip tekrar deneyin.',
          'Could not read the selected text. Please select a word and try again.',
        );
      });
      return;
    }

    await _startLookup(resolved);
  }

  Future<void> _loadWordLists() async {
    try {
      final lists = await _wordsController.loadLists();
      if (!mounted || lists.isEmpty) return;
      setState(() {
        _selectedListId ??= _resolveDefaultListId(lists);
      });
    } catch (_) {}
  }

  int? _resolveDefaultListId(List<WordList> lists) {
    if (lists.isEmpty) return null;
    for (final item in lists) {
      if (item.isDefault) return item.id;
    }
    return lists.first.id;
  }

  void _handleNewLookupText(String nextText) {
    if (!mounted) return;
    _startLookup(nextText);
  }

  bool _shouldUsePassageMode(String text) {
    final tokens = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.length > 3) return true;
    if (tokens.length >= 2 && RegExp(r'[.!?;:,\n]').hasMatch(text)) {
      return true;
    }
    return WordSanitizer.clean(text) == null;
  }

  Future<void> _startLookup(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    final myGen = ++_lookupGeneration;
    final isPassage = _shouldUsePassageMode(text);
    final displayText =
        isPassage ? text : (WordSanitizer.clean(text) ?? text);

    setState(() {
      _queryText = displayText;
      _isPassageMode = isPassage;
      _isLoading = true;
      _savedJustNow = false;
      _statusMessage = null;
      _errorMessage = null;
      _wordMeaning = null;
      _lexiconInfo = null;
      _selectedSynonyms.clear();
      _selectedAntonyms.clear();
      _passageTranslation = null;
    });

    if (!isPassage) {
      _fetchLexiconForWord(displayText, myGen);
    }

    try {
      if (isPassage) {
        final result = await _passageTranslator.translate(
          article: const Article(
            id: 'quick_lookup_overlay',
            title: 'Quick Lookup',
            level: 'B1',
            content: '',
          ),
          selectedText: displayText,
        );
        if (!mounted || myGen != _lookupGeneration) return;
        setState(() {
          _passageTranslation = result.translatedText;
          _isLoading = false;
        });
      } else {
        final meaning = await _translationService.lookup(word: displayText);
        if (!mounted || myGen != _lookupGeneration) return;
        setState(() {
          _wordMeaning = meaning;
          _isLoading = false;
        });
      }
    } on PassageTranslationException catch (error) {
      if (!mounted || myGen != _lookupGeneration) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } on TranslationException catch (error) {
      if (!mounted || myGen != _lookupGeneration) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || myGen != _lookupGeneration) return;
      setState(() {
        _errorMessage = context.l10n.t(
          'Anlam getirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          'Could not fetch translation. Please check your connection and try again.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchLexiconForWord(String word, int generation) async {
    try {
      final service = widget.lexiconService ?? WordLexiconService.shared;
      final info = await service.lookup(word);
      if (!mounted || generation != _lookupGeneration || info == null) return;
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

  Future<void> _closeOverlay() async {
    _ttsService.stop(notify: false);
    if (widget.onClose != null) {
      await widget.onClose!();
      return;
    }
    await LookupOverlayChannel.closeOverlay();
  }

  Future<void> _openInMainApp() async {
    _ttsService.stop(notify: false);
    final word = _queryText.trim();
    if (widget.onOpenInMainApp != null) {
      await widget.onOpenInMainApp!(word);
      return;
    }
    await LookupOverlayChannel.openInMainApp(word);
  }

  Future<void> _handleSpeak() async {
    if (_queryText.trim().isEmpty) return;
    await _ttsService.toggleSpeak(
      text: _queryText,
      target:
          _isPassageMode ? TtsSpeakingTarget.sentence : TtsSpeakingTarget.word,
    );
  }

  Future<void> _handleCreateNewList() async {
    WordList? createdList;
    final created = await WordListEditorDialog.show(
      context,
      onSubmit: (name, colorValue) async {
        final result = await _wordsController.createListWithResult(
          name: name,
          colorValue: colorValue,
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
      setState(() {
        _selectedListId = newlyCreated.id;
        _savedJustNow = false;
        _statusMessage = context.l10n.t(
          '"${newlyCreated.name}" listesi oluşturuldu ve seçildi.',
          '"${newlyCreated.name}" list created and selected.',
        );
      });
    }
  }

  Future<void> _handleSaveWord() async {
    if (_isSaving || _queryText.trim().isEmpty) return;

    final lists = _wordsController.lists;
    final targetId = _selectedListId ?? _resolveDefaultListId(lists);
    final targetList =
        targetId != null ? _wordsController.findListById(targetId) : null;
    final targetName = targetList?.name ?? 'Favoriler';

    final meaningText =
        _wordMeaning?.formattedMeaning ?? SavedWord.defaultPlaceholderMeaning;
    final entries = _wordMeaning?.orderedEntries ?? const <MeaningEntry>[];

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    try {
      final lexicon = _lexiconInfo;
      final chosenSyn = lexicon == null
          ? const <String>[]
          : lexicon.synonyms
              .where(_selectedSynonyms.contains)
              .toList(growable: false);
      final chosenAnt = lexicon == null
          ? const <String>[]
          : lexicon.antonyms
              .where(_selectedAntonyms.contains)
              .toList(growable: false);

      final status = await _wordsController.addWord(
        word: _queryText,
        meaning: meaningText,
        meanings: entries,
        ipaUs: lexicon?.ipaUs,
        ipaUk: lexicon?.ipaUk,
        synonyms: chosenSyn,
        antonyms: chosenAnt,
        listId: targetList?.id,
      );
      if (!mounted) return;

      final feedback = switch (status) {
        SaveWordStatus.saved =>
          '"$_queryText" "$targetName" listesine kaydedildi.',
        SaveWordStatus.alreadyExists =>
          '"$_queryText" zaten "$targetName" listesinde.',
        SaveWordStatus.error => 'Kelime kaydedilirken bir sorun oluştu.',
      };

      setState(() {
        _isSaving = false;
        _savedJustNow = status == SaveWordStatus.saved ||
            status == SaveWordStatus.alreadyExists;
        _statusMessage = feedback;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _statusMessage = 'Kelime kaydedilirken bir sorun oluştu.';
      });
    }
  }

  @override
  void dispose() {
    LookupOverlayChannel.setOnLookupTextListener(null);
    _entryController.dispose();
    _ttsService.stop(notify: false);
    if (_ownsTtsService) {
      _ttsService.dispose();
    }
    if (_ownsTranslationService) {
      _translationService.dispose();
    }
    if (_ownsPassageTranslator) {
      _passageTranslator.dispose();
    }
    if (_ownsWordsController) {
      _wordsController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxCardHeight = MediaQuery.sizeOf(context).height * 0.74;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closeOverlay();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Arkadaki uygulamayı görünür bırakan yumuşak karartma — dışına
            // dokunulduğunda mini kartı anında kapatır.
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey<String>('quick_lookup_backdrop'),
                behavior: HitTestBehavior.opaque,
                onTap: _closeOverlay,
                child: FadeTransition(
                  opacity: _backdropOpacity,
                  child: Container(
                    color: Colors.black.withAlpha(110),
                  ),
                ),
              ),
            ),
            // Alt yüzen mini kart
            Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: _cardOffset,
                child: FadeTransition(
                  opacity: _backdropOpacity,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 520,
                          maxHeight: maxCardHeight,
                        ),
                        child: Material(
                          key: const ValueKey<String>('quick_lookup_card'),
                          color: colorScheme.surface,
                          elevation: 16,
                          shadowColor: Colors.black45,
                          borderRadius: BorderRadius.circular(24),
                          clipBehavior: Clip.antiAlias,
                          child: ListenableBuilder(
                            listenable: Listenable.merge(<Listenable>[
                              _wordsController,
                              _ttsService,
                            ]),
                            builder: (context, _) {
                              return _buildCardContent(theme, colorScheme);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardContent(ThemeData theme, ColorScheme colorScheme) {
    final s = context.l10n;
    final lists = _wordsController.lists;
    final resolvedListId =
        lists.any((item) => item.id == _selectedListId)
            ? _selectedListId
            : _resolveDefaultListId(lists);
    final isSpeaking = _ttsService.speakingTarget != TtsSpeakingTarget.none;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Üst tutamaç + Line'da Bak etiketi + Kapat
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_stories_rounded,
                          size: 13,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          "Line'da Bak",
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_queryText.isNotEmpty &&
                      DisplayPreferencesController.shared.overlayShowTts)
                    IconButton.filledTonal(
                      key: const ValueKey<String>('quick_lookup_tts_button'),
                      onPressed: _handleSpeak,
                      icon: Icon(
                        isSpeaking
                            ? Icons.stop_rounded
                            : Icons.volume_up_rounded,
                        size: 19,
                      ),
                      tooltip: isSpeaking ? 'Durdur' : 'Dinle',
                      visualDensity: VisualDensity.compact,
                    ),
                  const SizedBox(width: 2),
                  IconButton(
                    key: const ValueKey<String>('quick_lookup_close_button'),
                    onPressed: _closeOverlay,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: s.t('Kapat', 'Close'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (_queryText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      _queryText,
                      style: (_isPassageMode
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleLarge)
                          ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: _isPassageMode ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!_isPassageMode &&
                        _lexiconInfo != null &&
                        _lexiconInfo!.hasAnyIpa)
                      WordIpaBadge(
                        lexiconInfo: _lexiconInfo,
                        modeOverride:
                            DisplayPreferencesController.shared.overlayIpaMode,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        // Kaydırılabilir anlam / çeviri alanı
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildResultBody(theme, colorScheme),
                if (!_isPassageMode &&
                    _lexiconInfo != null &&
                    _lexiconInfo!.hasRelations) ...<Widget>[
                  ListenableBuilder(
                    listenable: DisplayPreferencesController.shared,
                    builder: (context, _) {
                      final prefs = DisplayPreferencesController.shared;
                      final visibleSyn = prefs.overlayShowSynonyms
                          ? _lexiconInfo!.synonyms
                          : const <String>[];
                      final visibleAnt = prefs.overlayShowAntonyms
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
                              _savedJustNow = false;
                            });
                          },
                          onToggleAntonym: (term) {
                            setState(() {
                              if (!_selectedAntonyms.remove(term)) {
                                _selectedAntonyms.add(term);
                              }
                              _savedJustNow = false;
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
                              _savedJustNow = false;
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
        ),
        if (_statusMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Alt aksiyonlar (kelime modunda: liste seç + yeni liste + ekle + uygulamada aç)
        if (!_isPassageMode &&
            DisplayPreferencesController.shared.overlayShowSaveBar) ...[
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (lists.isNotEmpty) ...[
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: const ValueKey<String>(
                            'quick_lookup_list_dropdown',
                          ),
                          value: resolvedListId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: s.t('Liste Seç', 'Select List'),
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
                            if (value == null) return;
                            setState(() {
                              _selectedListId = value;
                              _savedJustNow = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'quick_lookup_create_list_button',
                      ),
                      onPressed: _handleCreateNewList,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: Text(s.t('Yeni Liste', 'New List')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'quick_lookup_save_button',
                        ),
                        onPressed:
                            (_isLoading || _isSaving) ? null : _handleSaveWord,
                        icon: Icon(
                          _savedJustNow
                              ? Icons.check_rounded
                              : Icons.bookmark_add_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _savedJustNow
                              ? s.t('Kaydedildi', 'Saved')
                              : s.t('Kelimelerime Ekle', 'Add to Words'),
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
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'quick_lookup_open_app_button',
                        ),
                        onPressed: _queryText.isEmpty ? null : _openInMainApp,
                        icon: const Icon(Icons.open_in_new_rounded, size: 17),
                        label: Text(
                          s.t('Detaylı Aç', 'Open App'),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else ...[
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: FilledButton.tonal(
              onPressed: _closeOverlay,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(s.t('Tamam', 'Done')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultBody(ThemeData theme, ColorScheme colorScheme) {
    final s = context.l10n;

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isPassageMode
                    ? s.t('Türkçeye çevriliyor...', 'Translating to Turkish...')
                    : s.t('Anlamlar getiriliyor...', 'Fetching meanings...'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_queryText.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _startLookup(_queryText),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: Text(s.retry),
              ),
            ],
          ],
        ),
      );
    }

    if (_isPassageMode && _passageTranslation != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withAlpha(180),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          _passageTranslation!,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onPrimaryContainer,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final meaning = _wordMeaning;
    if (meaning == null) {
      return const SizedBox.shrink();
    }

    final entries = meaning.orderedEntries;
    final primary = entries.first;
    final others = entries.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _buildMeaningItem(
            theme: theme,
            colorScheme: colorScheme,
            number: 1,
            entry: primary,
            highlighted: true,
          ),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
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
                      vertical: 9,
                    ),
                    child: _buildMeaningItem(
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

  Widget _buildMeaningItem({
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
    final mainColor =
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
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                    color: mainColor,
                  ),
                ),
                if (entry.partOfSpeech != null)
                  TextSpan(
                    text: ' (${entry.partOfSpeech!.label})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: posColor,
                      fontWeight: FontWeight.w500,
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
