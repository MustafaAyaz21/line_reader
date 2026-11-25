import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Line Reader için özel olarak tasarlanmış, aşağı çekildiğinde keskin siyah bir
/// hat ile "Line" kelimesini çizip akıtan, lüks ve minimalist yenileme göstergesi.
class LineRefreshIndicator extends StatefulWidget {
  const LineRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 56.0,
    this.strokeColor = const Color(0xFF111827),
    this.backgroundColor = Colors.white,
  });

  final Widget child;
  final RefreshCallback onRefresh;
  final double displacement;
  final Color strokeColor;
  final Color backgroundColor;

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
      duration: const Duration(milliseconds: 1400),
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
    final double pullProgress = (_dragOffset / _triggerThreshold).clamp(0.0, 1.0);
    final bool isVisible = _dragOffset > 0 || _isRefreshing;

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
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: widget.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: widget.strokeColor.withAlpha(20),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(16),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) {
                        final double progress = _isRefreshing
                            ? _animController.value
                            : pullProgress * 0.85;

                        return CustomPaint(
                          size: const Size(96, 36),
                          painter: _LineRefreshPainter(
                            progress: progress,
                            strokeColor: widget.strokeColor,
                            isLooping: _isRefreshing,
                          ),
                        );
                      },
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

/// "Line" imzasını akıcı hatla çizen minyatür CustomPainter.
class _LineRefreshPainter extends CustomPainter {
  _LineRefreshPainter({
    required this.progress,
    required this.strokeColor,
    required this.isLooping,
  });

  final double progress;
  final Color strokeColor;
  final bool isLooping;

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
      ..color = strokeColor.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final double drawT = isLooping
        ? (progress < 0.75
            ? Curves.easeInOutCubic.transform(progress / 0.75)
            : 1.0)
        : progress.clamp(0.0, 1.0);

    for (final PathMetric metric in linePath.computeMetrics()) {
      final double currentLen = metric.length * drawT;
      if (currentLen > 0.0) {
        final Path extracted = metric.extractPath(0, currentLen);
        canvas.drawPath(extracted, glowPaint);
        canvas.drawPath(extracted, linePaint);
      }
    }

    if (drawT > 0.46) {
      final double dotT = ((drawT - 0.46) / 0.16).clamp(0.0, 1.0);
      final Offset dotPos = Offset(w * 0.41, h * 0.25);
      final Paint dotPaint = Paint()..color = strokeColor;
      canvas.drawCircle(dotPos, 1.8 * dotT, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineRefreshPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isLooping != isLooping ||
        oldDelegate.strokeColor != strokeColor;
  }
}
