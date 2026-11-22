import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/tts/tts_service.dart';
import '../browser/browser_screen.dart';
import '../translation/services/word_translation_service.dart';
import '../words/models/word_list.dart';
import 'controllers/articles_controller.dart';
import 'data/article_reader_repository.dart';
import 'data/articles_cache_repository.dart';
import 'models/article_level.dart';
import 'screens/level_articles_screen.dart';
import 'services/articles_sync_service.dart';

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
    this.onAddWord,
    this.loadWordLists,
  });

  final ArticlesController? controller;
  final ArticleReaderStore? readerStore;
  final WordTranslationService? translationService;
  final TtsService? ttsService;
  final AddWordCallback? onAddWord;
  final Future<List<WordList>> Function()? loadWordLists;

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

  void _openLevel(ArticleLevel level) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LevelArticlesScreen(
          level: level,
          controller: _controller,
          readerStore: widget.readerStore,
          translationService: widget.translationService,
          ttsService: widget.ttsService,
          onAddWord: widget.onAddWord,
          loadWordLists: widget.loadWordLists,
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

        return Scaffold(
          appBar: AppBar(
            title: const Text('Makaleler'),
          ),
          body: Stack(
            children: <Widget>[
              RefreshIndicator(
                onRefresh: _handlePullToRefresh,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: ArticleLevel.values.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final level = ArticleLevel.values[index];
                    final count = countsByLevel[level] ?? 0;
                    return _ArticleLevelCard(
                      level: level,
                      articleCount: count,
                      onTap: () => _openLevel(level),
                    );
                  },
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
        );
      },
    );
  }
}

class _ArticleLevelCard extends StatelessWidget {
  const _ArticleLevelCard({
    required this.level,
    required this.articleCount,
    required this.onTap,
  });

  final ArticleLevel level;
  final int articleCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('article_level_card_${level.code}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      level.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      level.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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
                  '$articleCount makale',
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
    );
  }
}
