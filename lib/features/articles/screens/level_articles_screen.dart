import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/tts/tts_service.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../browser/browser_screen.dart';
import '../../translation/services/word_translation_service.dart';
import '../../words/models/word_list.dart';
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
    this.readerStore,
    this.translationService,
    this.ttsService,
    this.authController,
    this.onAddWord,
    this.loadWordLists,
  });

  final ArticleLevel level;
  final ArticlesController controller;
  final ArticleReaderStore? readerStore;
  final WordTranslationService? translationService;
  final TtsService? ttsService;
  final AuthController? authController;
  final AddWordCallback? onAddWord;
  final Future<List<WordList>> Function()? loadWordLists;

  @override
  State<LevelArticlesScreen> createState() => _LevelArticlesScreenState();
}

class _LevelArticlesScreenState extends State<LevelArticlesScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.startLiveCheck();
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
          translationService: widget.translationService,
          ttsService: widget.ttsService,
          authController: widget.authController,
          onAddWord: widget.onAddWord,
          loadWordLists: widget.loadWordLists,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final level = widget.level;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final levelArticles = widget.controller.articles
            .where((article) => article.parsedLevel == level)
            .toList(growable: false);
        final isRefreshing = widget.controller.isRefreshing;

        return Scaffold(
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
                    child: RefreshIndicator(
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
                                return _LevelArticleCard(
                                  article: article,
                                  accentColor: level.accentColor,
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
    required this.onTap,
  });

  final Article article;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final descriptionText = article.description.isNotEmpty
        ? article.description
        : 'Okumak için dokunun.';

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
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(24),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.schedule_rounded,
                          size: 15,
                          color: accentColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          article.formattedReadingTime,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
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
