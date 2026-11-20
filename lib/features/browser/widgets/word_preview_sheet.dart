import 'package:flutter/material.dart';

import '../../../core/tts/tts_service.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/services/word_translation_service.dart';
import '../../words/models/saved_word.dart';
import '../../words/models/word_list.dart';

/// Seçilen kelimeyi, sesli dinleme (kelime ve bağlam cümlesi) kontrollerini,
/// 1. sırada bağlamdaki anlam (`(cümledeki anlam)` etiketli) ve 2–4. sıralarda
/// en sık kullanılan diğer anlamlarla birlikte gösteren, kullanıcının
/// sürükleyerek yüksekliğini rahatça ayarlayabildiği alt panel.
class WordPreviewSheet extends StatefulWidget {
  const WordPreviewSheet({
    super.key,
    required this.word,
    required this.translationService,
    required this.wordLists,
    required this.onAddWord,
    this.contextSentence,
    this.ttsService,
  });

  final String word;
  final String? contextSentence;
  final WordTranslationService translationService;
  final List<WordList> wordLists;
  final TtsService? ttsService;
  final void Function(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
    String? listName,
  ) onAddWord;

  static Future<void> show(
    BuildContext context, {
    required String word,
    required WordTranslationService translationService,
    required List<WordList> wordLists,
    required void Function(
      String word,
      String meaning,
      List<MeaningEntry> meanings,
      int? listId,
      String? listName,
    ) onAddWord,
    String? contextSentence,
    TtsService? ttsService,
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
          wordLists: wordLists,
          ttsService: ttsService,
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
        );
      },
    );
  }

  @override
  State<WordPreviewSheet> createState() => _WordPreviewSheetState();
}

class _WordPreviewSheetState extends State<WordPreviewSheet> {
  WordMeaning? _meaning;
  String? _errorMessage;
  bool _isLoading = true;
  int? _selectedListId;

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
    _resolveTtsService().clearError(notify: false);
    _selectedListId = _resolveInitialListId();
    _fetchMeaning();
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
    if (widget.wordLists.isEmpty) return null;
    for (final list in widget.wordLists) {
      if (list.isDefault) return list.id;
    }
    return widget.wordLists.first.id;
  }

  WordList? _findSelectedList() {
    if (_selectedListId == null) return null;
    for (final list in widget.wordLists) {
      if (list.id == _selectedListId) return list;
    }
    return null;
  }

  Future<void> _fetchMeaning() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Anlam getirilirken beklenmeyen bir sorun oluştu.';
        _isLoading = false;
      });
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

  void _handleAddPressed() {
    _resolveTtsService().stop();
    final meaningToSave =
        _meaning?.formattedMeaning ?? SavedWord.defaultPlaceholderMeaning;
    final allMeanings = _meaning?.orderedEntries ?? const <MeaningEntry>[];
    final selectedList = _findSelectedList();
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
                      if (widget.wordLists.isNotEmpty) ...[
                        _buildListSelector(theme),
                        const SizedBox(height: 10),
                      ],
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _handleAddPressed,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                        label: const Text('Kelimelerime Ekle'),
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
        if (_hasContextSentence) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
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

  Widget _buildListSelector(ThemeData theme) {
    return DropdownButtonFormField<int>(
      value: _selectedListId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Liste Seç',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      items: widget.wordLists.map((list) {
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
                'Bağlama göre anlamlar getiriliyor...',
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
            label: const Text('Tekrar Dene'),
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
