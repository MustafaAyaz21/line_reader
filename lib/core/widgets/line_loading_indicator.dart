import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// Line Reader için özel, zarif vektörel "Line" imza çizimini sürekli akıtan
/// lüks yükleme göstergesi. Klasik dönen yuvarlak spinner yerine kullanılır.
class LineLoadingIndicator extends StatefulWidget {
  const LineLoadingIndicator({
    super.key,
    this.size = const Size(110, 42),
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
      duration: const Duration(milliseconds: 1400),
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
    final stroke = widget.strokeColor ?? colorScheme.primary;

    final content = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: widget.size,
          painter: _LineSignaturePainter(
            progress: _controller.value,
            strokeColor: stroke,
          ),
        );
      },
    );

    if (widget.message == null || widget.message!.isEmpty) {
      return Center(child: content);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 12),
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

class _LineSignaturePainter extends CustomPainter {
  _LineSignaturePainter({
    required this.progress,
    required this.strokeColor,
  });

  final double progress;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Path linePath = Path();
    linePath.moveTo(w * 0.08, h * 0.44);
    linePath.cubicTo(w * 0.16, h * 0.44, w * 0.20, h * 0.42, w * 0.24, h * 0.18);
    linePath.cubicTo(w * 0.25, h * 0.08, w * 0.22, h * 0.08, w * 0.21, h * 0.18);
    linePath.cubicTo(w * 0.19, h * 0.38, w * 0.21, h * 0.58, w * 0.25, h * 0.58);
    linePath.cubicTo(w * 0.30, h * 0.58, w * 0.34, h * 0.52, w * 0.36, h * 0.42);
    linePath.cubicTo(w * 0.38, h * 0.32, w * 0.39, h * 0.32, w * 0.40, h * 0.44);
    linePath.cubicTo(w * 0.41, h * 0.56, w * 0.44, h * 0.58, w * 0.47, h * 0.48);
    linePath.cubicTo(w * 0.49, h * 0.34, w * 0.51, h * 0.32, w * 0.53, h * 0.44);
    linePath.cubicTo(w * 0.54, h * 0.56, w * 0.56, h * 0.58, w * 0.59, h * 0.44);
    linePath.cubicTo(w * 0.61, h * 0.32, w * 0.63, h * 0.34, w * 0.65, h * 0.48);
    linePath.cubicTo(w * 0.66, h * 0.58, w * 0.69, h * 0.58, w * 0.72, h * 0.46);
    linePath.cubicTo(w * 0.74, h * 0.34, w * 0.78, h * 0.34, w * 0.78, h * 0.44);
    linePath.cubicTo(w * 0.78, h * 0.50, w * 0.74, h * 0.58, w * 0.69, h * 0.58);
    linePath.cubicTo(w * 0.74, h * 0.58, w * 0.82, h * 0.56, w * 0.92, h * 0.56);

    final Paint linePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint glowPaint = Paint()
      ..color = strokeColor.withAlpha(45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Çizim akışı (0.0 - 0.70 arası çizim tamamlanır, 0.70 - 1.00 arası parlayıp başa döner)
    final double drawT = progress < 0.72
        ? Curves.easeInOutCubic.transform(progress / 0.72)
        : 1.0;

    for (final PathMetric metric in linePath.computeMetrics()) {
      final double currentLen = metric.length * drawT;
      if (currentLen > 0.0) {
        final Path extracted = metric.extractPath(0, currentLen);
        canvas.drawPath(extracted, glowPaint);
        canvas.drawPath(extracted, linePaint);
      }
    }

    // "i" harfinin noktası
    if (drawT > 0.45) {
      final double dotT = ((drawT - 0.45) / 0.15).clamp(0.0, 1.0);
      final Offset dotPos = Offset(w * 0.41, h * 0.24);
      final Paint dotPaint = Paint()..color = strokeColor;
      canvas.drawCircle(dotPos, 2.0 * dotT, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineSignaturePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeColor != strokeColor;
  }
}
