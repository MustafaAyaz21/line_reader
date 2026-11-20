import 'package:flutter/material.dart';

import '../models/favorite_site.dart';

/// Tarayıcı ilk açıldığında hiçbir harici site veya Google sayfası yüklemeden
/// gösterilen Line Reader başlangıç ekranı:
/// - Üstte kullanıcının favori siteleri yan yana sıralı durur.
/// - Ortada kalın "Line Reader" başlığı, altında ekranın sağından çıkıp
///   solundan devam eden hareketli kesik çizgiler ve sade arama kutusu yer alır.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 36).clamp(0.0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1) Üst bölüm: Yan yana sıralı Favori Siteler
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFavoritesSection(theme, colorScheme),
                ),
                // 2) Orta bölüm: Kalın "Line Reader", ekran boyu akan kesik çizgiler ve arama kutusu
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Line Reader',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Ekranın sağının sonuna kadar gidip solundan çıkan kesik çizgiler
                      _WrappingDashedLines(
                        primaryColor: colorScheme.primary,
                        secondaryColor: colorScheme.primary.withAlpha(115),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Okumak istediğiniz konuyu arayın veya yukarıya site adresi yazın.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant,
                                    ),
                                  ),
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 4, 6, 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.search_rounded,
                                        size: 22,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: _searchController,
                                          keyboardType: TextInputType.text,
                                          textInputAction:
                                              TextInputAction.search,
                                          autocorrect: true,
                                          enableSuggestions: true,
                                          onSubmitted: (_) => _submit(),
                                          style: theme.textTheme.bodyLarge,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'Konu, makale veya kelime ara...',
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      FilledButton(
                                        onPressed: _submit,
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 11,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(13),
                                          ),
                                        ),
                                        child: const Text('Ara'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Dikey denge için alt boşluk
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavoritesSection(ThemeData theme, ColorScheme colorScheme) {
    final sites = widget.favoriteSites;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.star_rounded,
              size: 17,
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(width: 6),
            Text(
              'Favori Siteler',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Text(
              'Henüz favori site yok. Bir site açtığınızda yıldız ikonuyla buraya ekleyebilirsiniz.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sites.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final site = sites[index];
                return Material(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => widget.onSelectFavorite(site),
                    child: Container(
                      width: 132,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colorScheme.outlineVariant),
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
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            site.displayHost,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
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

/// "Line Reader" başlığının altında ekranın sağ kenarına kadar kayıp sol
/// kenarından kesintisiz devam eden hareketli kesik çizgiler.
class _WrappingDashedLines extends StatefulWidget {
  const _WrappingDashedLines({
    required this.primaryColor,
    required this.secondaryColor,
  });

  final Color primaryColor;
  final Color secondaryColor;

  @override
  State<_WrappingDashedLines> createState() => _WrappingDashedLinesState();
}

class _WrappingDashedLinesState extends State<_WrappingDashedLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: 14,
        child: CustomPaint(
          painter: _WrappingDashedLinesPainter(
            animation: _controller,
            primaryColor: widget.primaryColor,
            secondaryColor: widget.secondaryColor,
          ),
        ),
      ),
    );
  }
}

class _WrappingDashedLinesPainter extends CustomPainter {
  _WrappingDashedLinesPainter({
    required this.animation,
    required this.primaryColor,
    required this.secondaryColor,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color primaryColor;
  final Color secondaryColor;

  static const List<(double dash, double gap)> _topPattern = <(double, double)>[
    (26, 12),
    (12, 10),
    (36, 14),
    (16, 12),
  ];

  static const List<(double dash, double gap)> _bottomPattern =
      <(double, double)>[
    (14, 14),
    (30, 12),
    (10, 10),
    (22, 16),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final primaryPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final secondaryPaint = Paint()
      ..color = secondaryColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    _paintRow(
      canvas: canvas,
      width: size.width,
      y: size.height * 0.30,
      pattern: _topPattern,
      progress: animation.value,
      paint: primaryPaint,
    );

    _paintRow(
      canvas: canvas,
      width: size.width,
      y: size.height * 0.78,
      pattern: _bottomPattern,
      progress: (animation.value + 0.38) % 1.0,
      paint: secondaryPaint,
    );

    canvas.restore();
  }

  void _paintRow({
    required Canvas canvas,
    required double width,
    required double y,
    required List<(double dash, double gap)> pattern,
    required double progress,
    required Paint paint,
  }) {
    double patternLength = 0;
    for (final (dash, gap) in pattern) {
      patternLength += dash + gap;
    }
    if (patternLength <= 0) return;

    // Soldan sağa sürekli akar; sağ kenarı aşan parça sol kenardan yeniden girer.
    final double offset = progress * patternLength;
    double cursor = -patternLength + offset;

    while (cursor < width + patternLength) {
      for (final (dash, gap) in pattern) {
        final startX = cursor;
        final endX = cursor + dash;
        if (endX >= 0 && startX <= width) {
          canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
        }
        cursor += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WrappingDashedLinesPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
