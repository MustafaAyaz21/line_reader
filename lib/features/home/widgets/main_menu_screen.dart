import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/api_key_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/tts/tts_service.dart';
import '../../../core/widgets/line_loading_indicator.dart';
import '../../articles/controllers/article_reading_progress_controller.dart';
import '../../articles/controllers/articles_controller.dart';
import '../../articles/models/article.dart';
import '../../articles/models/article_level.dart';
import '../../articles/models/article_reading_progress.dart';
import '../../articles/screens/article_reader_screen.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/screens/auth_screen.dart';
import '../../browser/browser_screen.dart';
import '../../settings/screens/how_to_use_screen.dart';
import '../../settings/widgets/api_key_dialog.dart';
import '../../settings/widgets/settings_action_button.dart';
import '../../translation/services/word_translation_service.dart';
import '../../update/controllers/app_update_controller.dart';
import '../../update/widgets/update_action_button.dart';
import '../../words/models/word_list.dart';

/// Uygulamanın Ana Menü ekranı.
/// Masaüstü / Web'de geniş ekranda Konsept 1 modern keşif paneli (Arama, Seviye Filtreleri,
/// Öne Çıkan Hero Makale ve 3'lü Makale Izgarası) sunar. Mobilde ise sade ve dokunmatik
/// kart düzenini korur.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({
    super.key,
    required this.onOpenBrowser,
    required this.apiKeyController,
    this.localeController,
    this.authController,
    this.updateController,
    this.articlesController,
    this.readingProgressController,
    this.translationService,
    this.ttsService,
    this.onAddWord,
    this.onAddWordWithLexicon,
    this.loadWordLists,
    this.onCreateWordList,
    this.onClearCache,
  });

  final VoidCallback onOpenBrowser;
  final ApiKeyController apiKeyController;
  final AppLocaleController? localeController;
  final AuthController? authController;
  final AppUpdateController? updateController;
  final ArticlesController? articlesController;
  final ArticleReadingProgressController? readingProgressController;
  final WordTranslationService? translationService;
  final TtsService? ttsService;
  final AddWordCallback? onAddWord;
  final AddWordWithLexiconCallback? onAddWordWithLexicon;
  final Future<List<WordList>> Function()? loadWordLists;
  final CreateWordListCallback? onCreateWordList;
  final Future<void> Function()? onClearCache;

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final TextEditingController _searchController = TextEditingController();
  ArticleLevel? _selectedLevel;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openResumeArticle(
    BuildContext context,
    Article article,
    ArticleReadingProgressController progressController,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ArticleReaderScreen(
          article: article,
          readingProgressController: progressController,
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

  Article? _findVisibleArticleById(String articleId) {
    final controller = widget.articlesController;
    if (controller == null) return null;
    for (final article in controller.articles) {
      if (article.id == articleId) {
        return article;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width >= 840;
    final progressController = widget.readingProgressController ??
        ArticleReadingProgressController.shared;

    final listenables = <Listenable>[
      progressController,
      if (widget.articlesController != null) widget.articlesController!,
    ];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        if (isWideScreen) {
          return _buildDesktopLayout(context, progressController);
        }
        return _buildMobileLayout(context, progressController);
      },
    );
  }

  // ==========================================
  // DESKTOP KONSEPT 1 LAYOUT
  // ==========================================
  Widget _buildDesktopLayout(
    BuildContext context,
    ArticleReadingProgressController progressController,
  ) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final visuals = AppThemeVisuals.of(context);

    final allArticles = widget.articlesController?.articles ?? const <Article>[];
    final query = _searchController.text.trim().toLowerCase();

    final filteredArticles = allArticles.where((a) {
      if (_selectedLevel != null && a.level.isNotEmpty) {
        final parsed = ArticleLevel.tryParse(a.level);
        if (parsed != _selectedLevel) return false;
      }
      if (query.isNotEmpty) {
        final titleMatch = a.title.toLowerCase().contains(query);
        final descMatch = a.description.toLowerCase().contains(query);
        final categoryMatch = a.category.toLowerCase().contains(query);
        final wordMeaningMatch = a.wordMeanings.entries.any((entry) {
          return entry.key.toLowerCase().contains(query) ||
              entry.value.toLowerCase().contains(query);
        });
        final contentMatch =
            query.length >= 3 && a.content.toLowerCase().contains(query);

        if (!titleMatch &&
            !descMatch &&
            !categoryMatch &&
            !wordMeaningMatch &&
            !contentMatch) {
          return false;
        }
      }
      return true;
    }).toList();

    final heroArticle = filteredArticles.isNotEmpty ? filteredArticles.first : null;
    final gridArticles =
        filteredArticles.length > 1 ? filteredArticles.sublist(1) : filteredArticles;

    return Scaffold(
      backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Search Bar, CEFR Level Pills, Top Actions
            Container(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(40),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Search Bar
                  Expanded(
                    child: Container(
                      height: 42,
                      constraints: const BoxConstraints(maxWidth: 380),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF161B22)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withAlpha(50),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintText: s.t(
                                  'Makale veya kelime ara...',
                                  'Search articles or words...',
                                ),
                                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant.withAlpha(160),
                                ),
                              ),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withAlpha(40),
                                ),
                              ),
                              child: Text(
                                'Ctrl+K',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Level Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FilterChip(
                          label: s.t('Tümü', 'All'),
                          isSelected: _selectedLevel == null,
                          onTap: () => setState(() => _selectedLevel = null),
                        ),
                        const SizedBox(width: 6),
                        ...ArticleLevel.values.map(
                          (lvl) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _FilterChip(
                              label: lvl.code,
                              isSelected: _selectedLevel == lvl,
                              accentColor: lvl.accentColor,
                              onTap: () => setState(() => _selectedLevel = lvl),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Actions
                  IconButton(
                    key: const ValueKey<String>('main_menu_how_to_use_desktop'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const HowToUseScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.help_outline_rounded),
                    tooltip: s.t('Nasıl Kullanılır?', 'How to Use'),
                  ),
                  if (!kIsWeb && widget.updateController != null)
                    UpdateActionButton(controller: widget.updateController!),
                  if (widget.localeController != null && widget.authController != null)
                    SettingsActionButton(
                      apiKeyController: widget.apiKeyController,
                      localeController: widget.localeController!,
                      authController: widget.authController!,
                      onClearCache: widget.onClearCache,
                    )
                  else
                    ApiKeyActionButton(
                      controller: widget.apiKeyController,
                      onClearCache: widget.onClearCache,
                    ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: allArticles.isEmpty &&
                      (widget.articlesController?.isLoadingCache ?? false)
                  ? const Center(
                      child: LineLoadingIndicator(
                        message: 'Makaleler yükleniyor...',
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Continue reading banner if any
                          Builder(
                            builder: (context) {
                              final lastProgress = progressController.lastProgress;
                              if (lastProgress == null ||
                                  lastProgress.isCompleted ||
                                  progressController.isContinueReadingDismissed(
                                    lastProgress.articleId,
                                  )) {
                                return const SizedBox.shrink();
                              }
                              final article =
                                  _findVisibleArticleById(lastProgress.articleId);
                              if (article == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: _ContinueReadingCard(
                                  article: article,
                                  progress: lastProgress,
                                  onTap: () => _openResumeArticle(
                                    context,
                                    article,
                                    progressController,
                                  ),
                                  onDismiss: () => progressController
                                      .dismissContinueReading(lastProgress.articleId),
                                ),
                              );
                            },
                          ),

                          // Hero Featured Article Banner
                          if (heroArticle != null) ...[
                            _DesktopHeroBanner(
                              article: heroArticle,
                              onReadNow: () => _openResumeArticle(
                                context,
                                heroArticle,
                                progressController,
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],

                          // Section Header
                          Row(
                            children: [
                              Text(
                                s.t('Öne Çıkan Makaleler', 'Featured Articles'),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${filteredArticles.length} ${s.t('makale', 'articles')}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Article Grid (3 columns on wide desktop, 2 on medium)
                          if (filteredArticles.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(40),
                              alignment: Alignment.center,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 48,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    s.t(
                                      'Aramanızla eşleşen makale bulunamadı',
                                      'No articles match your search',
                                    ),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _selectedLevel = null);
                                    },
                                    child: Text(s.t('Filtreyi Temizle', 'Clear Filter')),
                                  ),
                                ],
                              ),
                            )
                          else
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final int columns =
                                    constraints.maxWidth >= 1080 ? 3 : 2;
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: gridArticles.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 16,
                                    childAspectRatio: 1.4,
                                  ),
                                  itemBuilder: (context, index) {
                                    final art = gridArticles[index];
                                    final lvl = ArticleLevel.tryParse(art.level);
                                    return _DesktopArticleCard(
                                      article: art,
                                      level: lvl,
                                      onTap: () => _openResumeArticle(
                                        context,
                                        art,
                                        progressController,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MOBILE MODERN LAYOUT
  // ==========================================
  Widget _buildMobileLayout(
    BuildContext context,
    ArticleReadingProgressController progressController,
  ) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final visuals = AppThemeVisuals.of(context);

    final allArticles = widget.articlesController?.articles ?? const <Article>[];
    final query = _searchController.text.trim().toLowerCase();

    final filteredArticles = allArticles.where((a) {
      if (_selectedLevel != null && a.level.isNotEmpty) {
        final parsed = ArticleLevel.tryParse(a.level);
        if (parsed != _selectedLevel) return false;
      }
      if (query.isNotEmpty) {
        final titleMatch = a.title.toLowerCase().contains(query);
        final descMatch = a.description.toLowerCase().contains(query);
        final categoryMatch = a.category.toLowerCase().contains(query);
        final wordMeaningMatch = a.wordMeanings.entries.any((entry) {
          return entry.key.toLowerCase().contains(query) ||
              entry.value.toLowerCase().contains(query);
        });
        final contentMatch =
            query.length >= 3 && a.content.toLowerCase().contains(query);

        if (!titleMatch &&
            !descMatch &&
            !categoryMatch &&
            !wordMeaningMatch &&
            !contentMatch) {
          return false;
        }
      }
      return true;
    }).toList();

    final heroArticle = filteredArticles.isNotEmpty ? filteredArticles.first : null;
    final feedArticles =
        filteredArticles.length > 1 ? filteredArticles.sublist(1) : filteredArticles;

    return Scaffold(
      backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0B0F17) : colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withAlpha(30),
                    blurRadius: 8,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/app_logo.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Line Reader',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          if (!kIsWeb && widget.updateController != null)
            UpdateActionButton(controller: widget.updateController!),
          IconButton(
            key: const ValueKey<String>('main_menu_how_to_use_button'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HowToUseScreen(),
                ),
              );
            },
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: s.t('Nasıl Kullanılır?', 'How to Use'),
          ),
          if (widget.localeController != null && widget.authController != null)
            SettingsActionButton(
              apiKeyController: widget.apiKeyController,
              localeController: widget.localeController!,
              authController: widget.authController!,
              onClearCache: widget.onClearCache,
            )
          else
            ApiKeyActionButton(
              controller: widget.apiKeyController,
              onClearCache: widget.onClearCache,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await widget.articlesController?.refresh(force: true);
        },
        child: allArticles.isEmpty && (widget.articlesController?.isLoadingCache ?? false)
            ? const Center(
                child: LineLoadingIndicator(
                  message: 'Makaleler yükleniyor...',
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search Bar
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141923) : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withAlpha(50),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: s.t(
                                  'Makale, konu veya kelime ara...',
                                  'Search articles, topics or words...',
                                ),
                                hintStyle: TextStyle(
                                  fontSize: 13.5,
                                  color: colorScheme.onSurfaceVariant.withAlpha(160),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Guest Sign In Banner (if guest)
                    if (widget.authController != null)
                      ListenableBuilder(
                        listenable: widget.authController!,
                        builder: (context, _) {
                          if (widget.authController!.isAuthenticated ||
                              widget.authController!.isLoading) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _GuestSignInBanner(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<bool>(
                                    builder: (_) => AuthScreen(
                                      controller: widget.authController!,
                                      canPop: true,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),

                    // Continue Reading Banner (if progress exists)
                    Builder(
                      builder: (context) {
                        final lastProgress = progressController.lastProgress;
                        if (lastProgress == null ||
                            lastProgress.isCompleted ||
                            progressController.isContinueReadingDismissed(
                              lastProgress.articleId,
                            )) {
                          return const SizedBox.shrink();
                        }
                        final article = _findVisibleArticleById(lastProgress.articleId);
                        if (article == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: _ContinueReadingCard(
                            article: article,
                            progress: lastProgress,
                            onTap: () => _openResumeArticle(
                              context,
                              article,
                              progressController,
                            ),
                            onDismiss: () => progressController
                                .dismissContinueReading(lastProgress.articleId),
                          ),
                        );
                      },
                    ),

                    // CEFR Level Filter Row (Lower down, thumb-friendly 38px)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('SEVİYE FİLTRESİ', 'LEVEL FILTER'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: colorScheme.onSurfaceVariant.withAlpha(160),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _MobileLevelPill(
                                  label: s.t('Tümü (${allArticles.length})', 'All (${allArticles.length})'),
                                  isSelected: _selectedLevel == null,
                                  accentColor: colorScheme.primary,
                                  onTap: () => setState(() => _selectedLevel = null),
                                ),
                                const SizedBox(width: 8),
                                ...ArticleLevel.values.map((lvl) {
                                  final count = allArticles
                                      .where((a) => ArticleLevel.tryParse(a.level) == lvl)
                                      .length;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _MobileLevelPill(
                                      label: '${lvl.code} ($count)',
                                      isSelected: _selectedLevel == lvl,
                                      accentColor: lvl.accentColor,
                                      onTap: () => setState(() => _selectedLevel = lvl),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Featured Hero Banner (Mobile)
                    if (heroArticle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: _MobileHeroCard(
                          article: heroArticle,
                          onTap: () => _openResumeArticle(
                            context,
                            heroArticle,
                            progressController,
                          ),
                        ),
                      ),

                    // Recent Articles Section Header
                    Padding(
                      padding: const EdgeInsets.only(top: 22, bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.t('Yeni Makaleler', 'Recent Articles'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            s.t('${filteredArticles.length} makale', '${filteredArticles.length} articles'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Articles Feed List
                    if (filteredArticles.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 44,
                              color: colorScheme.onSurfaceVariant.withAlpha(120),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              s.t('Bu filtreye uygun makale bulunamadı.', 'No articles found matching this filter.'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: feedArticles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final art = feedArticles[index];
                          final lvl = ArticleLevel.tryParse(art.level);
                          return _MobileArticleFeedCard(
                            article: art,
                            level: lvl,
                            onTap: () => _openResumeArticle(
                              context,
                              art,
                              progressController,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ==========================================
// MOBILE LEVEL PILL
// ==========================================
class _MobileLevelPill extends StatelessWidget {
  const _MobileLevelPill({
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withAlpha(35)
                : (isDark ? const Color(0xFF141923) : theme.colorScheme.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accentColor : theme.colorScheme.outlineVariant.withAlpha(50),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isSelected ? accentColor : theme.colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MOBILE HERO CARD
// ==========================================
class _MobileHeroCard extends StatelessWidget {
  const _MobileHeroCard({
    required this.article,
    required this.onTap,
  });

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final level = ArticleLevel.tryParse(article.level);
    final accent = level?.accentColor ?? colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141924) : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withAlpha(70),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 40 : 10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (article.imageUrl != null && article.imageUrl!.isNotEmpty)
                Stack(
                  children: [
                    Image.network(
                      article.imageUrl!,
                      height: 135,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              level?.code ?? 'B1',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (article.hasPodcastAudio) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(180),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: const Color(0xFFFBBF24).withAlpha(120),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.mic_rounded, size: 12, color: Color(0xFFFBBF24)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Podcast AI',
                                    style: TextStyle(
                                      color: Color(0xFFFBBF24),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      article.description.isNotEmpty ? article.description : article.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '⏱ ${article.readingTimeMinutes > 0 ? '${article.readingTimeMinutes} dk okuma' : '3 dk okuma'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: onTap,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent.withAlpha(40),
                            foregroundColor: accent,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          child: const Text(
                            'Hemen Oku',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MOBILE ARTICLE FEED CARD
// ==========================================
class _MobileArticleFeedCard extends StatelessWidget {
  const _MobileArticleFeedCard({
    required this.article,
    this.level,
    required this.onTap,
  });

  final Article article;
  final ArticleLevel? level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = level?.accentColor ?? colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141923) : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(50),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(30),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            level?.code ?? 'B1',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          article.readingTimeMinutes > 0 ? '${article.readingTimeMinutes} dk' : '3 dk',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                        if (article.hasPodcastAudio) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.mic_rounded, size: 14, color: Color(0xFFFBBF24)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      article.description.isNotEmpty ? article.description : article.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (article.imageUrl != null && article.imageUrl!.isNotEmpty) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
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
        ),
      ),
    );
  }
}

// ==========================================
// DESKTOP HERO BANNER
// ==========================================
class _DesktopHeroBanner extends StatelessWidget {
  const _DesktopHeroBanner({
    required this.article,
    required this.onReadNow,
  });

  final Article article;
  final VoidCallback onReadNow;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final level = ArticleLevel.tryParse(article.level);
    final accent = level?.accentColor ?? colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: isDark
              ? [
                  const Color(0xFF141F32),
                  const Color(0xFF0F172A),
                  const Color(0xFF0A0F1D),
                ]
              : [
                  colorScheme.primaryContainer.withAlpha(140),
                  colorScheme.surfaceContainerHighest,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(60),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 60 : 15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accent, width: 1),
                      ),
                      child: Text(
                        '${level?.code ?? 'B1'} • ${article.readingTimeMinutes > 0 ? '${article.readingTimeMinutes} dk' : '3 dk'}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    if (article.hasPodcastAudio)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24).withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFBBF24).withAlpha(140),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.mic_rounded,
                              size: 14,
                              color: Color(0xFFFBBF24),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Podcast AI',
                              style: TextStyle(
                                color: Color(0xFFFBBF24),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  article.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  article.description.isNotEmpty
                      ? article.description
                      : article.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onReadNow,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    s.t('Hemen Oku', 'Read Now'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (article.imageUrl != null && article.imageUrl!.isNotEmpty) ...[
            const SizedBox(width: 24),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  article.imageUrl!,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ==========================================
// DESKTOP ARTICLE CARD
// ==========================================
class _DesktopArticleCard extends StatelessWidget {
  const _DesktopArticleCard({
    required this.article,
    this.level,
    required this.onTap,
  });

  final Article article;
  final ArticleLevel? level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = level?.accentColor ?? colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        hoverColor: accent.withAlpha(20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141922) : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(50),
            ),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Meta Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      level?.code ?? 'B1',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    article.readingTimeMinutes > 0
                        ? '${article.readingTimeMinutes} dk'
                        : '3 dk',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (article.hasPodcastAudio)
                    const Icon(
                      Icons.mic_rounded,
                      size: 16,
                      color: Color(0xFFFBBF24),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Body row with compact side thumbnail
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              article.description.isNotEmpty
                                  ? article.description
                                  : article.summary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (article.imageUrl != null && article.imageUrl!.isNotEmpty) ...[
                      const SizedBox(width: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          article.imageUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// FILTER CHIP
// ==========================================
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color? accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bg = isSelected
        ? (accentColor ?? colorScheme.primary)
        : (isDark ? const Color(0xFF161B22) : colorScheme.surfaceContainerHighest);
    final fg = isSelected ? Colors.white : colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? (accentColor ?? colorScheme.primary)
                  : colorScheme.outlineVariant.withAlpha(40),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MOBILE SUB-COMPONENTS
// ==========================================
class _GuestSignInBanner extends StatelessWidget {
  const _GuestSignInBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      key: const ValueKey<String>('main_menu_guest_signin_banner'),
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.primary.withAlpha(90)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.rocket_launch_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.t(
                        'Ücretsiz giriş yap, limitini 2 katına çıkar',
                        'Sign in free to double your daily limit',
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.t(
                        'Hemen giriş yap veya kaydol — günlük 80 kelime çeviri hakkı kazan.',
                        'Sign in or sign up now — unlock 80 daily translations.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({
    required this.article,
    required this.progress,
    required this.onTap,
    required this.onDismiss,
  });

  final Article article;
  final ArticleReadingProgress progress;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final parsedLevel = article.parsedLevel;
    final accent = parsedLevel?.accentColor ?? colorScheme.primary;
    final percent = progress.progressPercent;

    return Material(
      key: const ValueKey<String>('main_menu_continue_reading_card'),
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(150),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(28),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      size: 16,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.continueReadingTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (parsedLevel != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        parsedLevel.code,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      key: const ValueKey<String>(
                        'main_menu_continue_reading_dismiss_btn',
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      tooltip: s.t('Kapat', 'Dismiss'),
                      onPressed: onDismiss,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                article.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.clampedProgress,
                  minHeight: 7,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      s.readingProgressCompletedLabel(percent),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    s.readingProgressPercent(percent),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: accent,
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
