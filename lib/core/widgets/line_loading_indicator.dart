import 'package:flutter/material.dart';

import 'line_refresh_indicator.dart';

/// Line Reader için özel, modern **LR** monogramını ve dönen ışık halkasını
/// gösteren yükleme göstergesi.
class LineLoadingIndicator extends StatefulWidget {
  const LineLoadingIndicator({
    super.key,
    this.size = const Size(56, 56),
    this.strokeColor,
    this.message,
    this.textStyle,
  });

  final Size size;
  final Color? strokeColor;
  final String? message;
  final TextStyle? textStyle;

  @override
  State<LineLoadingIndicator> createState() => _LineLoadingIndicatorState();
}

class _LineLoadingIndicatorState extends State<LineLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final double dim = widget.size.shortestSide.clamp(44.0, 68.0);
    final Color accent = widget.strokeColor ?? colorScheme.primary;

    final content = Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(dim * 0.28),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(80),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 70 : 20),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size(dim, dim),
            painter: LrStrokeRingPainter(
              progress: _controller.value,
              lColor: colorScheme.onSurface,
              accentColor: accent,
              isLooping: true,
            ),
          );
        },
      ),
    );

    if (widget.message == null || widget.message!.isEmpty) {
      return Center(child: content);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 14),
          Text(
            widget.message!,
            style: widget.textStyle ??
                theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                ),
          ),
        ],
      ),
    );
  }
}
