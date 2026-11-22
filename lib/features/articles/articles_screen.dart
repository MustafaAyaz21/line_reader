import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import 'controllers/articles_controller.dart';
import 'data/articles_cache_repository.dart';
import 'models/article.dart';
import 'services/articles_sync_service.dart';

/// Ana Menü'deki "Makaleler" kısayolundan açılan ekran.
///
/// - Girişte yerel SQLite önbelleğini anında gösterir ve uzak `articles.json`
///   kaynağından güncel makaleleri sessizce kontrol eder.
/// - Aşağı çekerek yenileme (`RefreshIndicator`) destekler.
/// - Ağ bağlantısı olmadığında veya istek başarısız olduğunda mevcut
///   önbellekteki verileri bozmadan korumaya devam eder.
/// - Uzak kaynakta henüz makale yoksa sade "Yakında..." görünümünü korur.
class ArticlesScreen extends StatefulWidget {
  const ArticlesScreen({
    super.key,
    this.controller,
  });

  final ArticlesController? controller;

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
      _controller.onScreenEntered();
    });
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  Future<void> _handlePullToRefresh() async {
    final result = await _controller.refresh(silent: false, force: true);
    if (!mounted) return;

    if (result.isOfflineFallback) {
      final hasCached = result.articles.isNotEmpty;
      final message = hasCached
          ? 'İnternet bağlantısı yok. Önbellekteki makaleler korunuyor.'
          : 'Güncel makaleler kontrol edilemedi; çevrimdışı önbellek korunuyor.';
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

  void _openArticlePreview(Article article) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bodyText = article.content.isNotEmpty
        ? article.content
        : (article.summary.isNotEmpty
            ? article.summary
            : 'Bu makalenin içeriği yakında eklenecek.');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.94,
          builder: (_, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: <Widget>[
                if (article.category.isNotEmpty || article.level.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: <Widget>[
                        if (article.level.isNotEmpty)
                          _MetaBadge(
                            label: article.level,
                            backgroundColor: colorScheme.primaryContainer,
                            textColor: colorScheme.onPrimaryContainer,
                          ),
                        if (article.category.isNotEmpty)
                          _MetaBadge(
                            label: article.category,
                            backgroundColor: colorScheme.secondaryContainer,
                            textColor: colorScheme.onSecondaryContainer,
                          ),
                        if (article.readingTimeMinutes > 0)
                          _MetaBadge(
                            label: '${article.readingTimeMinutes} dk',
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            textColor: colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                Text(
                  article.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (article.author.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    article.author,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SelectableText(
                  bodyText,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.65,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final articles = _controller.articles;
        final isRefreshing = _controller.isRefreshing;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Makaleler'),
          ),
          body: Stack(
            children: <Widget>[
              RefreshIndicator(
                onRefresh: _handlePullToRefresh,
                child: articles.isEmpty
                    ? _buildComingSoonView(context)
                    : _buildArticlesListView(context, articles),
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

  Widget _buildComingSoonView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          size: 40,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Yakında...',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'İnternet olmadan okuyup kelime çalışabileceğiniz özenle seçilmiş makaleler çok yakında burada yer alacak.',
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

  Widget _buildArticlesListView(BuildContext context, List<Article> articles) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: articles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final article = articles[index];
        return _ArticleCard(
          article: article,
          onTap: () => _openArticlePreview(article),
        );
      },
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.article,
    required this.onTap,
  });

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
              if (article.level.isNotEmpty ||
                  article.category.isNotEmpty ||
                  article.readingTimeMinutes > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      if (article.level.isNotEmpty)
                        _MetaBadge(
                          label: article.level,
                          backgroundColor: colorScheme.primaryContainer,
                          textColor: colorScheme.onPrimaryContainer,
                        ),
                      if (article.category.isNotEmpty)
                        _MetaBadge(
                          label: article.category,
                          backgroundColor: colorScheme.secondaryContainer,
                          textColor: colorScheme.onSecondaryContainer,
                        ),
                      if (article.readingTimeMinutes > 0)
                        _MetaBadge(
                          label: '${article.readingTimeMinutes} dk',
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          textColor: colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              Text(
                article.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              if (article.summary.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  article.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
