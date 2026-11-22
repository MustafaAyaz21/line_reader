import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/tts/tts_service.dart';
import '../models/article.dart';
import '../services/article_passage_translation_service.dart';

/// Makale ekranında seçilen cümle veya tam paragrafın Türkçe çevirisini
/// sürüklenebilir, taşma yapmayan temiz alt panelde gösterir.
class ArticlePassageTranslationSheet extends StatefulWidget {
  const ArticlePassageTranslationSheet({
    super.key,
    required this.article,
    required this.selectedText,
    required this.translator,
    required this.isFullParagraph,
    this.paragraphIndex,
    this.fullParagraphText,
    this.ttsService,
  });

  final Article article;
  final String selectedText;
  final ArticlePassageTranslator translator;
  final bool isFullParagraph;
  final int? paragraphIndex;
  final String? fullParagraphText;
  final TtsService? ttsService;

  static Future<void> show(
    BuildContext context, {
    required Article article,
    required String selectedText,
    required ArticlePassageTranslator translator,
    required bool isFullParagraph,
    int? paragraphIndex,
    String? fullParagraphText,
    TtsService? ttsService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ArticlePassageTranslationSheet(
        article: article,
        selectedText: selectedText,
        translator: translator,
        isFullParagraph: isFullParagraph,
        paragraphIndex: paragraphIndex,
        fullParagraphText: fullParagraphText,
        ttsService: ttsService,
      ),
    );
  }

  @override
  State<ArticlePassageTranslationSheet> createState() =>
      _ArticlePassageTranslationSheetState();
}

class _ArticlePassageTranslationSheetState
    extends State<ArticlePassageTranslationSheet> {
  PassageTranslationResult? _result;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTranslation();
  }

  @override
  void dispose() {
    widget.ttsService?.stop(notify: false);
    super.dispose();
  }

  Future<void> _loadTranslation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final translated = await widget.translator.translate(
        article: widget.article,
        selectedText: widget.selectedText,
        paragraphIndex: widget.paragraphIndex,
        fullParagraphText: widget.fullParagraphText,
      );
      if (!mounted) return;
      setState(() {
        _result = translated;
        _isLoading = false;
      });
    } on PassageTranslationException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = context.l10n.t(
          'Metin çevrilirken beklenmeyen bir sorun oluştu.',
          'An unexpected error occurred while translating the passage.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSpeakOriginal() async {
    final tts = widget.ttsService;
    if (tts == null) return;
    await tts.toggleSpeak(
      text: widget.selectedText,
      target: TtsSpeakingTarget.sentence,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tts = widget.ttsService;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.52,
      minChildSize: 0.32,
      maxChildSize: 0.86,
      snap: true,
      snapSizes: const <double>[0.36, 0.54, 0.84],
      builder: (context, scrollController) {
        return Container(
          key: const ValueKey<String>('article_passage_translation_sheet'),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Colors.black12,
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: <Widget>[
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
              Row(
                children: <Widget>[
                  Icon(
                    Icons.translate_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isFullParagraph
                          ? s.paragraphTranslationTitle
                          : s.sentenceTranslationTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_result != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _result!.isFromArticlePreset
                            ? colorScheme.secondaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _result!.isFromArticlePreset
                            ? s.presetTranslationBadge
                            : s.liveTranslationBadge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _result!.isFromArticlePreset
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (tts != null) ...<Widget>[
                    const SizedBox(width: 4),
                    ListenableBuilder(
                      listenable: tts,
                      builder: (context, _) {
                        final isSpeaking =
                            tts.speakingTarget == TtsSpeakingTarget.sentence;
                        return IconButton.filledTonal(
                          onPressed: _handleSpeakOriginal,
                          icon: Icon(
                            isSpeaking
                                ? Icons.stop_rounded
                                : Icons.volume_up_rounded,
                            size: 19,
                          ),
                          tooltip: isSpeaking ? 'Durdur' : 'Dinle',
                          visualDensity: VisualDensity.compact,
                        );
                      },
                    ),
                  ],
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: s.close,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Türkçe çeviri kutusu (en üstte ve belirgin)
              if (_isLoading)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.t(
                            'Türkçe çeviri hazırlanıyor...',
                            'Preparing Turkish translation...',
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_result != null)
                Container(
                  key: const ValueKey<String>('passage_translated_text_box'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.t('Türkçe Çeviri', 'Turkish Translation'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _result!.translatedText,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          height: 1.58,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withAlpha(180),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _errorMessage ??
                            s.t('Çeviri alınamadı.', 'Translation failed.'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _loadTranslation,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(s.retry),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),

              // Orijinal İngilizce metin kutusu
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.t('Seçilen Metin', 'Selected Text'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.selectedText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
