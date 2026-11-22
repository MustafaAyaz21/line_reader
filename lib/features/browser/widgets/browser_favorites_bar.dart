import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/favorite_site.dart';

/// Tarayıcı üst çubuğunun hemen altında kayıtlı favori sitelere tek tıkla
/// erişim sağlayan ince, yatay kaydırılabilir hızlı erişim şeridi.
class BrowserFavoritesBar extends StatelessWidget {
  const BrowserFavoritesBar({
    super.key,
    required this.sites,
    required this.onSelectSite,
    required this.onOpenAll,
  });

  final List<FavoriteSite> sites;
  final ValueChanged<FavoriteSite> onSelectSite;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    if (sites.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visuals = AppThemeVisuals.of(context);

    return Container(
      height: 40,
      color: visuals.appBarColor,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        itemCount: sites.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == sites.length) {
            return ActionChip(
              onPressed: onOpenAll,
              label: Text(
                'Yönet',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: colorScheme.surfaceContainerLow,
              side: BorderSide(color: colorScheme.outlineVariant),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            );
          }

          final site = sites[index];
          return ActionChip(
            onPressed: () => onSelectSite(site),
            avatar: const Icon(
              Icons.star_rounded,
              size: 14,
              color: Color(0xFFF59E0B),
            ),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                site.displayTitle,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            backgroundColor: colorScheme.surfaceContainerLow,
            side: BorderSide(color: colorScheme.outlineVariant),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }
}
