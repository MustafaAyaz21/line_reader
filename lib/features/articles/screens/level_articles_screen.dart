import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_backdrop.dart';
import '../../../core/tts/tts_service.dart';
import '../../../core/widgets/line_refresh_indicator.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../browser/browser_screen.dart';
import '../../translation/services/word_translation_service.dart';
import '../../words/models/word_list.dart';
import '../controllers/article_reading_progress_controller.dart';
import '../controllers/articles_controller.dart';
import '../data/article_reader_repository.dart';
import '../models/article.dart';
import '../models/article_level.dart';
import '../widgets/new_articles_banner.dart';
import 'article_reader_screen.dart';

/// Seçilen CEFR seviyesine (A1–C2) ait makaleleri listeleyen ekran.
///
/// Her kartta makale başlığı, kısa açıklama (`description`) ve ortalama okuma
/// süresi (`5 - 8 dk`, `4 - 6 dk` vb.) net biçimde gösterilir.
class LevelArticlesScreen extends StatefulWidget {
  const LevelArticlesScreen({
    super.key,
    required this.level,
    required this.controller,
    this.readingProgressController,
    this.readerStore,
    this.translationService,
    this.ttsService,
    this.authController,
    this.onAddWord,
    this.onAddWordWithLexicon,
    this.loadWordLists,
    this.onCreateWordList,
  });

  final ArticleLevel level;
  final ArticlesController controller;
  final ArticleReadingProgressController? readingProgressController;
  final ArticleReaderStore? readerStore;
  final WordTranslationService? translationService;
  final TtsService? ttsService;
  final AuthController? authController;
  final AddWordCallback? onAddWord;
  final AddWordWithLexiconCallback? onAddWordWithLexicon;
  final Future<List<WordList>> Function()? loadWordLists;
  final CreateWordListCallback? onCreateWordList;

  @override
  State<LevelArticlesScreen> createState() => _LevelArticlesScreenState();
}

class _LevelArticlesScreenState extends State<LevelArticlesScreen> {
  ArticleReadingProgressController get _progressController =>
      widget.readingProgressController ??
      ArticleReadingProgressController.shared;

  @override
  void initState() {
    super.initState();
    widget.controller.startLiveCheck();
    _progressController.load();
  }

  @override
  void dispose() {
    widget.controller.stopLiveCheck();
    super.dispose();
  }

  Future<void> _handlePullToRefresh() async {
    final result = await widget.controller.refresh(silent: false, force: true);
    if (!mounted) return;

    if (result.isOfflineFallback) {
      final s = context.l10n;
      final hasCached = result.articles.isNotEmpty;
      final message = hasCached
          ? s.t(
              'İnternet bağlantısı yok. Önbellekteki makaleler korunuyor.',
              'No internet connection. Cached articles are preserved.',
            )
          : s.t(
              'Güncel makaleler kontrol edilemedi; çevrimdışı önbellek korunuyor.',
              'Could not check for new articles; offline cache preserved.',
            );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  void _openArticleReader(Article article) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ArticleReaderScreen(
          article: article,
          readerStore: widget.readerStore,
          readingProgressController: _progressController,
          translationService: widget.translationService,
          ttsService: widget.ttsService,
          authController: widget.authController,
          onAddWord: widget.onAddWord,
          onAddWordWithLexicon: widget.onAddWordWithLexicon,
          loadWordLists: widget.loadWordLists,
          onCreateWordList: widget.onCreateWordList,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final level = widget.level;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.controller,
        _progressController,
      ]),
      builder: (context, _) {
        final levelArticles = widget.controller.articles
            .where((article) => article.parsedLevel == level)
            .toList(growable: false);
        final isRefreshing = widget.controller.isRefreshing;

        final visuals = AppThemeVisuals.of(context);

        return AppThemeBackdrop(
          child: Scaffold(
            backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
            appBar: AppBar(
              title: Text('${level.code} • ${s.levelLabel(level.code)}'),
            ),
          body: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  NewArticlesBanner(
                    totalNewCount: widget.controller.pendingNewArticlesCount,
                    level: level,
                    levelNewCount:
                        widget.controller.pendingNewCountForLevel(level),
                    onRefreshPressed: widget.controller.applyPendingArticles,
                  ),
                  Expanded(
                    child: LineRefreshIndicator(
                      onRefresh: _handlePullToRefresh,
                      child: levelArticles.isEmpty
                          ? _buildEmptyState(context, level)
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 28),
                              itemCount: levelArticles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final article = levelArticles[index];
                                final isCompleted = _progressController
                                        .progressForArticle(article.id)
                                        ?.isCompleted ??
                                    false;
                                return _LevelArticleCard(
                                  article: article,
                                  accentColor: level.accentColor,
                                  isCompleted: isCompleted,
                                  onTap: () => _openArticleReader(article),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
              if (isRefreshing)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, ArticleLevel level) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final levelLabel = s.levelLabel(level.code);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: level.accentColor.withAlpha(28),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          level.code,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: level.accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        s.t(
                          'Bu seviyede henüz makale yok',
                          'No articles in this level yet',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.t(
                          '${level.code} ($levelLabel) seviyesi için yeni makaleler eklendiğinde burada otomatik olarak listelenecektir. Aşağı çekerek yenileyebilirsiniz.',
                          'New articles for ${level.code} ($levelLabel) will appear here automatically once published. Pull down to refresh.',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LevelArticleCard extends StatelessWidget {
  const _LevelArticleCard({
    required this.article,
    required this.accentColor,
    this.isCompleted = false,
    required this.onTap,
  });

  final Article article;
  final Color accentColor;
  final bool isCompleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final completedColor =
        isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    final podcastColor =
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    final categoryText = article.category?.trim() ?? '';
    final authorText = article.author?.trim() ?? '';
    final descriptionText = article.description.isNotEmpty
        ? article.description
        : s.t('Okumak için dokunun.', 'Tap to read.');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          article.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          descriptionText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (article.imageUrl != null && article.imageUrl!.isNotEmpty) ...[
                    const SizedBox(width: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        article.imageUrl!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _CardMetaChip(
                          icon: Icons.schedule_rounded,
                          label: article.formattedReadingTime,
                          foreground: accentColor,
                          background: accentColor.withAlpha(24),
                        ),
                        if (categoryText.isNotEmpty)
                          _CardMetaChip(
                            icon: Icons.label_outline_rounded,
                            label: categoryText,
                            foreground: colorScheme.onSurfaceVariant,
                            background: colorScheme.surfaceContainerHighest
                                .withAlpha(150),
                          ),
                        if (article.hasPodcastAudio)
                          _CardMetaChip(
                            icon: Icons.podcasts_rounded,
                            label: 'Podcast AI',
                            foreground: podcastColor,
                            background: podcastColor.withAlpha(28),
                          ),
                        if (authorText.isNotEmpty)
                          _CardMetaChip(
                            icon: Icons.person_outline_rounded,
                            label: authorText,
                            foreground: colorScheme.onSurfaceVariant,
                            background: colorScheme.surfaceContainerHighest
                                .withAlpha(150),
                          ),
                        if (isCompleted)
                          _CardMetaChip(
                            key: ValueKey<String>(
                              'article_completed_badge_${article.id}',
                            ),
                            icon: Icons.check_circle_rounded,
                            label: s.t('Tamamlandı', 'Completed'),
                            foreground: completedColor,
                            background: completedColor.withAlpha(28),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMetaChip extends StatelessWidget {
  const _CardMetaChip({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
