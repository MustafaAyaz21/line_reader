import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/api_key_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/tts/tts_service.dart';
import '../../articles/articles_screen.dart';
import '../../articles/controllers/article_reading_progress_controller.dart';
import '../../articles/controllers/articles_controller.dart';
import '../../articles/models/article.dart';
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

/// Uygulamanın sade Ana Menü ekranı.
/// Ortada yan yana "Tarayıcı" ve "Makaleler" kısayol kartları, sağ üstte ise
/// güncelleme ikonu (kırmızı göstergeli) ve Ayarlar ikonu yer alır.
class MainMenuScreen extends StatelessWidget {
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

  void _openArticles(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ArticlesScreen(
          controller: articlesController,
          translationService: translationService,
          ttsService: ttsService,
          authController: authController,
          onAddWord: onAddWord,
          onAddWordWithLexicon: onAddWordWithLexicon,
          loadWordLists: loadWordLists,
          onCreateWordList: onCreateWordList,
        ),
      ),
    );
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
          translationService: translationService,
          ttsService: ttsService,
          authController: authController,
          onAddWord: onAddWord,
          onAddWordWithLexicon: onAddWordWithLexicon,
          loadWordLists: loadWordLists,
          onCreateWordList: onCreateWordList,
        ),
      ),
    );
  }

  Article? _findVisibleArticleById(String articleId) {
    final controller = articlesController;
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
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visuals = AppThemeVisuals.of(context);
    final progressController =
        readingProgressController ?? ArticleReadingProgressController.shared;
    final listenables = <Listenable>[
      progressController,
      if (articlesController != null) articlesController!,
    ];

    return Scaffold(
      backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(s.mainMenuTitle),
        actions: [
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
          if (updateController != null)
            UpdateActionButton(controller: updateController!),
          if (localeController != null && authController != null)
            SettingsActionButton(
              apiKeyController: apiKeyController,
              localeController: localeController!,
              authController: authController!,
              onClearCache: onClearCache,
            )
          else
            ApiKeyActionButton(
              controller: apiKeyController,
              onClearCache: onClearCache,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (authController != null)
                  ListenableBuilder(
                    listenable: authController!,
                    builder: (context, _) {
                      if (authController!.isAuthenticated ||
                          authController!.isLoading) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _GuestSignInBanner(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<bool>(
                                builder: (_) => AuthScreen(
                                  controller: authController!,
                                  canPop: true,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _MenuShortcutCard(
                          icon: Icons.public_rounded,
                          title: s.browserTitle,
                          subtitle: s.browserSubtitle,
                          containerColor: colorScheme.primaryContainer,
                          iconBackgroundColor: colorScheme.primary,
                          iconColor: colorScheme.onPrimary,
                          textColor: colorScheme.onPrimaryContainer,
                          onTap: onOpenBrowser,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _MenuShortcutCard(
                          icon: Icons.menu_book_rounded,
                          title: s.articlesTitle,
                          subtitle: s.articlesSubtitle,
                          containerColor: colorScheme.secondaryContainer,
                          iconBackgroundColor: colorScheme.secondary,
                          iconColor: colorScheme.onSecondary,
                          textColor: colorScheme.onSecondaryContainer,
                          onTap: () => _openArticles(context),
                        ),
                      ),
                    ],
                  ),
                ),
                ListenableBuilder(
                  listenable: Listenable.merge(listenables),
                  builder: (context, _) {
                    final lastProgress = progressController.lastProgress;
                    if (lastProgress == null ||
                        lastProgress.isCompleted ||
                        progressController.isContinueReadingDismissed(
                          lastProgress.articleId,
                        )) {
                      return const SizedBox.shrink();
                    }
                    final article = _findVisibleArticleById(
                      lastProgress.articleId,
                    );
                    if (article == null) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

class _MenuShortcutCard extends StatelessWidget {
  const _MenuShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.containerColor,
    required this.iconBackgroundColor,
    required this.iconColor,
    required this.textColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color containerColor;
  final Color iconBackgroundColor;
  final Color iconColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: containerColor,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor.withAlpha(210),
                    height: 1.3,
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
