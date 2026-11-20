import 'package:flutter/material.dart';

import '../controllers/favorite_sites_controller.dart';
import '../models/favorite_site.dart';

/// Kayıtlı favori web sitelerini listeleyen, tek dokunuşla açma ve silme
/// imkânı sunan alt panel.
class FavoriteSitesSheet extends StatelessWidget {
  const FavoriteSitesSheet({
    super.key,
    required this.controller,
    required this.currentUrl,
    required this.onSelectSite,
    required this.onToggleCurrentSite,
  });

  final FavoriteSitesController controller;
  final String currentUrl;
  final ValueChanged<FavoriteSite> onSelectSite;
  final VoidCallback onToggleCurrentSite;

  static Future<void> show(
    BuildContext context, {
    required FavoriteSitesController controller,
    required String currentUrl,
    required ValueChanged<FavoriteSite> onSelectSite,
    required VoidCallback onToggleCurrentSite,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return FavoriteSitesSheet(
          controller: controller,
          currentUrl: currentUrl,
          onSelectSite: (site) {
            Navigator.of(sheetContext).pop();
            onSelectSite(site);
          },
          onToggleCurrentSite: onToggleCurrentSite,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.65;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final sites = controller.sites;
          final isCurrentSaved = controller.isFavorite(currentUrl);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 22,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Favori Siteler',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onToggleCurrentSite,
                      icon: Icon(
                        isCurrentSaved
                            ? Icons.star_rounded
                            : Icons.add_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isCurrentSaved ? 'Kayıtlı' : 'Bu Siteyi Ekle',
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              if (sites.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 36,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmarks_outlined,
                        size: 36,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Henüz favori site eklenmedi',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Üst çubuktaki yıldız ikonuna dokunarak sık okuduğunuz siteleri tek tıkla erişmek üzere kaydedebilirsiniz.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: sites.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final site = sites[index];
                      return ListTile(
                        onTap: () => onSelectSite(site),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.public_rounded,
                            size: 18,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          site.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          site.displayHost,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: IconButton(
                          onPressed: () => controller.removeSite(site),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          tooltip: 'Favorilerden Çıkar',
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}
