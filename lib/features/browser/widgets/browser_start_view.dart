import 'package:flutter/material.dart';

import '../models/favorite_site.dart';

/// Tarayıcı ilk açıldığında gösterilen modern Line Reader başlangıç ekranı:
/// - Üstte kullanıcının favori siteleri.
/// - Ortada zarif beyaz zeminli cursive LR logosu, arama/URL çubuğu ve hızlı okuma kaynakları.
class BrowserStartView extends StatefulWidget {
  const BrowserStartView({
    super.key,
    required this.favoriteSites,
    required this.onSearch,
    required this.onSelectFavorite,
    required this.onManageFavorites,
  });

  final List<FavoriteSite> favoriteSites;
  final ValueChanged<String> onSearch;
  final ValueChanged<FavoriteSite> onSelectFavorite;
  final VoidCallback onManageFavorites;

  @override
  State<BrowserStartView> createState() => _BrowserStartViewState();
}

class _BrowserStartViewState extends State<BrowserStartView> {
  final TextEditingController _searchController = TextEditingController();

  static const List<({String title, String url, IconData icon})> _popularSites = [
    (title: 'BBC News', url: 'https://www.bbc.com/news', icon: Icons.newspaper_rounded),
    (title: 'Wikipedia', url: 'https://en.wikipedia.org', icon: Icons.menu_book_rounded),
    (title: 'The Guardian', url: 'https://www.theguardian.com', icon: Icons.public_rounded),
    (title: 'Medium', url: 'https://medium.com', icon: Icons.article_rounded),
    (title: 'TechCrunch', url: 'https://techcrunch.com', icon: Icons.biotech_rounded),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    widget.onSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 40).clamp(0.0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1) Üst bölüm: Favori Siteler
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: _buildFavoritesSection(theme, colorScheme),
                  ),
                ),

                // 2) Orta bölüm: Modern Arama ve Keşif Alanı
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Cursive LR Logo Badge (White background, black cursive letters)
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.black.withAlpha(25),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 50 : 15),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            'assets/app_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 18),

                        Text(
                          'Line Reader',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'İngilizce web sayfalarında okuyun, kelimelere dokunarak anında çevirin.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Arama / URL Çubuğu
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF141922)
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withAlpha(60),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 40 : 10),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 22,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.search,
                                  autocorrect: false,
                                  onSubmitted: (_) => _submit(),
                                  style: theme.textTheme.bodyLarge,
                                  decoration: InputDecoration(
                                    hintText: 'Konu, makale veya web adresi (URL) yazın...',
                                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant.withAlpha(160),
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                ),
                              const SizedBox(width: 4),
                              FilledButton(
                                onPressed: _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Ara',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Popüler Okuma Kaynakları Çipleri
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _popularSites.map((site) {
                            return ActionChip(
                              avatar: Icon(
                                site.icon,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              label: Text(site.title),
                              labelStyle: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              backgroundColor: isDark
                                  ? const Color(0xFF161B22)
                                  : colorScheme.surfaceContainerLow,
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withAlpha(50),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              onPressed: () => widget.onSearch(site.url),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavoritesSection(ThemeData theme, ColorScheme colorScheme) {
    final sites = widget.favoriteSites;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.star_rounded,
              size: 18,
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(width: 6),
            Text(
              'Favori Siteler',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (sites.isNotEmpty)
              TextButton(
                onPressed: widget.onManageFavorites,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Yönet'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (sites.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141922) : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant.withAlpha(40)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Henüz favori site eklenmedi. Gezindiğiniz siteleri üstteki yıldız ikonuyla buraya ekleyebilirsiniz.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sites.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final site = sites[index];
                return Material(
                  color: isDark ? const Color(0xFF161B22) : colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => widget.onSelectFavorite(site),
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withAlpha(50),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.public_rounded,
                                size: 15,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  site.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            site.displayHost,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
