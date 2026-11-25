import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// Line Reader için özel olarak tasarlanmış, aşağı çekildiğinde modern **LR**
/// monogramını çizip etrafında ince bir ışık halkası döndüren yenileme göstergesi.
class LineRefreshIndicator extends StatefulWidget {
  const LineRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 56.0,
    this.strokeColor,
    this.backgroundColor,
  });

  final Widget child;
  final RefreshCallback onRefresh;
  final double displacement;
  final Color? strokeColor;
  final Color? backgroundColor;

  @override
  State<LineRefreshIndicator> createState() => _LineRefreshIndicatorState();
}

class _LineRefreshIndicatorState extends State<LineRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  bool _isRefreshing = false;
  double _dragOffset = 0.0;
  static const double _triggerThreshold = 75.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isRefreshing) return false;

    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.extentBefore == 0 &&
          notification.scrollDelta != null &&
          notification.scrollDelta! < 0) {
        setState(() {
          _dragOffset = (_dragOffset - notification.scrollDelta! * 0.5)
              .clamp(0.0, _triggerThreshold * 1.5);
        });
      } else if (notification.scrollDelta != null &&
          notification.scrollDelta! > 0 &&
          _dragOffset > 0) {
        setState(() {
          _dragOffset = (_dragOffset - notification.scrollDelta!)
              .clamp(0.0, _triggerThreshold * 1.5);
        });
      }
    } else if (notification is OverscrollNotification) {
      if (notification.overscroll < 0) {
        setState(() {
          _dragOffset = (_dragOffset - notification.overscroll * 0.5)
              .clamp(0.0, _triggerThreshold * 1.5);
        });
      }
    } else if (notification is ScrollEndNotification) {
      if (_dragOffset >= _triggerThreshold) {
        _startRefresh();
      } else {
        setState(() {
          _dragOffset = 0.0;
        });
      }
    }
    return false;
  }

  Future<void> _startRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _dragOffset = _triggerThreshold;
    });
    _animController.repeat();

    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        _animController.stop();
        _animController.reset();
        setState(() {
          _isRefreshing = false;
          _dragOffset = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final double pullProgress =
        (_dragOffset / _triggerThreshold).clamp(0.0, 1.0);
    final bool isVisible = _dragOffset > 0 || _isRefreshing;

    final Color badgeBg =
        widget.backgroundColor ?? colorScheme.surfaceContainerHigh;
    final Color lColor = widget.strokeColor ?? colorScheme.onSurface;
    final Color rColor = colorScheme.primary;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Stack(
        children: [
          widget.child,
          if (isVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: AnimatedScale(
                    scale: _isRefreshing
                        ? 1.0
                        : (0.72 + 0.28 * pullProgress).clamp(0.72, 1.0),
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: 56,
                      height: 56,
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withAlpha(90),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 90 : 28),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: AnimatedBuilder(
                        animation: _animController,
                        builder: (context, _) {
                          return CustomPaint(
                            size: const Size(56, 56),
                            painter: LrStrokeRingPainter(
                              progress: _isRefreshing
                                  ? _animController.value
                                  : pullProgress,
                              lColor: lColor,
                              accentColor: rColor,
                              isLooping: _isRefreshing,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Konsept 1: Çizilen LR & Dönen Işık Halkası CustomPainter'ı.
class LrStrokeRingPainter extends CustomPainter {
  const LrStrokeRingPainter({
    required this.progress,
    required this.lColor,
    required this.accentColor,
    required this.isLooping,
  });

  final double progress;
  final Color lColor;
  final Color accentColor;
  final bool isLooping;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset center = Offset(w / 2, h / 2);
    final double radius = math.min(w, h) * 0.40;

    // 1. İnce dönen / dolan aksan halkası
    final Rect arcRect = Rect.fromCircle(center: center, radius: radius);
    final Paint trackPaint = Paint()
      ..color = accentColor.withAlpha(28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, radius, trackPaint);

    final Paint ringPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    if (isLooping) {
      final double startAngle = -math.pi / 2 + (progress * 2 * math.pi);
      canvas.drawArc(arcRect, startAngle, math.pi * 0.65, false, ringPaint);
    } else if (progress > 0.02) {
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        progress.clamp(0.0, 1.0) * 2 * math.pi,
        false,
        ringPaint,
      );
    }

    // 2. Modern L harfi yolu (sol)
    final Path lPath = Path()
      ..moveTo(w * 0.30, h * 0.31)
      ..lineTo(w * 0.30, h * 0.69)
      ..lineTo(w * 0.47, h * 0.69);

    // 3. Modern R harfi yolu (sağ)
    final Path rPath = Path()
      ..moveTo(w * 0.53, h * 0.69)
      ..lineTo(w * 0.53, h * 0.31)
      ..lineTo(w * 0.64, h * 0.31)
      ..cubicTo(
        w * 0.72,
        h * 0.31,
        w * 0.74,
        h * 0.36,
        w * 0.74,
        h * 0.42,
      )
      ..cubicTo(
        w * 0.74,
        h * 0.48,
        w * 0.71,
        h * 0.52,
        w * 0.64,
        h * 0.52,
      )
      ..lineTo(w * 0.53, h * 0.52);

    final Path rLegPath = Path()
      ..moveTo(w * 0.62, h * 0.52)
      ..lineTo(w * 0.74, h * 0.69);

    final double lDrawT;
    final double rDrawT;
    if (isLooping) {
      // Sürekli yenileme sırasında L ve R zarifçe çizilip sabitlenir
      if (progress < 0.45) {
        lDrawT = Curves.easeOutCubic.transform(progress / 0.45);
        rDrawT = Curves.easeOutCubic
            .transform(((progress - 0.12) / 0.38).clamp(0.0, 1.0));
      } else if (progress < 0.85) {
        lDrawT = 1.0;
        rDrawT = 1.0;
      } else {
        final fade = 1.0 - ((progress - 0.85) / 0.15).clamp(0.0, 1.0);
        lDrawT = 0.25 + 0.75 * fade;
        rDrawT = 0.25 + 0.75 * fade;
      }
    } else {
      lDrawT = (progress * 1.45).clamp(0.0, 1.0);
      rDrawT = ((progress - 0.22) / 0.78).clamp(0.0, 1.0);
    }

    final Paint lPaint = Paint()
      ..color = lColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint rPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    _drawTrimmedPath(canvas, lPath, lDrawT, lPaint);
    _drawTrimmedPath(canvas, rPath, (rDrawT * 1.25).clamp(0.0, 1.0), rPaint);
    if (rDrawT > 0.62) {
      final double legT = ((rDrawT - 0.62) / 0.38).clamp(0.0, 1.0);
      _drawTrimmedPath(canvas, rLegPath, legT, rPaint);
    }
  }

  void _drawTrimmedPath(Canvas canvas, Path path, double t, Paint paint) {
    if (t <= 0.0) return;
    for (final PathMetric metric in path.computeMetrics()) {
      final double len = metric.length * t.clamp(0.0, 1.0);
      if (len > 0) {
        canvas.drawPath(metric.extractPath(0, len), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LrStrokeRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isLooping != isLooping ||
        oldDelegate.lColor != lColor ||
        oldDelegate.accentColor != accentColor;
  }
}
