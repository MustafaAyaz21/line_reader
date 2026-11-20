import 'package:flutter/material.dart';

/// Line Apps tasarım diline uygun, Chrome'dan farklı sade ve modern tarayıcı
/// üst çubuğu. Kalem modu anahtarı ve Favori site aksiyonlarını içerir.
class BrowserAddressBar extends StatelessWidget {
  const BrowserAddressBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.canGoBack,
    required this.canGoForward,
    required this.isPenMode,
    required this.isCurrentSiteFavorite,
    required this.onSubmitted,
    required this.onBack,
    required this.onForward,
    required this.onReloadOrStop,
    required this.onTogglePenMode,
    required this.onToggleFavoriteSite,
    required this.onOpenFavoriteSites,
    this.onReturnToMenu,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final bool canGoBack;
  final bool canGoForward;
  final bool isPenMode;
  final bool isCurrentSiteFavorite;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReloadOrStop;
  final VoidCallback onTogglePenMode;
  final VoidCallback onToggleFavoriteSite;
  final VoidCallback onOpenFavoriteSites;
  final VoidCallback? onReturnToMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Üst aksiyon satırı: Ana Menü, gezinme, Kalem modu ve Favori site araçları
          Row(
            children: [
              if (onReturnToMenu != null)
                IconButton(
                  onPressed: onReturnToMenu,
                  icon: const Icon(Icons.home_rounded, size: 20),
                  tooltip: 'Ana Menü',
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                onPressed: canGoBack ? onBack : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                tooltip: 'Geri',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: canGoForward ? onForward : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                tooltip: 'İleri',
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              // Kalem İkonu: Aktif (hızlı kelime çevirisi) / Devre Dışı (Kopyala & Tümünü Seç)
              Material(
                color: isPenMode
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTogglePenMode,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPenMode
                              ? Icons.edit_rounded
                              : Icons.edit_off_outlined,
                          size: 16,
                          color: isPenMode
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPenMode ? 'Kelime' : 'Seçim',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isPenMode
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onToggleFavoriteSite,
                icon: Icon(
                  isCurrentSiteFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 21,
                  color: isCurrentSiteFavorite
                      ? const Color(0xFFF59E0B)
                      : colorScheme.onSurfaceVariant,
                ),
                tooltip: isCurrentSiteFavorite
                    ? 'Favori Siteden Çıkar'
                    : 'Siteyi Favorilere Ekle',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onOpenFavoriteSites,
                icon: Icon(
                  Icons.collections_bookmark_outlined,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Favori Siteler',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Sade Line Apps adres / arama giriş alanı
          ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[controller, focusNode]),
            builder: (context, _) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: onSubmitted,
                onTap: () {
                  controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  );
                },
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Web adresi girin veya arama yapın',
                  prefixIcon: Icon(
                    Icons.public_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.text.isNotEmpty && focusNode.hasFocus)
                        IconButton(
                          onPressed: () {
                            controller.clear();
                            focusNode.requestFocus();
                          },
                          icon: const Icon(Icons.close_rounded, size: 17),
                          tooltip: 'Temizle',
                          visualDensity: VisualDensity.compact,
                        ),
                      IconButton(
                        onPressed: onReloadOrStop,
                        icon: Icon(
                          isLoading
                              ? Icons.close_rounded
                              : Icons.refresh_rounded,
                          size: 18,
                        ),
                        tooltip: isLoading ? 'Durdur' : 'Yenile',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
