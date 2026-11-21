import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/settings/api_key_controller.dart';
import '../../../core/tts/tts_service.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/services/word_translation_service.dart';
import '../controllers/words_controller.dart';
import '../models/saved_word.dart';
import '../models/word_list.dart';
import '../models/word_search_detail.dart';
import '../services/word_dictionary_search_service.dart';

/// Kelime listesi içindeki `+` butonundan açılan manuel kelime arama,
/// 10–15 anlam arasından çoklu seçim (tik ✓) ve 3 kısa örnek cümle ekranı.
class AddWordSearchScreen extends StatefulWidget {
  const AddWordSearchScreen({
    super.key,
    required this.listId,
    required this.controller,
    this.wordList,
    this.apiKeyController,
    this.ttsService,
  });

  final int listId;
  final WordsController controller;
  final WordList? wordList;
  final ApiKeyController? apiKeyController;
  final TtsService? ttsService;

  @override
  State<AddWordSearchScreen> createState() => _AddWordSearchScreenState();
}

class _AddWordSearchScreenState extends State<AddWordSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final WordDictionarySearchService _searchService;
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  WordSearchDetail? _detail;
  final Set<int> _selectedIndices = <int>{};

  @override
  void initState() {
    super.initState();
    _searchService = WordDictionarySearchService(
      geminiApiKeyProvider: () => widget.apiKeyController?.apiKey,
      shouldAttemptGeminiProvider: () =>
          widget.apiKeyController?.shouldAttemptGemini ?? false,
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchService.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounceTimer?.cancel();

    final trimmed = value.trim();
    if (trimmed.length < 2) return;

    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_searchController.text.trim() == trimmed &&
          _detail?.word != trimmed.toLowerCase()) {
        _performSearch(trimmed, dismissKeyboard: false);
      }
    });
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _detail = null;
      _selectedIndices.clear();
    });

    try {
      final result = await _searchService.searchWord(query);
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _detail = result;
        _isLoading = false;
      });
    } on TranslationException catch (error) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _errorMessage =
            'Kelime aranırken bir sorun oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.';
        _isLoading = false;
      });
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

  Future<void> _handleSaveSelected() async {
    if (_isSaving) return;

    final detail = _detail;
    if (detail == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Önce bir kelime arayıp anlam seçin.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Lütfen kaydetmek için en az bir anlam seçin.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    final sortedIndices = _selectedIndices.toList()..sort();
    final selectedMeanings = <MeaningEntry>[
      for (final idx in sortedIndices)
        detail.meanings[idx].copyWith(isContextual: false),
    ];

    setState(() => _isSaving = true);
    try {
      final status = await widget.controller.addWord(
        word: detail.word,
        meaning: selectedMeanings.first.baseFormatted,
        meanings: selectedMeanings,
        listId: widget.listId,
      );

      if (!mounted) return;

      if (status == SaveWordStatus.saved) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() => _isSaving = false);
      final feedback = status == SaveWordStatus.alreadyExists
          ? '"${detail.word}" zaten bu listede kayıtlı.'
          : 'Kelime kaydedilirken bir sorun oluştu.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(feedback),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Kelime kaydedilirken beklenmeyen bir sorun oluştu.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
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
    final list = widget.wordList ?? widget.controller.findListById(widget.listId);
    final selectedCount = _selectedIndices.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (list != null) ...[
              Container(
                width: 8,
                height: 20,
                decoration: BoxDecoration(
                  color: list.color,
                  borderRadius: BorderRadius.circular(4),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _isSaving ? null : _handleSaveSelected,
        tooltip: 'Seçilen Anlamlarla Kaydet',
        child: _isSaving
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colorScheme.onPrimaryContainer,
                ),
              )
            : Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.add_rounded, size: 28),
                  if (selectedCount > 0)
                    Positioned(
                      right: -12,
                      top: -12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '$selectedCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst Arama Çubuğu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    autocorrect: true,
                    enableSuggestions: true,
                    onChanged: _onSearchChanged,
                    onSubmitted: (value) => _performSearch(value),
                    decoration: InputDecoration(
                      hintText: 'İngilizce kelime yazın (örn. run, insight)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _debounceTimer?.cancel();
                                _searchController.clear();
                                setState(() {
                                  _detail = null;
                                  _errorMessage = null;
                                  _selectedIndices.clear();
                                });
                                _searchFocusNode.requestFocus();
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: 'Temizle',
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isLoading
                      ? null
                      : () => _performSearch(_searchController.text),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Ara'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          // İçerik Alanı: Yükleniyor / Hata / Boş / İkiye Bölünmüş Düzen
          Expanded(
            child: _buildBody(theme, colorScheme),
          ),
        ],
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
                'Üstteki arama çubuğuna bir kelime yazın; 10–15 farklı anlam arasından istediklerinizi tikleyip sağ alttaki + butonuyla listenize kaydedin.',
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

    // İkiye Bölünmüş Düzen:
    // - Üst Bölüm (flex: 6): 10–15 Anlam Seçimi (tikli kutucuklar)
    // - Alt Bölüm (flex: 4): 3 Kısa Örnek Cümle
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ÜST BÖLÜM: Anlam Seçimi
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
                color: colorScheme.surfaceContainerLowest,
                child: Row(
                  children: [
                    Text(
                      detail.word,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                    if (widget.ttsService != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () =>
                            _handleSpeak(detail.word, TtsSpeakingTarget.word),
                        icon: Icon(
                          Icons.volume_up_rounded,
                          size: 19,
                          color: colorScheme.primary,
                        ),
                        tooltip: 'Kelimeyi Dinle',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedIndices.isNotEmpty
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_selectedIndices.length}/${detail.meanings.length} seçili',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _selectedIndices.isNotEmpty
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: detail.meanings.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 52,
                    color: colorScheme.outlineVariant.withAlpha(140),
                  ),
                  itemBuilder: (context, index) {
                    final entry = detail.meanings[index];
                    final isChecked = _selectedIndices.contains(index);

                    return Material(
                      color: isChecked
                          ? colorScheme.primaryContainer.withAlpha(110)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => _toggleMeaningSelection(index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: isChecked
                                        ? colorScheme.primary
                                        : colorScheme.outline,
                                    width: 1.8,
                                  ),
                                ),
                                child: isChecked
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: colorScheme.onPrimary,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: entry.translation,
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: isChecked
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      if (entry.partOfSpeech != null)
                                        TextSpan(
                                          text:
                                              '  (${entry.partOfSpeech!.label})',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: isChecked
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
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
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // İki bölüm arasındaki belirgin ayırıcı
        Divider(
          height: 2,
          thickness: 2,
          color: colorScheme.outlineVariant,
        ),
        // ALT BÖLÜM: 3 Kısa Örnek Cümle
        Expanded(
          flex: 4,
          child: Container(
            color: colorScheme.surfaceContainerLowest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.format_quote_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Örnek Cümleler',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 84),
                    itemCount: detail.examples.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final example = detail.examples[index];
                      return Container(
                        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withAlpha(160),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.only(top: 1),
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
                                    highlightWord: detail.word,
                                    baseStyle:
                                        theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface,
                                      height: 1.35,
                                    ),
                                    highlightColor: colorScheme.primary,
                                  ),
                                  if (example.turkish != null &&
                                      example.turkish!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      example.turkish!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
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
                                  minWidth: 30,
                                  minHeight: 30,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
