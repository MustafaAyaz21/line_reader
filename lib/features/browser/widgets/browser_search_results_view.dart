import 'package:flutter/material.dart';

import '../models/web_search_result.dart';

/// Arka plan aramasından dönen sonuçları Google tarzında sade, kart çerçevesiz
/// ve gereksiz detaylardan arındırılmış şekilde (site ismi, URL, başlık ve
/// açıklama) listeleyen görünüm.
class BrowserSearchResultsView extends StatelessWidget {
  const BrowserSearchResultsView({
    super.key,
    required this.query,
    required this.isLoading,
    required this.results,
    required this.errorMessage,
    required this.onSelectResult,
    required this.onRetry,
    required this.onBackToStart,
  });

  final String query;
  final bool isLoading;
  final List<WebSearchResult> results;
  final String? errorMessage;
  final ValueChanged<WebSearchResult> onSelectResult;
  final VoidCallback onRetry;
  final VoidCallback onBackToStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sade arama üst bilgi şeridi
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          color: colorScheme.surface,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '"$query"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onBackToStart,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Başlangıç'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        Expanded(
          child: _buildBody(theme, colorScheme),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              'Sonuçlar aranıyor...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null && results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 36,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 36,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                '"$query" için sonuç bulunamadı.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Farklı kelimelerle tekrar arayabilir veya üst çubuğa doğrudan web adresi yazabilirsiniz.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    final linkTitleColor =
        isDark ? const Color(0xFF8AB4F8) : const Color(0xFF1A0DAB);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: results.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: colorScheme.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final item = results[index];
        return InkWell(
          onTap: () => onSelectResult(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Site ismi
                Text(
                  item.displaySource,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 1),
                // URL
                Text(
                  item.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 5),
                // Başlık
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: linkTitleColor,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                if (item.snippet.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  // Kısa açıklama
                  Text(
                    item.snippet,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
