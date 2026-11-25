import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_backdrop.dart';
import '../../../core/tts/tts_service.dart';
import '../../../core/utils/word_sanitizer.dart';
import '../../ads/widgets/promo_interstitial_dialog.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../browser/browser_screen.dart';
import '../../browser/widgets/word_preview_sheet.dart';
import '../../translation/data/translation_cache_repository.dart';
import '../../translation/models/word_lexicon_info.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/services/cached_translation_service.dart';
import '../../translation/services/word_lexicon_service.dart';
import '../../translation/services/word_translation_service.dart';
import '../../words/data/word_repository.dart';
import '../../words/models/saved_word.dart';
import '../../words/models/word_list.dart';
import '../controllers/article_audio_controller.dart';
import '../controllers/article_reading_progress_controller.dart';
import '../data/article_reader_repository.dart';
import '../models/article.dart';
import '../models/article_level.dart';
import '../models/article_reader_models.dart';
import '../services/article_passage_translation_service.dart';
import '../services/article_word_lexicon_service.dart';
import '../services/article_word_translation_service.dart';
import '../utils/article_text_parser.dart';
import '../widgets/article_audio_player_bar.dart';
import '../widgets/article_passage_translation_sheet.dart';

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
    this.lexiconService,
    this.passageTranslator,
    this.ttsService,
    this.audioController,
    this.readingProgressController,
    this.authController,
    this.onAddWord,
    this.onAddWordWithLexicon,
    this.loadWordLists,
    this.onCreateWordList,
  });

  final Article article;
  final ArticleReaderStore? readerStore;
  final WordTranslationService? translationService;
  final WordLexiconService? lexiconService;
  final ArticlePassageTranslator? passageTranslator;
  final TtsService? ttsService;
  final ArticleAudioController? audioController;
  final ArticleReadingProgressController? readingProgressController;
  final AuthController? authController;
  final AddWordCallback? onAddWord;
  final AddWordWithLexiconCallback? onAddWordWithLexicon;
  final Future<List<WordList>> Function()? loadWordLists;
  final CreateWordListCallback? onCreateWordList;

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  late final ArticleReaderStore _readerStore;
  late final WordTranslationService _baseTranslationService;
  late final WordTranslationService _translationService;
  late final WordLexiconService _lexiconService;
  late final bool _ownsTranslationService;
  late final ArticlePassageTranslator _passageTranslator;
  late final bool _ownsPassageTranslator;
  late final List<String> _paragraphs;
  late final List<GlobalKey> _paragraphKeys;
  late final ArticleAudioController _audioController;
  late final bool _ownsAudioController;
  late final ArticleReadingProgressController _readingProgressController;
  final ScrollController _scrollController = ScrollController();

  Timer? _progressSaveTimer;
  double _latestScrollProgress = 0.0;
  double _latestScrollOffset = 0.0;
  bool _hasRestoredScrollPosition = false;

  int? _lastAutoScrolledParagraph;
  ArticleReaderPreferences _preferences = ArticleReaderPreferences.defaults;
  List<ArticleUnderline> _underlines = const <ArticleUnderline>[];
  bool _isUnderlineMode = false;
  bool _isWordSheetOpen = false;

  // Uygulama içi özel metin seçimi (sistem Kopyala/Tümünü Seç kullanılmaz;
  // yalnızca kullanıcının basılı tutup seçtiği kelime veya kısa aralık tutulur).
  int? _selectedParagraphIndex;
  int? _selectedStartOffset;
  int? _selectedEndOffset;

  String get _selectedPlainText {
    final pIdx = _selectedParagraphIndex;
    final start = _selectedStartOffset;
    final end = _selectedEndOffset;
    if (pIdx == null ||
        start == null ||
        end == null ||
        pIdx < 0 ||
        pIdx >= _paragraphs.length) {
      return '';
    }
    final paragraph = _paragraphs[pIdx];
    final safeStart = start.clamp(0, paragraph.length);
    final safeEnd = end.clamp(safeStart, paragraph.length);
    if (safeEnd <= safeStart) return '';
    return paragraph.substring(safeStart, safeEnd).trim();
  }

  @override
  void initState() {
    super.initState();
    _readerStore =
        widget.readerStore ?? ArticleReaderRepository(AppDatabase.instance);
    _ownsTranslationService = widget.translationService == null;
    _baseTranslationService = widget.translationService ??
        CachedTranslationService(
          cacheRepository: TranslationCacheRepository(AppDatabase.instance),
        );
    // Makale içinde dokunulan/seçilen kelimede önce açık makalenin word_meanings
    // haritasına (tam kelime + kök formu) bakar; yoksa standart/yerel servise geçer.
    _translationService = ArticleWordTranslationService(
      article: widget.article,
      fallbackService: _baseTranslationService,
    );
    _lexiconService = ArticleWordLexiconService(
      article: widget.article,
      baseService: widget.lexiconService,
    );
    _ownsPassageTranslator = widget.passageTranslator == null;
    _passageTranslator =
        widget.passageTranslator ?? ArticlePassageTranslationService();

    final effectiveBody = widget.article.content.trim().isNotEmpty
        ? widget.article.content
        : widget.article.description;
    _paragraphs = ArticleTextParser.splitParagraphs(effectiveBody);
    _paragraphKeys = List<GlobalKey>.generate(
      _paragraphs.length,
      (_) => GlobalKey(),
      growable: false,
    );
    _readingProgressController =
        widget.readingProgressController ??
        ArticleReadingProgressController.shared;
    final savedProgress =
        _readingProgressController.progressForArticle(widget.article.id);
    final initialAudioMs = savedProgress?.audioPositionMs ?? 0;

    _ownsAudioController = widget.audioController == null;
    _audioController = widget.audioController ??
        ArticleAudioController(
          article: widget.article,
          paragraphs: _paragraphs,
          initialPositionMs: initialAudioMs,
        );
    _audioController.addListener(_handleAudioStateChanged);
    _scrollController.addListener(_handleScrollChanged);

    _loadInitialReaderData();
  }

  double _calculateEffectiveProgress(double scrollProgress) {
    final audioFraction = _audioController.progressFraction;
    if (audioFraction > 0) {
      return (scrollProgress > audioFraction ? scrollProgress : audioFraction)
          .clamp(0.0, 1.0);
    }
    return scrollProgress.clamp(0.0, 1.0);
  }

  void _handleScrollChanged() {
    if (!_hasRestoredScrollPosition || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final clampedOffset =
        maxExtent > 0 ? position.pixels.clamp(0.0, maxExtent).toDouble() : 0.0;
    final scrollProg = maxExtent <= 0
        ? 1.0
        : (clampedOffset / maxExtent).clamp(0.0, 1.0).toDouble();

    final effectiveProgress = _calculateEffectiveProgress(scrollProg);
    _latestScrollProgress = effectiveProgress;
    _latestScrollOffset = clampedOffset;

    _readingProgressController.recordProgress(
      article: widget.article,
      progress: effectiveProgress,
      scrollOffset: clampedOffset,
      audioPositionMs: _audioController.position.inMilliseconds,
      persist: false,
    );

    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 350), () {
      _readingProgressController.recordProgress(
        article: widget.article,
        progress: _latestScrollProgress,
        scrollOffset: _latestScrollOffset,
        audioPositionMs: _audioController.position.inMilliseconds,
        persist: true,
      );
    });
  }

  void _restoreSavedScrollPosition() {
    if (!mounted || _hasRestoredScrollPosition) return;
    _hasRestoredScrollPosition = true;

    final saved = _readingProgressController.progressForArticle(
      widget.article.id,
    );

    if (_scrollController.hasClients) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (saved != null && saved.clampedProgress > 0) {
        if (maxExtent > 0) {
          final target = (saved.clampedProgress * maxExtent)
              .clamp(0.0, maxExtent)
              .toDouble();
          _scrollController.jumpTo(target);
          _latestScrollProgress = saved.clampedProgress;
          _latestScrollOffset = target;
        } else {
          _latestScrollProgress = 1.0;
          _latestScrollOffset = 0.0;
        }
      } else {
        _latestScrollProgress = maxExtent <= 0 ? 1.0 : 0.0;
        _latestScrollOffset = 0.0;
      }
    } else if (saved != null) {
      _latestScrollProgress = saved.clampedProgress;
      _latestScrollOffset = saved.scrollOffset;
    }

    _readingProgressController.recordProgress(
      article: widget.article,
      progress: _latestScrollProgress,
      scrollOffset: _latestScrollOffset,
      persist: true,
    );
  }

  void _handleAudioStateChanged() {
    if (!mounted) return;
    final currentAudioMs = _audioController.position.inMilliseconds;
    if (currentAudioMs > 0 && _hasRestoredScrollPosition) {
      final effectiveProgress = _calculateEffectiveProgress(_latestScrollProgress);
      _latestScrollProgress = effectiveProgress;
      _readingProgressController.recordProgress(
        article: widget.article,
        progress: effectiveProgress,
        scrollOffset: _latestScrollOffset,
        audioPositionMs: currentAudioMs,
        persist: false,
      );
    }

    if (_audioController.isVisible && _audioController.isPlaying) {
      final targetParagraph = _audioController.currentParagraphIndex;
      if (targetParagraph != _lastAutoScrolledParagraph &&
          targetParagraph >= 0 &&
          targetParagraph < _paragraphKeys.length) {
        _lastAutoScrolledParagraph = targetParagraph;
        final ctx = _paragraphKeys[targetParagraph].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            alignment: 0.25,
          );
        }
      }
    } else if (!_audioController.isVisible) {
      _lastAutoScrolledParagraph = null;
    }
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
    _scrollController.removeListener(_handleScrollChanged);
    if (_hasRestoredScrollPosition) {
      _readingProgressController.recordProgress(
        article: widget.article,
        progress: _latestScrollProgress,
        scrollOffset: _latestScrollOffset,
        audioPositionMs: _audioController.position.inMilliseconds,
        persist: true,
      );
    }
    _scrollController.dispose();
    _audioController.removeListener(_handleAudioStateChanged);
    if (_ownsAudioController) {
      _audioController.dispose();
    }
    if (_ownsTranslationService) {
      _baseTranslationService.dispose();
    }
    if (_ownsPassageTranslator) {
      _passageTranslator.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialReaderData() async {
    try {
      await _readingProgressController.load();
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
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSavedScrollPosition();
    });
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
      _selectedStartOffset = null;
      _selectedEndOffset = null;
    });
  }

  void _clearActiveSelection() {
    if (_selectedParagraphIndex == null &&
        _selectedStartOffset == null &&
        _selectedEndOffset == null) {
      return;
    }
    setState(() {
      _selectedParagraphIndex = null;
      _selectedStartOffset = null;
      _selectedEndOffset = null;
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
      // Altı çizili bir kelimenin üzerine tek sefer tıklandığında yalnızca
      // o kelimenin alt çizgisini kaldır; çok kelimelik çizginin diğer
      // kelimeleri bozulmadan kalsın.
      final existingUnderline = segment.underline;
      if (existingUnderline != null) {
        final paragraph = _paragraphs[paragraphIndex];
        final next = segment.isWord
            ? ArticleTextParser.removeWordRangeFromUnderlines(
                existing: _underlines,
                paragraphIndex: paragraphIndex,
                wordStart: segment.start,
                wordEnd: segment.end,
                paragraphText: paragraph,
              )
            : _underlines
                .where((item) =>
                    !(item.paragraphIndex == existingUnderline.paragraphIndex &&
                        item.startOffset == existingUnderline.startOffset &&
                        item.endOffset == existingUnderline.endOffset))
                .toList(growable: false);
        await _persistUnderlines(next);
        return;
      }

      // Çizili olmayan bir kelimeye tek tıkla altını çiz ve kaydet.
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

    // Kalem kapalıyken kelimeye tek dokunuşta seçimi temizleyip anlamı aç.
    _clearActiveSelection();
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

  /// "Altını Çiz" modu açıkken kelimeye basılı tutup sürüklenerek geçilen
  /// kelime aralığını tek seferde kaydeder.
  Future<void> _handleDragMarkCommitted({
    required int paragraphIndex,
    required int startOffset,
    required int endOffset,
  }) async {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return;
    if (endOffset <= startOffset) return;

    final paragraph = _paragraphs[paragraphIndex];
    final next = ArticleTextParser.addAndMergeUnderline(
      existing: _underlines,
      incoming: ArticleUnderline(
        articleId: widget.article.id,
        paragraphIndex: paragraphIndex,
        startOffset: startOffset,
        endOffset: endOffset,
        createdAt: DateTime.now(),
      ),
      paragraphText: paragraph,
    );
    await _persistUnderlines(next);
  }

  /// "Altını Çiz" modunda zaten çizili bir kelimeden basılı tutup (ileri veya
  /// geri) sürükleyerek tüm aralığı veya bir kısmını topluca siler.
  Future<void> _handleDragEraseCommitted({
    required int paragraphIndex,
    required int startOffset,
    required int endOffset,
  }) async {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return;
    if (endOffset <= startOffset) return;
    final paragraph = _paragraphs[paragraphIndex];
    final next = ArticleTextParser.removeWordRangeFromUnderlines(
      existing: _underlines,
      paragraphIndex: paragraphIndex,
      wordStart: startOffset,
      wordEnd: endOffset,
      paragraphText: paragraph,
    );
    await _persistUnderlines(next);
  }

  /// "Altını Çiz" modu kapalıyken basılı tutma/sürükleme ile seçilen yalnızca
  /// ilgili kelime veya kısa ifade aralığını uygulama içi seçim çubuğuna bağlar
  /// (tüm cümle otomatik seçilmez ve sistem Kopyala/Tümünü Seç menüsü açılmaz).
  void _handleNormalSelectionCommitted({
    required int paragraphIndex,
    required int startOffset,
    required int endOffset,
  }) {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return;
    if (endOffset <= startOffset) {
      _clearActiveSelection();
      return;
    }
    setState(() {
      _selectedParagraphIndex = paragraphIndex;
      _selectedStartOffset = startOffset;
      _selectedEndOffset = endOffset;
    });
  }

  Future<void> _underlineSelection({
    required int paragraphIndex,
    required String selectedText,
  }) async {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return;
    final paragraph = _paragraphs[paragraphIndex];
    final start = _selectedStartOffset;
    final end = _selectedEndOffset;
    final range = (start != null && end != null && end > start)
        ? (start: start, end: end)
        : ArticleTextParser.findSelectionRange(paragraph, selectedText);
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
    final start = _selectedStartOffset;
    final end = _selectedEndOffset;
    final range = (start != null && end != null && end > start)
        ? (start: start, end: end)
        : ArticleTextParser.findSelectionRange(paragraph, selectedText);
    if (range == null) return;

    final next = ArticleTextParser.removeWordRangeFromUnderlines(
      existing: _underlines,
      paragraphIndex: paragraphIndex,
      wordStart: range.start,
      wordEnd: range.end,
      paragraphText: paragraph,
    );
    _clearActiveSelection();
    await _persistUnderlines(next);
  }

  bool _selectionHasUnderline(int paragraphIndex, String selectedText) {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return false;
    final paragraph = _paragraphs[paragraphIndex];
    final start = _selectedStartOffset;
    final end = _selectedEndOffset;
    final range = (start != null && end != null && end > start)
        ? (start: start, end: end)
        : ArticleTextParser.findSelectionRange(paragraph, selectedText);
    if (range == null) return false;
    return _underlines.any(
      (item) =>
          item.paragraphIndex == paragraphIndex &&
          item.overlaps(range.start, range.end),
    );
  }

  bool _isPassageOrSentenceSelection(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return false;
    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    if (words.length >= 4) return true;
    if (RegExp(r'[.!?]').hasMatch(trimmed)) return true;
    if (WordSanitizer.clean(trimmed) == null) return true;
    if (widget.article.findSentenceTranslation(trimmed) != null) return true;
    return false;
  }

  Future<void> _lookupSelectedText({
    required int paragraphIndex,
    required String selectedText,
  }) async {
    final trimmed = selectedText.trim();
    if (trimmed.isEmpty) return;

    final fullParagraph =
        (paragraphIndex >= 0 && paragraphIndex < _paragraphs.length)
            ? _paragraphs[paragraphIndex]
            : null;

    // Seçim bir cümle, çok kelimeli ifade veya paragraf ise tek-kelime sınırına
    // takılmadan doğrudan cümle/paragraf Türkçe çeviri panelini aç.
    if (_isPassageOrSentenceSelection(trimmed)) {
      final normSel = Article.normalizeTranslationKey(trimmed);
      final normPara = fullParagraph != null
          ? Article.normalizeTranslationKey(fullParagraph)
          : '';
      final isFullParagraph = normPara.isNotEmpty &&
          normSel.length >= (normPara.length * 0.90).round();

      _clearActiveSelection();
      await _openPassageTranslationSheet(
        selectedText: trimmed,
        paragraphIndex: paragraphIndex,
        fullParagraphText: fullParagraph,
        isFullParagraph: isFullParagraph,
      );
      return;
    }

    final cleaned = WordSanitizer.clean(trimmed);
    if (cleaned == null) {
      _clearActiveSelection();
      await _openPassageTranslationSheet(
        selectedText: trimmed,
        paragraphIndex: paragraphIndex,
        fullParagraphText: fullParagraph,
        isFullParagraph: false,
      );
      return;
    }

    String? contextSentence;
    if (fullParagraph != null) {
      final anchorOffset = _selectedStartOffset ??
          ArticleTextParser.findSelectionRange(fullParagraph, trimmed)?.start ??
          0;
      contextSentence = ArticleTextParser.extractContextSentence(
        fullParagraph,
        anchorOffset,
      );
    }

    _clearActiveSelection();
    await _openWordMeaningSheet(
      word: cleaned,
      contextSentence: contextSentence,
    );
  }

  Future<void> _translateWholeParagraph(int paragraphIndex) async {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return;
    final fullParagraph = _paragraphs[paragraphIndex].trim();
    if (fullParagraph.isEmpty) return;

    _clearActiveSelection();
    await _openPassageTranslationSheet(
      selectedText: fullParagraph,
      paragraphIndex: paragraphIndex,
      fullParagraphText: fullParagraph,
      isFullParagraph: true,
    );
  }

  Future<void> _openPassageTranslationSheet({
    required String selectedText,
    required int paragraphIndex,
    required String? fullParagraphText,
    required bool isFullParagraph,
  }) async {
    if (_isWordSheetOpen || !mounted) return;
    _isWordSheetOpen = true;

    if (_audioController.isPlaying) {
      await _audioController.pause();
      if (!mounted) {
        _isWordSheetOpen = false;
        return;
      }
    }

    try {
      await ArticlePassageTranslationSheet.show(
        context,
        article: widget.article,
        selectedText: selectedText,
        translator: _passageTranslator,
        isFullParagraph: isFullParagraph,
        paragraphIndex: paragraphIndex,
        fullParagraphText: fullParagraphText,
        ttsService: widget.ttsService,
      );
    } finally {
      _isWordSheetOpen = false;
    }
  }

  Future<void> _openWordMeaningSheet({
    required String word,
    String? contextSentence,
  }) async {
    if (_isWordSheetOpen || !mounted) return;
    _isWordSheetOpen = true;

    if (_audioController.isPlaying) {
      await _audioController.pause();
      if (!mounted) {
        _isWordSheetOpen = false;
        return;
      }
    }

    try {
      final auth = widget.authController;
      if (auth != null &&
          !auth.hasReachedDailyLimit &&
          auth.recordWordLookupAndShouldShowPromo()) {
        await PromoInterstitialDialog.show(context);
        if (!mounted) return;
      }

      await WordPreviewSheet.show(
        context,
        word: word,
        contextSentence: contextSentence,
        translationService: _translationService,
        lexiconService: _lexiconService,
        ttsService: widget.ttsService,
        authController: widget.authController,
        loadWordLists: widget.loadWordLists,
        onCreateWordList: widget.onCreateWordList,
        onAddWord: _handleAddWord,
        onAddWordWithLexicon: _handleAddWordWithLexicon,
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
  ) {
    return _handleAddWordWithLexicon(word, meaning, meanings, listId, listName, null);
  }

  Future<void> _handleAddWordWithLexicon(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
    String? listName,
    WordLexiconInfo? selectedLexicon,
  ) async {
    SaveWordStatus status;
    try {
      if (widget.onAddWordWithLexicon != null) {
        status = await widget.onAddWordWithLexicon!(
          word,
          meaning,
          meanings,
          listId,
          selectedLexicon,
        );
      } else if (widget.onAddWord != null) {
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
          ipaUs: selectedLexicon?.ipaUs,
          ipaUk: selectedLexicon?.ipaUk,
          synonyms: selectedLexicon?.synonyms ?? const <String>[],
          antonyms: selectedLexicon?.antonyms ?? const <String>[],
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
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final s = context.l10n;
            final currentPrefs = _preferences;

            Future<void> applyPrefs(ArticleReaderPreferences next) async {
              await _updatePreferences(next);
              if (sheetContext.mounted) {
                setModalState(() {});
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.readerAppearanceTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.backgroundToneLabel,
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
                            right: tone == ArticleReaderTone.values.last ? 0 : 8,
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
                  const SizedBox(height: 20),
                  Row(
                    children: <Widget>[
                      Text(
                        s.fontSizeLabel,
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
                  const SizedBox(height: 20),
                  // İşaretleme Stili: Altı Çizili / Fosforlu Kalem / Üstü Çizili
                  Text(
                    s.markStyleLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: ArticleMarkStyle.values.map((styleOption) {
                      final isSelected = currentPrefs.markStyle == styleOption;
                      final accent = currentPrefs.effectiveMarkAccent;
                      final icon = switch (styleOption) {
                        ArticleMarkStyle.underline =>
                          Icons.format_underlined_rounded,
                        ArticleMarkStyle.highlight => Icons.highlight_rounded,
                        ArticleMarkStyle.strikethrough =>
                          Icons.format_strikethrough_rounded,
                      };
                      final label = switch (styleOption) {
                        ArticleMarkStyle.underline => s.markStyleUnderline,
                        ArticleMarkStyle.highlight => s.markStyleHighlight,
                        ArticleMarkStyle.strikethrough =>
                          s.markStyleStrikethrough,
                      };
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: styleOption == ArticleMarkStyle.values.last
                                ? 0
                                : 8,
                          ),
                          child: Material(
                            color: isSelected
                                ? accent.withAlpha(28)
                                : colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey<String>(
                                'reader_mark_style_${styleOption.storageKey}',
                              ),
                              onTap: () => applyPrefs(
                                currentPrefs.copyWith(markStyle: styleOption),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? accent
                                        : colorScheme.outlineVariant,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      icon,
                                      size: 20,
                                      color: isSelected
                                          ? accent
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? accent
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 20),
                  // İşaretleme Rengi: 5 hazır renk seçeneği
                  Text(
                    s.markColorLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ArticleMarkColor.values.map((colorOption) {
                      final isSelected = currentPrefs.markColor == colorOption;
                      return GestureDetector(
                        key: ValueKey<String>(
                          'reader_mark_color_${colorOption.storageKey}',
                        ),
                        onTap: () => applyPrefs(
                          currentPrefs.copyWith(markColor: colorOption),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colorOption.swatchColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2.8,
                            ),
                            boxShadow: isSelected
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: colorOption.swatchColor
                                          .withAlpha(110),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    }).toList(growable: false),
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
    final palette = tone.resolvePalette(context);
    final effectiveMarkAccent =
        _preferences.markColor.accentForBrightness(palette.brightness);
    final effectiveHighlightFill =
        _preferences.markColor.highlightFillForBrightness(palette.brightness);
    final parsedLevel = widget.article.parsedLevel;
    final overlayStyle = palette.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final hasFloatingSelection =
        _selectedParagraphIndex != null && _selectedPlainText.trim().isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: ListenableBuilder(
        listenable: _audioController,
        builder: (context, _) {
          final isAudioVisible = _audioController.isVisible;
          final activeSentence = _audioController.activeSentence;

          final readerColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDocumentHeader(palette, parsedLevel),
              const SizedBox(height: 24),
              if (_paragraphs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Bu makalenin içeriği henüz eklenmedi.',
                    style: TextStyle(
                      fontSize: _preferences.fontSize,
                      height: 1.75,
                      color: palette.secondaryTextColor,
                    ),
                  ),
                )
              else
                for (var i = 0; i < _paragraphs.length; i++) ...<Widget>[
                  KeyedSubtree(
                    key: _paragraphKeys[i],
                    child: _ReaderParagraphView(
                      key: ValueKey<String>('paragraph_$i'),
                      paragraphIndex: i,
                      paragraphText: _paragraphs[i],
                      underlines: _underlinesForParagraph(i),
                      highlightStartOffset: activeSentence != null &&
                              activeSentence.paragraphIndex == i
                          ? activeSentence.startOffset
                          : null,
                      highlightEndOffset: activeSentence != null &&
                              activeSentence.paragraphIndex == i
                          ? activeSentence.endOffset
                          : null,
                      selectedStartOffset: _selectedParagraphIndex == i
                          ? _selectedStartOffset
                          : null,
                      selectedEndOffset: _selectedParagraphIndex == i
                          ? _selectedEndOffset
                          : null,
                      tone: tone,
                      fontSize: _preferences.fontSize,
                      markStyle: _preferences.markStyle,
                      markAccentColor: effectiveMarkAccent,
                      markHighlightFillColor: effectiveHighlightFill,
                      isUnderlineMode: _isUnderlineMode,
                      onSegmentTap: (segment) => _handleSegmentTap(
                        paragraphIndex: i,
                        segment: segment,
                      ),
                      onDragMarkCommitted: (start, end) =>
                          _handleDragMarkCommitted(
                        paragraphIndex: i,
                        startOffset: start,
                        endOffset: end,
                      ),
                      onDragEraseCommitted: (start, end) =>
                          _handleDragEraseCommitted(
                        paragraphIndex: i,
                        startOffset: start,
                        endOffset: end,
                      ),
                      onNormalSelectionCommitted: (start, end) =>
                          _handleNormalSelectionCommitted(
                        paragraphIndex: i,
                        startOffset: start,
                        endOffset: end,
                      ),
                    ),
                  ),
                  if (i < _paragraphs.length - 1)
                    SizedBox(height: _preferences.fontSize * 0.95),
                ],
            ],
          );

          final scaffold = Scaffold(
            backgroundColor: palette.backgroundColor,
            appBar: AppBar(
              backgroundColor: palette.appBarColor,
              foregroundColor: palette.textColor,
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
                        color: palette.secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                // Makaleyi sesli dinleme (Podcast AI / Cihaz Sesi) butonu
                if (_audioController.hasPlayableContent)
                  IconButton(
                    key: const ValueKey<String>('reader_audio_listen_button'),
                    tooltip: context.l10n.listenArticleTooltip,
                    onPressed: _audioController.togglePlayerVisibility,
                    icon: Icon(
                      isAudioVisible
                          ? Icons.graphic_eq_rounded
                          : Icons.headphones_rounded,
                      size: 22,
                      color: isAudioVisible
                          ? palette.underlineColor
                          : palette.textColor,
                    ),
                  ),
                // Altını çizme kalemi aç/kapa butonu
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Tooltip(
                message: _isUnderlineMode
                    ? context.l10n.underlinePenActiveTooltip
                    : context.l10n.underlinePenTooltip,
                child: Material(
                  color: _isUnderlineMode
                      ? effectiveMarkAccent.withAlpha(38)
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
                                color: effectiveMarkAccent.withAlpha(170),
                                width: 1.2,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            switch (_preferences.markStyle) {
                              ArticleMarkStyle.underline =>
                                Icons.border_color_rounded,
                              ArticleMarkStyle.highlight =>
                                Icons.highlight_rounded,
                              ArticleMarkStyle.strikethrough =>
                                Icons.format_strikethrough_rounded,
                            },
                            size: 20,
                            color: _isUnderlineMode
                                ? effectiveMarkAccent
                                : palette.textColor,
                          ),
                          if (_isUnderlineMode) ...<Widget>[
                            const SizedBox(width: 5),
                            Text(
                              context.l10n.underlinePenShort,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: effectiveMarkAccent,
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
                  color: palette.textColor,
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
                Divider(height: 1, thickness: 1, color: palette.dividerColor),
                if (_isUnderlineMode)
                  Container(
                    width: double.infinity,
                    color: palette.surfaceColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.edit_rounded,
                          size: 15,
                          color: effectiveMarkAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.underlineBannerHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.secondaryTextColor,
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
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  palette.paperCardColor != null ? 14 : 24,
                  palette.paperCardColor != null ? 16 : 24,
                  palette.paperCardColor != null ? 14 : 24,
                  hasFloatingSelection ? 104 : 56,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: palette.paperCardColor != null
                        ? Container(
                            padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
                            decoration: BoxDecoration(
                              color: palette.paperCardColor,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: palette.dividerColor,
                              ),
                            ),
                            child: readerColumn,
                          )
                        : readerColumn,
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
                      isPassageSelection:
                          _isPassageOrSentenceSelection(_selectedPlainText),
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
                      onTranslateParagraph: () =>
                          _translateWholeParagraph(_selectedParagraphIndex!),
                      onDismiss: _clearActiveSelection,
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: isAudioVisible
            ? ArticleAudioPlayerBar(
                controller: _audioController,
                tone: tone,
              )
            : null,
      );

          return palette.usesAppBackdrop
              ? AppThemeBackdrop(child: scaffold)
              : scaffold;
        },
      ),
    );
  }

  Widget _buildDocumentHeader(
    ArticleReaderPalette palette,
    ArticleLevel? parsedLevel,
  ) {
    final article = widget.article;
    final accentColor = parsedLevel?.accentColor ?? palette.underlineColor;

    // Başlık, açıklama ve yazar alanları sabit boyutlarda tutulur;
    // yazı boyutu (A- / A+) ayarı yalnızca okuma metnini etkiler.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: palette.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.dividerColor),
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
                    color: palette.secondaryTextColor,
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: palette.secondaryTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    article.formattedReadingTime,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: palette.secondaryTextColor,
                    ),
                  ),
                ],
              ),
              if (article.hasPodcastAudio)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.underlineColor.withAlpha(28),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.podcasts_rounded,
                        size: 13,
                        color: palette.underlineColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.l10n.podcastAiLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: palette.underlineColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (article.imageUrl != null && article.imageUrl!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                article.imageUrl!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            article.title,
            key: const ValueKey<String>('reader_article_title'),
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              height: 1.28,
              letterSpacing: -0.25,
              color: palette.textColor,
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
                  color: palette.secondaryTextColor,
                ),
              ),
            ),
          ],
          if (article.author.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Divider(height: 1, thickness: 1, color: palette.dividerColor),
            const SizedBox(height: 11),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.dividerColor.withAlpha(150),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    key: const ValueKey<String>('reader_author_icon'),
                    size: 15,
                    color: palette.secondaryTextColor,
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
                      color: palette.textColor.withAlpha(215),
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

/// Tek bir paragrafı kitap tipografisiyle işler.
///
/// Sistem `SelectionArea` / `SelectableText` bileşenini bilerek kullanmaz;
/// böylece Android/iOS'un "Kopyala", "Tümünü Seç", "Paylaş" menüleri asla
/// açılmaz ve yalnızca Line Reader'a özel şu etkileşimler çalışır:
/// - **Altını Çiz modu açıkken:** Kelimeye basılı tutup parmağı sürükledikçe
///   geçilen tüm kelimeler canlı olarak çizilir/vurgulanır; çizili kelimeye tek
///   tıklandığında yalnızca o kelimenin çizgisi kaldırılır.
/// - **Altını Çiz modu kapalıyken:** Kelimeye tek dokunuşta anlam penceresi
///   açılır; basılı tutup sürüklenince tüm cümle değil yalnızca parmağın
///   geçtiği kelime/kısa ifade seçilir.
class _ReaderParagraphView extends StatefulWidget {
  const _ReaderParagraphView({
    super.key,
    required this.paragraphIndex,
    required this.paragraphText,
    required this.underlines,
    this.highlightStartOffset,
    this.highlightEndOffset,
    this.selectedStartOffset,
    this.selectedEndOffset,
    required this.tone,
    required this.fontSize,
    required this.markStyle,
    required this.markAccentColor,
    required this.markHighlightFillColor,
    required this.isUnderlineMode,
    required this.onSegmentTap,
    required this.onDragMarkCommitted,
    required this.onDragEraseCommitted,
    required this.onNormalSelectionCommitted,
  });

  final int paragraphIndex;
  final String paragraphText;
  final List<ArticleUnderline> underlines;
  final int? highlightStartOffset;
  final int? highlightEndOffset;
  final int? selectedStartOffset;
  final int? selectedEndOffset;
  final ArticleReaderTone tone;
  final double fontSize;
  final ArticleMarkStyle markStyle;
  final Color markAccentColor;
  final Color markHighlightFillColor;
  final bool isUnderlineMode;
  final void Function(ArticleRenderSegment segment) onSegmentTap;
  final void Function(int startOffset, int endOffset) onDragMarkCommitted;
  final void Function(int startOffset, int endOffset) onDragEraseCommitted;
  final void Function(int startOffset, int endOffset)
      onNormalSelectionCommitted;

  @override
  State<_ReaderParagraphView> createState() => _ReaderParagraphViewState();
}

class _ReaderParagraphViewState extends State<_ReaderParagraphView> {
  final GlobalKey _richTextKey = GlobalKey();
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  // Basılı tutup sürükleme sırasındaki canlı kelime aralığı
  int? _dragAnchorStart;
  int? _dragAnchorEnd;
  int? _dragRangeStart;
  int? _dragRangeEnd;
  bool _isDragErasing = false;

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

  ({int start, int end, String text})? _hitTestWordAtGlobal(
    Offset globalPosition,
  ) {
    final renderObject = _richTextKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) return null;
    final localOffset = renderObject.globalToLocal(globalPosition);
    final textPos = renderObject.getPositionForOffset(localOffset);
    return ArticleTextParser.findWordBoundsAtOffset(
      widget.paragraphText,
      textPos.offset,
    );
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    final word = _hitTestWordAtGlobal(details.globalPosition);
    if (word == null) return;
    HapticFeedback.selectionClick();
    final startsOnUnderline = widget.isUnderlineMode &&
        widget.underlines.any((u) => u.overlaps(word.start, word.end));
    setState(() {
      _dragAnchorStart = word.start;
      _dragAnchorEnd = word.end;
      _dragRangeStart = word.start;
      _dragRangeEnd = word.end;
      _isDragErasing = startsOnUnderline;
    });
  }

  void _handleLongPressMove(LongPressMoveUpdateDetails details) {
    final anchorStart = _dragAnchorStart;
    final anchorEnd = _dragAnchorEnd;
    if (anchorStart == null || anchorEnd == null) return;

    final word = _hitTestWordAtGlobal(details.globalPosition);
    if (word == null) return;

    final nextStart = word.start < anchorStart ? word.start : anchorStart;
    final nextEnd = word.end > anchorEnd ? word.end : anchorEnd;
    if (nextStart != _dragRangeStart || nextEnd != _dragRangeEnd) {
      setState(() {
        _dragRangeStart = nextStart;
        _dragRangeEnd = nextEnd;
      });
    }
  }

  void _handleLongPressEnd(LongPressEndDetails _) {
    final start = _dragRangeStart;
    final end = _dragRangeEnd;
    final isErasing = _isDragErasing;
    setState(() {
      _dragAnchorStart = null;
      _dragAnchorEnd = null;
      _dragRangeStart = null;
      _dragRangeEnd = null;
      _isDragErasing = false;
    });

    if (start == null || end == null || end <= start) return;
    if (widget.isUnderlineMode) {
      if (isErasing) {
        widget.onDragEraseCommitted(start, end);
      } else {
        widget.onDragMarkCommitted(start, end);
      }
    } else {
      widget.onNormalSelectionCommitted(start, end);
    }
  }

  void _handleLongPressCancel() {
    if (_dragAnchorStart == null && _dragRangeStart == null) return;
    setState(() {
      _dragAnchorStart = null;
      _dragAnchorEnd = null;
      _dragRangeStart = null;
      _dragRangeEnd = null;
      _isDragErasing = false;
    });
  }

  TextStyle _buildMarkedStyle({
    required TextStyle baseStyle,
    required bool isInSpokenSentence,
    required Color sentenceHighlightColor,
  }) {
    return switch (widget.markStyle) {
      ArticleMarkStyle.underline => baseStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: widget.markAccentColor,
          decorationThickness: 2.3,
          backgroundColor: isInSpokenSentence
              ? sentenceHighlightColor
              : widget.markAccentColor.withAlpha(24),
        ),
      ArticleMarkStyle.highlight => baseStyle.copyWith(
          backgroundColor: widget.markHighlightFillColor,
        ),
      ArticleMarkStyle.strikethrough => baseStyle.copyWith(
          decoration: TextDecoration.lineThrough,
          decorationColor: widget.markAccentColor,
          decorationThickness: 2.3,
          backgroundColor: isInSpokenSentence
              ? sentenceHighlightColor
              : widget.markAccentColor.withAlpha(18),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final palette = widget.tone.resolvePalette(context);

    final segments = ArticleTextParser.buildSegments(
      widget.paragraphText,
      widget.underlines,
    );

    final baseStyle = TextStyle(
      fontSize: widget.fontSize,
      height: 1.78,
      letterSpacing: 0.15,
      color: palette.textColor,
    );

    final hlStart = widget.highlightStartOffset;
    final hlEnd = widget.highlightEndOffset;
    final hasSentenceHighlight =
        hlStart != null && hlEnd != null && hlEnd > hlStart;
    final sentenceHighlightColor = palette.brightness == Brightness.dark
        ? palette.underlineColor.withAlpha(64)
        : palette.underlineColor.withAlpha(34);

    final dragStart = _dragRangeStart;
    final dragEnd = _dragRangeEnd;
    final hasLiveDrag =
        dragStart != null && dragEnd != null && dragEnd > dragStart;

    final selStart = !widget.isUnderlineMode && hasLiveDrag
        ? dragStart
        : widget.selectedStartOffset;
    final selEnd = !widget.isUnderlineMode && hasLiveDrag
        ? dragEnd
        : widget.selectedEndOffset;
    final hasNormalSelection =
        selStart != null && selEnd != null && selEnd > selStart;
    final selectionFillColor = widget.markAccentColor.withAlpha(56);

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

      final isInSpokenSentence = hasSentenceHighlight &&
          segment.start < hlEnd &&
          segment.end > hlStart;
      final isInLiveDragErase = widget.isUnderlineMode &&
          _isDragErasing &&
          hasLiveDrag &&
          segment.start < dragEnd &&
          segment.end > dragStart;
      final isInLiveDragMark = widget.isUnderlineMode &&
          !_isDragErasing &&
          hasLiveDrag &&
          segment.start < dragEnd &&
          segment.end > dragStart;
      final isMarked =
          (segment.isUnderlined && !isInLiveDragErase) || isInLiveDragMark;
      final isInNormalSelection = !widget.isUnderlineMode &&
          hasNormalSelection &&
          segment.start < selEnd &&
          segment.end > selStart;

      TextStyle style;
      if (isInLiveDragErase) {
        style = baseStyle.copyWith(
          backgroundColor: Theme.of(context).colorScheme.error.withAlpha(58),
        );
      } else if (isInNormalSelection) {
        style = (isMarked
                ? _buildMarkedStyle(
                    baseStyle: baseStyle,
                    isInSpokenSentence: false,
                    sentenceHighlightColor: sentenceHighlightColor,
                  )
                : baseStyle)
            .copyWith(backgroundColor: selectionFillColor);
      } else if (isMarked) {
        style = _buildMarkedStyle(
          baseStyle: baseStyle,
          isInSpokenSentence: isInSpokenSentence,
          sentenceHighlightColor: sentenceHighlightColor,
        );
      } else if (isInSpokenSentence) {
        style = baseStyle.copyWith(
          backgroundColor: sentenceHighlightColor,
        );
      } else {
        style = baseStyle;
      }

      spans.add(
        TextSpan(
          text: segment.text,
          style: style,
          recognizer: recognizer,
        ),
      );
    }

    return GestureDetector(
      key: ValueKey<String>('reader_paragraph_gesture_${widget.paragraphIndex}'),
      behavior: HitTestBehavior.translucent,
      onLongPressStart: _handleLongPressStart,
      onLongPressMoveUpdate: _handleLongPressMove,
      onLongPressEnd: _handleLongPressEnd,
      onLongPressCancel: _handleLongPressCancel,
      child: RichText(
        key: _richTextKey,
        text: TextSpan(children: spans),
        textAlign: TextAlign.start,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
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
    final visuals = AppThemeVisuals.of(context);
    final palette = tone.resolvePalette(context);
    final isThemeChip = tone == ArticleReaderTone.appTheme;
    final toneLabel = switch (tone) {
      ArticleReaderTone.appTheme => s.toneTheme,
      ArticleReaderTone.white => s.toneWhite,
      ArticleReaderTone.paper => s.tonePaper,
      ArticleReaderTone.dark => s.toneDark,
    };

    return Material(
      color: isThemeChip && visuals.hasBackdrop
          ? Colors.transparent
          : palette.backgroundColor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('reader_tone_${tone.storageKey}'),
        onTap: onTap,
        child: Stack(
          children: <Widget>[
            if (isThemeChip && visuals.hasBackdrop)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: AppThemeMeshPainter(visuals.preset),
                  ),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              decoration: BoxDecoration(
                color: isThemeChip && visuals.hasBackdrop
                    ? visuals.readerPaperColor.withAlpha(175)
                    : null,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary
                      : palette.dividerColor,
                  width: isSelected ? 2.2 : 1.2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Aa',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: palette.textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    toneLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: palette.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionFloatingBar extends StatelessWidget {
  const _SelectionFloatingBar({
    required this.tone,
    required this.isUnderlineMode,
    required this.isPassageSelection,
    required this.hasExistingUnderline,
    required this.onUnderline,
    required this.onRemoveUnderline,
    required this.onLookupMeaning,
    required this.onTranslateParagraph,
    required this.onDismiss,
  });

  final ArticleReaderTone tone;
  final bool isUnderlineMode;
  final bool isPassageSelection;
  final bool hasExistingUnderline;
  final VoidCallback onUnderline;
  final VoidCallback onRemoveUnderline;
  final VoidCallback onLookupMeaning;
  final VoidCallback onTranslateParagraph;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final palette = tone.resolvePalette(context);
    return Material(
      elevation: 4,
      color: palette.surfaceColor,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.dividerColor),
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
                  color: palette.underlineColor,
                ),
                label: Text(
                  s.underlineAction,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.textColor,
                  ),
                ),
              ),
              if (hasExistingUnderline)
                TextButton.icon(
                  onPressed: onRemoveUnderline,
                  icon: Icon(
                    Icons.format_clear_rounded,
                    size: 18,
                    color: palette.secondaryTextColor,
                  ),
                  label: Text(
                    s.removeShort,
                    style: TextStyle(color: palette.secondaryTextColor),
                  ),
                ),
            ] else ...<Widget>[
              TextButton.icon(
                key: const ValueKey<String>('reader_selection_lookup_button'),
                onPressed: onLookupMeaning,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                icon: Icon(
                  Icons.translate_rounded,
                  size: 18,
                  color: palette.underlineColor,
                ),
                label: Text(
                  isPassageSelection
                      ? s.translateSelectionAction
                      : s.lookupMeaningAction,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.textColor,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 20,
                color: palette.dividerColor,
              ),
              TextButton.icon(
                key: const ValueKey<String>(
                  'reader_selection_translate_paragraph_button',
                ),
                onPressed: onTranslateParagraph,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                icon: Icon(
                  Icons.notes_rounded,
                  size: 18,
                  color: palette.secondaryTextColor,
                ),
                label: Text(
                  s.translateParagraphAction,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: palette.textColor,
                  ),
                ),
              ),
            ],
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: palette.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
