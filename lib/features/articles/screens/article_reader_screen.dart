import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/tts/tts_service.dart';
import '../../../core/utils/word_sanitizer.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../browser/browser_screen.dart';
import '../../browser/widgets/word_preview_sheet.dart';
import '../../translation/data/translation_cache_repository.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/services/cached_translation_service.dart';
import '../../translation/services/word_translation_service.dart';
import '../../words/data/word_repository.dart';
import '../../words/models/saved_word.dart';
import '../../words/models/word_list.dart';
import '../data/article_reader_repository.dart';
import '../models/article.dart';
import '../models/article_level.dart';
import '../models/article_reader_models.dart';
import '../utils/article_text_parser.dart';

/// WebView kullanmadan kitap / PDF belgesi temizliğinde yerel okuma deneyimi
/// sunan ekran.
///
/// - Arka plan tonu (`Beyaz`, `Kağıt Tonu`, `Koyu`) yerel olarak kaydedilir.
/// - Font boyutu (`A-` / `A+` ve kaydırıcı) yerel olarak kaydedilir.
/// - Altını çizme kalemi (Underline) aktifken dokunulan kelime veya seçilen
///   metin aralığının altını çizer ve makale bazında SQLite'ta saklar; çizili
///   alana tekrar dokunulduğunda çizgi kaldırılır.
/// - Altını çizme kalemi kapalıyken kelimeye dokunarak veya kısa ifade seçerek
///   mevcut 4 anlamlı çeviri, sesli okuma ve kelime listesine ekleme akışı
///   (`WordPreviewSheet`) açılır.
class ArticleReaderScreen extends StatefulWidget {
  const ArticleReaderScreen({
    super.key,
    required this.article,
    this.readerStore,
    this.translationService,
    this.ttsService,
    this.authController,
    this.onAddWord,
    this.loadWordLists,
  });

  final Article article;
  final ArticleReaderStore? readerStore;
  final WordTranslationService? translationService;
  final TtsService? ttsService;
  final AuthController? authController;
  final AddWordCallback? onAddWord;
  final Future<List<WordList>> Function()? loadWordLists;

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  late final ArticleReaderStore _readerStore;
  late final WordTranslationService _translationService;
  late final bool _ownsTranslationService;
  late final List<String> _paragraphs;

  ArticleReaderPreferences _preferences = ArticleReaderPreferences.defaults;
  List<ArticleUnderline> _underlines = const <ArticleUnderline>[];
  bool _isUnderlineMode = false;
  bool _isWordSheetOpen = false;

  // Paragraf bazlı aktif metin seçimi (çok kelimelik alt çizgi / anlam sorgusu)
  int? _selectedParagraphIndex;
  String _selectedPlainText = '';
  int _selectionRevision = 0;

  @override
  void initState() {
    super.initState();
    _readerStore =
        widget.readerStore ?? ArticleReaderRepository(AppDatabase.instance);
    _ownsTranslationService = widget.translationService == null;
    _translationService = widget.translationService ??
        CachedTranslationService(
          cacheRepository: TranslationCacheRepository(AppDatabase.instance),
        );

    final effectiveBody = widget.article.content.trim().isNotEmpty
        ? widget.article.content
        : widget.article.description;
    _paragraphs = ArticleTextParser.splitParagraphs(effectiveBody);

    _loadInitialReaderData();
  }

  @override
  void dispose() {
    if (_ownsTranslationService) {
      _translationService.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialReaderData() async {
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        _readerStore.loadPreferences(),
        _readerStore.getUnderlinesForArticle(widget.article.id),
      ]);
      if (!mounted) return;
      setState(() {
        _preferences = results[0] as ArticleReaderPreferences;
        _underlines =
            List<ArticleUnderline>.unmodifiable(results[1] as List<ArticleUnderline>);
      });
    } catch (error) {
      debugPrint('[ArticleReaderScreen] Okuma verileri yuklenemedi: $error');
    }
  }

  Future<void> _updatePreferences(ArticleReaderPreferences next) async {
    setState(() {
      _preferences = next;
    });
    try {
      await _readerStore.savePreferences(next);
    } catch (error) {
      debugPrint('[ArticleReaderScreen] Okuma ayari kaydedilemedi: $error');
    }
  }

  Future<void> _persistUnderlines(List<ArticleUnderline> updated) async {
    setState(() {
      _underlines = List<ArticleUnderline>.unmodifiable(updated);
    });
    try {
      await _readerStore.saveUnderlinesForArticle(widget.article.id, updated);
    } catch (error) {
      debugPrint('[ArticleReaderScreen] Alt cizgiler kaydedilemedi: $error');
    }
  }

  void _toggleUnderlineMode() {
    setState(() {
      _isUnderlineMode = !_isUnderlineMode;
      _selectedParagraphIndex = null;
      _selectedPlainText = '';
      _selectionRevision++;
    });
  }

  void _clearActiveSelection() {
    if (_selectedPlainText.isEmpty && _selectedParagraphIndex == null) return;
    setState(() {
      _selectedParagraphIndex = null;
      _selectedPlainText = '';
      _selectionRevision++;
    });
  }

  List<ArticleUnderline> _underlinesForParagraph(int paragraphIndex) {
    return _underlines
        .where((item) => item.paragraphIndex == paragraphIndex)
        .toList(growable: false);
  }

  Future<void> _handleSegmentTap({
    required int paragraphIndex,
    required ArticleRenderSegment segment,
  }) async {
    if (_isUnderlineMode) {
      // Çizili bir alana tekrar dokunulduysa o çizgiyi kaldır.
      final existingUnderline = segment.underline;
      if (existingUnderline != null) {
        final next = _underlines
            .where((item) => !(item.paragraphIndex == existingUnderline.paragraphIndex &&
                item.startOffset == existingUnderline.startOffset &&
                item.endOffset == existingUnderline.endOffset))
            .toList(growable: false);
        await _persistUnderlines(next);
        return;
      }

      // Çizili olmayan bir kelimeye dokunulduysa altını çiz ve kaydet.
      if (!segment.isWord) return;
      final paragraph = _paragraphs[paragraphIndex];
      final next = ArticleTextParser.addAndMergeUnderline(
        existing: _underlines,
        incoming: ArticleUnderline(
          articleId: widget.article.id,
          paragraphIndex: paragraphIndex,
          startOffset: segment.start,
          endOffset: segment.end,
          createdAt: DateTime.now(),
        ),
        paragraphText: paragraph,
      );
      await _persistUnderlines(next);
      return;
    }

    // Kalem kapalıyken kelimeye dokununca anlam önizleme akışını aç.
    if (!segment.isWord) return;
    final cleanedWord = WordSanitizer.clean(segment.text);
    if (cleanedWord == null) return;

    final paragraph = _paragraphs[paragraphIndex];
    final contextSentence = ArticleTextParser.extractContextSentence(
      paragraph,
      segment.start,
    );
    await _openWordMeaningSheet(
      word: cleanedWord,
      contextSentence: contextSentence,
    );
  }

  Future<void> _underlineSelection({
    required int paragraphIndex,
    required String selectedText,
  }) async {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return;
    final paragraph = _paragraphs[paragraphIndex];
    final range = ArticleTextParser.findSelectionRange(paragraph, selectedText);
    if (range == null) return;

    final next = ArticleTextParser.addAndMergeUnderline(
      existing: _underlines,
      incoming: ArticleUnderline(
        articleId: widget.article.id,
        paragraphIndex: paragraphIndex,
        startOffset: range.start,
        endOffset: range.end,
        createdAt: DateTime.now(),
      ),
      paragraphText: paragraph,
    );
    _clearActiveSelection();
    await _persistUnderlines(next);
  }

  Future<void> _removeUnderlineInSelection({
    required int paragraphIndex,
    required String selectedText,
  }) async {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return;
    final paragraph = _paragraphs[paragraphIndex];
    final range = ArticleTextParser.findSelectionRange(paragraph, selectedText);
    if (range == null) return;

    final next = _underlines
        .where((item) => !(item.paragraphIndex == paragraphIndex &&
            item.overlaps(range.start, range.end)))
        .toList(growable: false);
    _clearActiveSelection();
    await _persistUnderlines(next);
  }

  bool _selectionHasUnderline(int paragraphIndex, String selectedText) {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return false;
    final paragraph = _paragraphs[paragraphIndex];
    final range = ArticleTextParser.findSelectionRange(paragraph, selectedText);
    if (range == null) return false;
    return _underlines.any(
      (item) =>
          item.paragraphIndex == paragraphIndex &&
          item.overlaps(range.start, range.end),
    );
  }

  Future<void> _lookupSelectedText({
    required int paragraphIndex,
    required String selectedText,
  }) async {
    final cleaned = WordSanitizer.clean(selectedText);
    if (cleaned == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Anlam görmek için bir kelime veya kısa ifade seçin.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    String? contextSentence;
    if (paragraphIndex >= 0 && paragraphIndex < _paragraphs.length) {
      final paragraph = _paragraphs[paragraphIndex];
      final range = ArticleTextParser.findSelectionRange(paragraph, selectedText);
      contextSentence = ArticleTextParser.extractContextSentence(
        paragraph,
        range?.start ?? 0,
      );
    }

    _clearActiveSelection();
    await _openWordMeaningSheet(
      word: cleaned,
      contextSentence: contextSentence,
    );
  }

  Future<void> _openWordMeaningSheet({
    required String word,
    String? contextSentence,
  }) async {
    if (_isWordSheetOpen || !mounted) return;
    _isWordSheetOpen = true;

    try {
      await WordPreviewSheet.show(
        context,
        word: word,
        contextSentence: contextSentence,
        translationService: _translationService,
        ttsService: widget.ttsService,
        authController: widget.authController,
        loadWordLists: widget.loadWordLists,
        onAddWord: _handleAddWord,
      );
    } finally {
      _isWordSheetOpen = false;
    }
  }

  Future<void> _handleAddWord(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
    String? listName,
  ) async {
    SaveWordStatus status;
    try {
      if (widget.onAddWord != null) {
        status = await widget.onAddWord!(word, meaning, meanings, listId);
      } else {
        final repo = WordRepository(AppDatabase.instance);
        final resolvedListId =
            listId ?? await repo.getDefaultFavoritesListId();
        status = await repo.saveWord(
          listId: resolvedListId,
          word: word,
          meaning: meaning,
          meanings: meanings,
        );
      }
    } catch (error) {
      debugPrint('[ArticleReaderScreen] Kelime ekleme hatasi: $error');
      status = SaveWordStatus.error;
    }

    if (!mounted) return;
    final targetName =
        (listName != null && listName.isNotEmpty) ? listName : 'Favoriler';

    final feedback = switch (status) {
      SaveWordStatus.saved => '"$word" "$targetName" listesine kaydedildi.',
      SaveWordStatus.alreadyExists => '"$word" zaten "$targetName" listesinde.',
      SaveWordStatus.error => 'Kelime kaydedilirken bir sorun oluştu.',
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(feedback),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _openAppearanceSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final currentPrefs = _preferences;

            Future<void> applyPrefs(ArticleReaderPreferences next) async {
              await _updatePreferences(next);
              if (sheetContext.mounted) {
                setModalState(() {});
              }
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.readerAppearanceTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.backgroundToneLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: ArticleReaderTone.values.map((tone) {
                      final isSelected = currentPrefs.tone == tone;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: tone == ArticleReaderTone.values.last ? 0 : 10,
                          ),
                          child: _ToneOptionChip(
                            tone: tone,
                            isSelected: isSelected,
                            onTap: () => applyPrefs(
                              currentPrefs.copyWith(tone: tone),
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: <Widget>[
                      Text(
                        context.l10n.fontSizeLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${currentPrefs.fontSize.round()} pt',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      OutlinedButton(
                        key: const ValueKey<String>('reader_font_decrease'),
                        onPressed:
                            currentPrefs.fontSize > ArticleReaderPreferences.minFontSize
                                ? () => applyPrefs(
                                      currentPrefs.copyWith(
                                        fontSize: currentPrefs.fontSize - 1,
                                      ),
                                    )
                                : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text(
                          'A-',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          key: const ValueKey<String>('reader_font_slider'),
                          value: currentPrefs.fontSize,
                          min: ArticleReaderPreferences.minFontSize,
                          max: ArticleReaderPreferences.maxFontSize,
                          divisions: (ArticleReaderPreferences.maxFontSize -
                                  ArticleReaderPreferences.minFontSize)
                              .round(),
                          onChanged: (value) {
                            applyPrefs(
                              currentPrefs.copyWith(fontSize: value.roundToDouble()),
                            );
                          },
                        ),
                      ),
                      OutlinedButton(
                        key: const ValueKey<String>('reader_font_increase'),
                        onPressed:
                            currentPrefs.fontSize < ArticleReaderPreferences.maxFontSize
                                ? () => applyPrefs(
                                      currentPrefs.copyWith(
                                        fontSize: currentPrefs.fontSize + 1,
                                      ),
                                    )
                                : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text(
                          'A+',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tone = _preferences.tone;
    final parsedLevel = widget.article.parsedLevel;
    final overlayStyle = tone.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final hasFloatingSelection =
        _selectedParagraphIndex != null && _selectedPlainText.trim().isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: tone.backgroundColor,
        appBar: AppBar(
          backgroundColor: tone.backgroundColor,
          foregroundColor: tone.textColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          titleSpacing: 4,
          title: Row(
            children: <Widget>[
              if (parsedLevel != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: parsedLevel.accentColor.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    parsedLevel.code,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: parsedLevel.accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.article.formattedReadingTime,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: tone.secondaryTextColor,
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            // Altını çizme kalemi aç/kapa butonu
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Tooltip(
                message: _isUnderlineMode
                    ? context.l10n.underlinePenActiveTooltip
                    : context.l10n.underlinePenTooltip,
                child: Material(
                  color: _isUnderlineMode
                      ? tone.underlineColor.withAlpha(38)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: const ValueKey<String>('reader_underline_pen_button'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: _toggleUnderlineMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: _isUnderlineMode
                            ? Border.all(
                                color: tone.underlineColor.withAlpha(170),
                                width: 1.2,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.border_color_rounded,
                            size: 20,
                            color: _isUnderlineMode
                                ? tone.underlineColor
                                : tone.textColor,
                          ),
                          if (_isUnderlineMode) ...<Widget>[
                            const SizedBox(width: 5),
                            Text(
                              context.l10n.underlinePenShort,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: tone.underlineColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Görünüm ve yazı boyutu ayarları ("Aa")
            IconButton(
              key: const ValueKey<String>('reader_appearance_button'),
              tooltip: context.l10n.readerAppearanceTooltip,
              onPressed: _openAppearanceSheet,
              icon: Text(
                'Aa',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tone.textColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(_isUnderlineMode ? 36 : 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Divider(height: 1, thickness: 1, color: tone.dividerColor),
                if (_isUnderlineMode)
                  Container(
                    width: double.infinity,
                    color: tone.surfaceColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.edit_rounded,
                          size: 15,
                          color: tone.underlineColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.underlineBannerHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: tone.secondaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        body: Stack(
          children: <Widget>[
            SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  hasFloatingSelection ? 104 : 56,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildDocumentHeader(tone, parsedLevel),
                        const SizedBox(height: 24),
                        if (_paragraphs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'Bu makalenin içeriği henüz eklenmedi.',
                              style: TextStyle(
                                fontSize: _preferences.fontSize,
                                height: 1.75,
                                color: tone.secondaryTextColor,
                              ),
                            ),
                          )
                        else
                          for (var i = 0; i < _paragraphs.length; i++) ...<Widget>[
                            _ReaderParagraphView(
                              key: ValueKey<String>(
                                'paragraph_${i}_$_selectionRevision',
                              ),
                              paragraphIndex: i,
                              paragraphText: _paragraphs[i],
                              underlines: _underlinesForParagraph(i),
                              tone: tone,
                              fontSize: _preferences.fontSize,
                              isUnderlineMode: _isUnderlineMode,
                              onSegmentTap: (segment) => _handleSegmentTap(
                                paragraphIndex: i,
                                segment: segment,
                              ),
                              onSelectionChanged: (selectedText) {
                                final cleaned = selectedText.trim();
                                if (cleaned.isEmpty) {
                                  if (_selectedParagraphIndex == i) {
                                    setState(() {
                                      _selectedParagraphIndex = null;
                                      _selectedPlainText = '';
                                    });
                                  }
                                } else {
                                  setState(() {
                                    _selectedParagraphIndex = i;
                                    _selectedPlainText = cleaned;
                                  });
                                }
                              },
                              onUnderlineSelection: (selectedText) =>
                                  _underlineSelection(
                                paragraphIndex: i,
                                selectedText: selectedText,
                              ),
                              onRemoveSelectionUnderline: (selectedText) =>
                                  _removeUnderlineInSelection(
                                paragraphIndex: i,
                                selectedText: selectedText,
                              ),
                              onLookupSelection: (selectedText) =>
                                  _lookupSelectedText(
                                paragraphIndex: i,
                                selectedText: selectedText,
                              ),
                              hasUnderlineInSelection: (selectedText) =>
                                  _selectionHasUnderline(i, selectedText),
                            ),
                            if (i < _paragraphs.length - 1)
                              SizedBox(height: _preferences.fontSize * 0.95),
                          ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (hasFloatingSelection)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: _SelectionFloatingBar(
                      tone: tone,
                      isUnderlineMode: _isUnderlineMode,
                      hasExistingUnderline: _selectionHasUnderline(
                        _selectedParagraphIndex!,
                        _selectedPlainText,
                      ),
                      onUnderline: () => _underlineSelection(
                        paragraphIndex: _selectedParagraphIndex!,
                        selectedText: _selectedPlainText,
                      ),
                      onRemoveUnderline: () => _removeUnderlineInSelection(
                        paragraphIndex: _selectedParagraphIndex!,
                        selectedText: _selectedPlainText,
                      ),
                      onLookupMeaning: () => _lookupSelectedText(
                        paragraphIndex: _selectedParagraphIndex!,
                        selectedText: _selectedPlainText,
                      ),
                      onDismiss: _clearActiveSelection,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentHeader(
    ArticleReaderTone tone,
    ArticleLevel? parsedLevel,
  ) {
    final article = widget.article;
    final accentColor = parsedLevel?.accentColor ?? tone.underlineColor;

    // Başlık, açıklama ve yazar alanları sabit boyutlarda tutulur;
    // yazı boyutu (A- / A+) ayarı yalnızca okuma metnini etkiler.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: tone.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (parsedLevel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: parsedLevel.accentColor.withAlpha(28),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${parsedLevel.code} • ${context.l10n.levelLabel(parsedLevel.code)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.25,
                      color: parsedLevel.accentColor,
                    ),
                  ),
                ),
              if (article.category.isNotEmpty)
                Text(
                  article.category,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: tone.secondaryTextColor,
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: tone.secondaryTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    article.formattedReadingTime,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: tone.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            article.title,
            key: const ValueKey<String>('reader_article_title'),
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              height: 1.28,
              letterSpacing: -0.25,
              color: tone.textColor,
            ),
          ),
          if (article.description.isNotEmpty &&
              article.content.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: accentColor.withAlpha(160),
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                article.description,
                key: const ValueKey<String>('reader_article_description'),
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  color: tone.secondaryTextColor,
                ),
              ),
            ),
          ],
          if (article.author.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Divider(height: 1, thickness: 1, color: tone.dividerColor),
            const SizedBox(height: 11),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.dividerColor.withAlpha(150),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    key: const ValueKey<String>('reader_author_icon'),
                    size: 15,
                    color: tone.secondaryTextColor,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    article.author,
                    key: const ValueKey<String>('reader_article_author'),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: tone.textColor.withAlpha(215),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tek bir paragrafı kitap tipografisiyle işler; her kelimeye dokunma
/// (`TapGestureRecognizer`) ile çok kelimeli metin seçimini (`SelectionArea`)
/// bellek sızıntısı olmadan birlikte yönetir.
class _ReaderParagraphView extends StatefulWidget {
  const _ReaderParagraphView({
    super.key,
    required this.paragraphIndex,
    required this.paragraphText,
    required this.underlines,
    required this.tone,
    required this.fontSize,
    required this.isUnderlineMode,
    required this.onSegmentTap,
    required this.onSelectionChanged,
    required this.onUnderlineSelection,
    required this.onRemoveSelectionUnderline,
    required this.onLookupSelection,
    required this.hasUnderlineInSelection,
  });

  final int paragraphIndex;
  final String paragraphText;
  final List<ArticleUnderline> underlines;
  final ArticleReaderTone tone;
  final double fontSize;
  final bool isUnderlineMode;
  final void Function(ArticleRenderSegment segment) onSegmentTap;
  final void Function(String selectedText) onSelectionChanged;
  final void Function(String selectedText) onUnderlineSelection;
  final void Function(String selectedText) onRemoveSelectionUnderline;
  final void Function(String selectedText) onLookupSelection;
  final bool Function(String selectedText) hasUnderlineInSelection;

  @override
  State<_ReaderParagraphView> createState() => _ReaderParagraphViewState();
}

class _ReaderParagraphViewState extends State<_ReaderParagraphView> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  String _localSelectedText = '';

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final segments = ArticleTextParser.buildSegments(
      widget.paragraphText,
      widget.underlines,
    );

    final baseStyle = TextStyle(
      fontSize: widget.fontSize,
      height: 1.78,
      letterSpacing: 0.15,
      color: widget.tone.textColor,
    );

    final spans = <InlineSpan>[];
    for (final segment in segments) {
      final isInteractive = segment.isWord ||
          (widget.isUnderlineMode && segment.isUnderlined);

      TapGestureRecognizer? recognizer;
      if (isInteractive) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onSegmentTap(segment);
        _recognizers.add(recognizer);
      }

      final style = segment.isUnderlined
          ? baseStyle.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: widget.tone.underlineColor,
              decorationThickness: 2.2,
              backgroundColor: widget.tone.underlineFillColor,
            )
          : baseStyle;

      spans.add(
        TextSpan(
          text: segment.text,
          style: style,
          recognizer: recognizer,
        ),
      );
    }

    return SelectionArea(
      onSelectionChanged: (SelectedContent? content) {
        final plain = content?.plainText ?? '';
        _localSelectedText = plain;
        widget.onSelectionChanged(plain);
      },
      contextMenuBuilder: (context, selectableRegionState) {
        final selected = _localSelectedText.trim();
        final items = <ContextMenuButtonItem>[];

        if (selected.isNotEmpty) {
          final s = context.l10n;
          if (widget.isUnderlineMode) {
            items.add(
              ContextMenuButtonItem(
                label: s.underlineAction,
                onPressed: () {
                  selectableRegionState.hideToolbar();
                  widget.onUnderlineSelection(selected);
                },
              ),
            );
            if (widget.hasUnderlineInSelection(selected)) {
              items.add(
                ContextMenuButtonItem(
                  label: s.removeUnderlineAction,
                  onPressed: () {
                    selectableRegionState.hideToolbar();
                    widget.onRemoveSelectionUnderline(selected);
                  },
                ),
              );
            }
          } else {
            items.add(
              ContextMenuButtonItem(
                label: s.lookupMeaningAction,
                onPressed: () {
                  selectableRegionState.hideToolbar();
                  widget.onLookupSelection(selected);
                },
              ),
            );
          }
        }

        items.addAll(selectableRegionState.contextMenuButtonItems);
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: items,
        );
      },
      child: Text.rich(
        TextSpan(children: spans),
        textAlign: TextAlign.start,
      ),
    );
  }
}

class _ToneOptionChip extends StatelessWidget {
  const _ToneOptionChip({
    required this.tone,
    required this.isSelected,
    required this.onTap,
  });

  final ArticleReaderTone tone;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final toneLabel = switch (tone) {
      ArticleReaderTone.white => s.toneWhite,
      ArticleReaderTone.paper => s.tonePaper,
      ArticleReaderTone.dark => s.toneDark,
    };

    return Material(
      color: tone.backgroundColor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('reader_tone_${tone.storageKey}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? colorScheme.primary : tone.dividerColor,
              width: isSelected ? 2.2 : 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tone.textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                toneLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: tone.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionFloatingBar extends StatelessWidget {
  const _SelectionFloatingBar({
    required this.tone,
    required this.isUnderlineMode,
    required this.hasExistingUnderline,
    required this.onUnderline,
    required this.onRemoveUnderline,
    required this.onLookupMeaning,
    required this.onDismiss,
  });

  final ArticleReaderTone tone;
  final bool isUnderlineMode;
  final bool hasExistingUnderline;
  final VoidCallback onUnderline;
  final VoidCallback onRemoveUnderline;
  final VoidCallback onLookupMeaning;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Material(
      elevation: 4,
      color: tone.surfaceColor,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tone.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isUnderlineMode) ...<Widget>[
              TextButton.icon(
                onPressed: onUnderline,
                icon: Icon(
                  Icons.border_color_rounded,
                  size: 18,
                  color: tone.underlineColor,
                ),
                label: Text(
                  s.underlineAction,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tone.textColor,
                  ),
                ),
              ),
              if (hasExistingUnderline)
                TextButton.icon(
                  onPressed: onRemoveUnderline,
                  icon: Icon(
                    Icons.format_clear_rounded,
                    size: 18,
                    color: tone.secondaryTextColor,
                  ),
                  label: Text(
                    s.removeShort,
                    style: TextStyle(color: tone.secondaryTextColor),
                  ),
                ),
            ] else
              TextButton.icon(
                onPressed: onLookupMeaning,
                icon: Icon(
                  Icons.translate_rounded,
                  size: 18,
                  color: tone.underlineColor,
                ),
                label: Text(
                  s.lookupMeaningAction,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tone.textColor,
                  ),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: tone.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
