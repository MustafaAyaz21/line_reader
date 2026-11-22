import 'package:flutter/material.dart';

import '../../../core/settings/api_key_controller.dart';
import '../../articles/articles_screen.dart';
import '../../articles/controllers/articles_controller.dart';
import '../../settings/widgets/api_key_dialog.dart';
import '../../update/controllers/app_update_controller.dart';
import '../../update/widgets/update_action_button.dart';

/// Uygulamanın sade Ana Menü ekranı.
/// Ortada yan yana "Tarayıcı" ve "Makaleler" kısayol kartları, sağ üstte ise
/// güncelleme ikonu (kırmızı göstergeli) ve Gemini API anahtarı ikonu yer alır.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({
    super.key,
    required this.onOpenBrowser,
    required this.apiKeyController,
    this.updateController,
    this.articlesController,
    this.onClearCache,
  });

  final VoidCallback onOpenBrowser;
  final ApiKeyController apiKeyController;
  final AppUpdateController? updateController;
  final ArticlesController? articlesController;
  final Future<void> Function()? onClearCache;

  void _openArticles(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ArticlesScreen(controller: articlesController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ana Menü'),
        actions: [
          if (updateController != null)
            UpdateActionButton(controller: updateController!),
          ApiKeyActionButton(
            controller: apiKeyController,
            onClearCache: onClearCache,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _MenuShortcutCard(
                      icon: Icons.public_rounded,
                      title: 'Tarayıcı',
                      subtitle: 'Web\'de oku ve anında çevir',
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
                      title: 'Makaleler',
                      subtitle: 'Çevrimdışı okumalar',
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
          ),
        ),
      ),
    );
  }
}
