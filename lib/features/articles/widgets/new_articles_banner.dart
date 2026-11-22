import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../models/article_level.dart';

/// Uzak kaynaktan yeni makale indirildiğinde ekranın en üstünde beliren
/// ve sağındaki "Yenile" butonuyla yeni makaleleri tek dokunuşla listeye
/// düşüren şık bildirim şeridi.
class NewArticlesBanner extends StatelessWidget {
  const NewArticlesBanner({
    super.key,
    required this.totalNewCount,
    required this.onRefreshPressed,
    this.level,
    this.levelNewCount = 0,
  });

  final int totalNewCount;
  final VoidCallback onRefreshPressed;
  final ArticleLevel? level;
  final int levelNewCount;

  @override
  Widget build(BuildContext context) {
    final visible = totalNewCount > 0;
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String message;
    if (level != null && levelNewCount > 0) {
      message = s.newLevelArticlesAvailableLabel(levelNewCount, level!.code);
    } else {
      message = s.newArticlesAvailableLabel(totalNewCount);
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Material(
                key: const ValueKey<String>('new_articles_banner'),
                color: colorScheme.primaryContainer,
                elevation: 1,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.primary.withAlpha(70),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.auto_stories_rounded,
                        size: 19,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey<String>(
                          'new_articles_refresh_button',
                        ),
                        onPressed: onRefreshPressed,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          s.refreshAction,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
