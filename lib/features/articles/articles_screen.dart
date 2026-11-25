import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_theme_backdrop.dart';
import '../../core/tts/tts_service.dart';
import '../../core/widgets/line_refresh_indicator.dart';
import '../auth/controllers/auth_controller.dart';
import '../browser/browser_screen.dart';
import '../translation/services/word_translation_service.dart';
import '../words/models/word_list.dart';
import 'controllers/articles_controller.dart';
import 'data/article_reader_repository.dart';
import 'data/articles_cache_repository.dart';
import 'models/article_level.dart';
import 'screens/level_articles_screen.dart';
import 'services/articles_sync_service.dart';
import 'widgets/new_articles_banner.dart';

/// Ana Menü'deki "Makaleler" kartından açılan A1–C2 seviye seçim ekranı.
///
/// - Alt alta düzenli kartlar halinde sırasıyla A1, A2, B1, B2, C1, C2
///   seviyelerini, kısa etiketlerini ve her seviyedeki canlı makale sayısını
///   gösterir.
/// - Girişte yerel SQLite önbelleğini anında yükler ve uzak `articles.json`
///   kaynağından güncel makaleleri sessizce kontrol eder.
/// - Aşağı çekerek yenileme (`RefreshIndicator`) ve çevrimdışı önbellek
///   koruması ile tam uyumlu çalışır.
class ArticlesScreen extends StatefulWidget {
  const ArticlesScreen({
    super.key,
    this.controller,
    this.readerStore,
    this.translationService,
    this.ttsService,
    this.authController,
    this.onAddWord,
    this.onAddWordWithLexicon,
    this.loadWordLists,
    this.onCreateWordList,
  });

  final ArticlesController? controller;
  final ArticleReaderStore? readerStore;
  final WordTranslationService? translationService;
  final TtsService? ttsService;
  final AuthController? authController;
  final AddWordCallback? onAddWord;
  final AddWordWithLexiconCallback? onAddWordWithLexicon;
  final Future<List<WordList>> Function()? loadWordLists;
  final CreateWordListCallback? onCreateWordList;

  @override
  State<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends State<ArticlesScreen> {
  ArticlesController? _ownedController;

  ArticlesController get _controller => widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = ArticlesController(
        ArticlesSyncService(
          cacheStore: ArticlesCacheRepository(AppDatabase.instance),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.startLiveCheck();
      _controller.onScreenEntered();
    });
  }

  @override
  void dispose() {
    _controller.stopLiveCheck();
    _ownedController?.dispose();
    super.dispose();
  }

  Future<void> _handlePullToRefresh() async {
    final result = await _controller.refresh(silent: false, force: true);
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

  void _openLevel(ArticleLevel level) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LevelArticlesScreen(
          level: level,
          controller: _controller,
          readerStore: widget.readerStore,
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
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final articles = _controller.articles;
        final isRefreshing = _controller.isRefreshing;

        final countsByLevel = <ArticleLevel, int>{
          for (final level in ArticleLevel.values) level: 0,
        };
        for (final article in articles) {
          final parsed = article.parsedLevel;
          if (parsed != null) {
            countsByLevel[parsed] = (countsByLevel[parsed] ?? 0) + 1;
          }
        }

        final visuals = AppThemeVisuals.of(context);

        return AppThemeBackdrop(
          child: Scaffold(
            backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
            appBar: AppBar(
              title: Text(context.l10n.articlesTitle),
            ),
          body: Stack(
            children: <Widget>[
              SafeArea(
                top: false,
                child: Column(
                  children: <Widget>[
                    NewArticlesBanner(
                      totalNewCount: _controller.pendingNewArticlesCount,
                      onRefreshPressed: _controller.applyPendingArticles,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const topPadding = 12.0;
                          const bottomPadding = 16.0;
                          const spacing = 12.0;
                          const minCardHeight = 88.0;
                          final count = ArticleLevel.values.length;
                          final minTotalHeight =
                              count * minCardHeight + (count - 1) * spacing;
                          final viewportHeight =
                              constraints.maxHeight - topPadding - bottomPadding;
                          final targetHeight = viewportHeight > minTotalHeight
                              ? viewportHeight
                              : minTotalHeight;

                          return LineRefreshIndicator(
                            onRefresh: _handlePullToRefresh,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                topPadding,
                                16,
                                bottomPadding,
                              ),
                              child: SizedBox(
                                height: targetHeight,
                                child: Column(
                                  children: <Widget>[
                                    for (var i = 0; i < count; i++) ...<Widget>[
                                      Expanded(
                                        child: _ArticleLevelCard(
                                          level: ArticleLevel.values[i],
                                          articleCount: countsByLevel[
                                                  ArticleLevel.values[i]] ??
                                              0,
                                          pendingNewCount: _controller
                                              .pendingNewCountForLevel(
                                            ArticleLevel.values[i],
                                          ),
                                          onTap: () => _openLevel(
                                            ArticleLevel.values[i],
                                          ),
                                        ),
                                      ),
                                      if (i < count - 1)
                                        const SizedBox(height: spacing),
                                    ],
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
}

class _ArticleLevelCard extends StatelessWidget {
  const _ArticleLevelCard({
    required this.level,
    required this.articleCount,
    this.pendingNewCount = 0,
    required this.onTap,
  });

  final ArticleLevel level;
  final int articleCount;
  final int pendingNewCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('article_level_card_${level.code}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Center(
            child: Row(
              children: <Widget>[
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: level.accentColor.withAlpha(28),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    level.code,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: level.accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.levelLabel(level.code),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.levelSubtitle(level.code),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (pendingNewCount > 0) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '+$pendingNewCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    s.articleCountLabel(articleCount),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
