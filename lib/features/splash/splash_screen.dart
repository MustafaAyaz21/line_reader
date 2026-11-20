import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../home/home_screen.dart';

/// Hızlı, akıcı ve logosuz Line Apps açılış ekranı (~2.0 saniye).
/// Ayrı kesik çizgi parçaları (CustomPainter) ekranın tam ortasında hızla bir
/// araya gelerek "Line Apps" harflerini oluşturur; altta sade geliştirici
/// imzası yer alır ve ardından doğrudan Ana Menü'ye geçilir.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _totalDuration = Duration(milliseconds: 2050);

  late final AnimationController _controller;
  late final Animation<double> _signatureOpacity;
  late final List<_StrokeSpec> _strokes;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _strokes = _LineAppsGlyphs.buildAllStrokes();

    _controller = AnimationController(
      vsync: this,
      duration: _totalDuration,
    );

    _signatureOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.22, 0.58, curve: Curves.easeOut),
    );

    _controller.addStatusListener(_handleAnimationStatus);
    _controller.forward();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement<void, void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    // Ekran genişliğine duyarlı, ne küçük ne aşırı büyük dengeli ölçek.
    final double canvasWidth = (screenWidth * 0.70).clamp(224.0, 316.0);
    final double unitScale = canvasWidth / _LineAppsGlyphs.totalNormalizedWidth;
    final double canvasHeight = unitScale * 1.46;

    return Scaffold(
      backgroundColor: const Color(0xFF0C1635),
      body: SafeArea(
        child: Stack(
          children: [
            // Tam merkezde kesik çizgilerden oluşan "Line Apps" kompozisyonu
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      size: Size(canvasWidth, canvasHeight),
                      painter: _LineAppsDashedPainter(
                        strokes: _strokes,
                        progress: _controller.value,
                        unitScale: unitScale,
                      ),
                    ),
                  );
                },
              ),
            ),
            // Alt geliştirici imzası (odağı bozmayan ince, düşük kontrastlı tipografi)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: FadeTransition(
                  opacity: _signatureOpacity,
                  child: const Text(
                    'Developed by Mustafa Ayaz',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.9,
                      color: Color(0x70CBD5E1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Her bir harf strokunu (çizgi parçası), başlangıç dağınıklık vektörünü ve
/// zamanlama penceresini tanımlar.
class _StrokeSpec {
  const _StrokeSpec({
    required this.buildPath,
    required this.isAccent,
    required this.startAt,
    required this.endAt,
    required this.initialOffset,
    required this.initialAngle,
  });

  final Path Function(double scale) buildPath;
  final bool isAccent;
  final double startAt;
  final double endAt;
  final Offset initialOffset;
  final double initialAngle;
}

/// Kesik çizgi parçalarının dışarıdan hızlıca toplanıp birleşerek "Line Apps"
/// harflerini oluşturmasını çizen CustomPainter.
class _LineAppsDashedPainter extends CustomPainter {
  const _LineAppsDashedPainter({
    required this.strokes,
    required this.progress,
    required this.unitScale,
  });

  final List<_StrokeSpec> strokes;
  final double progress;
  final double unitScale;

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeWidth = (unitScale * 0.102).clamp(3.8, 5.8);
    final double dashLen = (unitScale * 0.16).clamp(6.0, 10.0);
    final double maxGapLen = (unitScale * 0.13).clamp(4.5, 8.0);

    // Harfler tamamlandıktan sonra hafif bir parlaklık nefesi (0.68 -> 0.95)
    final double glowPulse = progress > 0.66
        ? math.sin(((progress - 0.66) / 0.34).clamp(0.0, 1.0) * math.pi)
        : 0.0;

    final Paint linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    // Dikey ortalama için üst pay
    final double verticalOffset = (size.height - unitScale * 1.32) * 0.5;

    canvas.save();
    canvas.translate(0, verticalOffset);

    for (final spec in strokes) {
      if (progress < spec.startAt) continue;

      final double rawT =
          ((progress - spec.startAt) / (spec.endAt - spec.startAt))
              .clamp(0.0, 1.0);
      final double easedMove = Curves.easeOutCubic.transform(rawT);
      final double easedDraw = Curves.easeOutQuad.transform(
        (rawT * 1.18).clamp(0.0, 1.0),
      );
      final double opacity = (rawT * 3.2).clamp(0.0, 1.0);

      // Başlangıçta belirgin kesik çizgiler, yerleşirken pürüzsüz bütünleşir.
      final double dashGapFactor =
          (1.0 - ((rawT - 0.58) / 0.42).clamp(0.0, 1.0));

      final Path fullPath = spec.buildPath(unitScale);
      final Rect bounds = fullPath.getBounds();
      final Offset pivot = bounds.center;

      final double dx = spec.initialOffset.dx * unitScale * (1.0 - easedMove);
      final double dy = spec.initialOffset.dy * unitScale * (1.0 - easedMove);
      final double angle = spec.initialAngle * (1.0 - easedMove);

      final Color baseColor =
          spec.isAccent ? const Color(0xFF60A5FA) : const Color(0xFFF8FAFC);
      final int alpha = (opacity * 255).round().clamp(0, 255);
      linePaint.color = baseColor.withAlpha(alpha);

      final Path renderPath = _extractAnimatedPath(
        fullPath: fullPath,
        drawFraction: easedDraw,
        dashLength: dashLen,
        gapLength: maxGapLen * dashGapFactor,
      );

      canvas.save();
      canvas.translate(dx + pivot.dx, dy + pivot.dy);
      canvas.rotate(angle);
      canvas.translate(-pivot.dx, -pivot.dy);

      if (spec.isAccent && rawT > 0.55) {
        final int glowAlpha =
            ((0.18 + 0.16 * glowPulse) * opacity * 255).round().clamp(0, 110);
        glowPaint.color = const Color(0xFF60A5FA).withAlpha(glowAlpha);
        canvas.drawPath(renderPath, glowPaint);
      }

      canvas.drawPath(renderPath, linePaint);
      canvas.restore();
    }

    canvas.restore();
  }

  Path _extractAnimatedPath({
    required Path fullPath,
    required double drawFraction,
    required double dashLength,
    required double gapLength,
  }) {
    final Path output = Path();
    for (final PathMetric metric in fullPath.computeMetrics()) {
      final double targetLength = metric.length * drawFraction;
      if (targetLength <= 0.01) continue;

      if (gapLength <= 0.4) {
        output.addPath(metric.extractPath(0, targetLength), Offset.zero);
        continue;
      }

      double distance = 0.0;
      while (distance < targetLength) {
        final double nextEnd = math.min(distance + dashLength, targetLength);
        output.addPath(metric.extractPath(distance, nextEnd), Offset.zero);
        distance = nextEnd + gapLength;
      }
    }
    return output;
  }

  @override
  bool shouldRepaint(covariant _LineAppsDashedPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.unitScale != unitScale;
  }
}

/// "Line Apps" yazısının geometrik monoline vektör strok tanımlarını üretir.
abstract final class _LineAppsGlyphs {
  static const double _letterGap = 0.16;
  static const double _wordSpace = 0.36;

  /// Tüm harf genişlikleri + harf aralıkları toplamı.
  static const double totalNormalizedWidth =
      0.54 + // L
      _letterGap +
      0.18 + // i
      _letterGap +
      0.56 + // n
      _letterGap +
      0.56 + // e
      _wordSpace +
      0.66 + // A
      _letterGap +
      0.56 + // p
      _letterGap +
      0.56 + // p
      _letterGap +
      0.52; // s

  static List<_StrokeSpec> buildAllStrokes() {
    final raw = <_RawStroke>[];
    double x = 0.0;

    // L
    raw.add(_line(x + 0.08, 0.04, x + 0.08, 0.52, false));
    raw.add(_line(x + 0.08, 0.52, x + 0.08, 0.98, false));
    raw.add(_line(x + 0.08, 0.98, x + 0.52, 0.98, false));
    x += 0.54 + _letterGap;

    // i
    raw.add(_line(x + 0.09, 0.14, x + 0.09, 0.20, false));
    raw.add(_line(x + 0.09, 0.38, x + 0.09, 0.68, false));
    raw.add(_line(x + 0.09, 0.68, x + 0.09, 0.98, false));
    x += 0.18 + _letterGap;

    // n
    raw.add(_line(x + 0.06, 0.38, x + 0.06, 0.98, false));
    raw.add(
      _cubic(
        x + 0.06, 0.56,
        x + 0.10, 0.34,
        x + 0.48, 0.34,
        x + 0.50, 0.58,
        false,
      ),
    );
    raw.add(_line(x + 0.50, 0.58, x + 0.50, 0.98, false));
    x += 0.56 + _letterGap;

    // e
    raw.add(_line(x + 0.06, 0.67, x + 0.52, 0.67, false));
    raw.add(
      _cubic(
        x + 0.52, 0.67,
        x + 0.52, 0.34,
        x + 0.06, 0.34,
        x + 0.06, 0.67,
        false,
      ),
    );
    raw.add(
      _cubic(
        x + 0.06, 0.67,
        x + 0.06, 0.98,
        x + 0.34, 1.02,
        x + 0.49, 0.90,
        false,
      ),
    );
    x += 0.56 + _wordSpace;

    // A
    raw.add(_line(x + 0.04, 0.98, x + 0.185, 0.51, true));
    raw.add(_line(x + 0.185, 0.51, x + 0.33, 0.04, true));
    raw.add(_line(x + 0.33, 0.04, x + 0.475, 0.51, true));
    raw.add(_line(x + 0.475, 0.51, x + 0.62, 0.98, true));
    raw.add(_line(x + 0.15, 0.68, x + 0.51, 0.68, true));
    x += 0.66 + _letterGap;

    // p #1
    _addLowercaseP(raw, x);
    x += 0.56 + _letterGap;

    // p #2
    _addLowercaseP(raw, x);
    x += 0.56 + _letterGap;

    // s
    raw.add(
      _cubic(
        x + 0.46, 0.44,
        x + 0.32, 0.32,
        x + 0.06, 0.38,
        x + 0.08, 0.56,
        true,
      ),
    );
    raw.add(
      _cubic(
        x + 0.08, 0.56,
        x + 0.10, 0.68,
        x + 0.46, 0.66,
        x + 0.48, 0.80,
        true,
      ),
    );
    raw.add(
      _cubic(
        x + 0.48, 0.80,
        x + 0.50, 0.98,
        x + 0.22, 1.02,
        x + 0.06, 0.90,
        true,
      ),
    );

    // Deterministik başlangıç saçılım vektörleri ve hızlı ardışık zamanlama
    // (0.02 -> 0.72 aralığında tüm harfler hızlıca toplanıp oturur).
    const double timelineStart = 0.02;
    const double timelineEnd = 0.72;
    const double strokeDuration = 0.28;
    final double usableSpan = (timelineEnd - timelineStart) - strokeDuration;

    final int count = raw.length;
    return List<_StrokeSpec>.generate(count, (i) {
      final double tStart =
          count > 1 ? timelineStart + (usableSpan * i / (count - 1)) : 0.02;
      final double tEnd = (tStart + strokeDuration).clamp(tStart + 0.08, 0.80);

      // Çizgilerin farklı yönlerden dengeli biçimde merkeze toplanması için.
      final double angleSeed = (i * 2.39996) % (2 * math.pi);
      final double radius = 0.42 + (i % 3) * 0.16;
      final Offset offset = Offset(
        math.cos(angleSeed) * radius,
        math.sin(angleSeed) * radius,
      );
      final double tilt = ((i.isEven ? 1 : -1) * (0.22 + (i % 4) * 0.08));

      return _StrokeSpec(
        buildPath: raw[i].buildPath,
        isAccent: raw[i].isAccent,
        startAt: tStart,
        endAt: tEnd,
        initialOffset: offset,
        initialAngle: tilt,
      );
    });
  }

  static void _addLowercaseP(List<_RawStroke> target, double x) {
    target.add(_line(x + 0.07, 0.38, x + 0.07, 0.86, true));
    target.add(_line(x + 0.07, 0.86, x + 0.07, 1.30, true));
    target.add(
      _cubic(
        x + 0.07, 0.50,
        x + 0.18, 0.34,
        x + 0.50, 0.36,
        x + 0.50, 0.67,
        true,
      ),
    );
    target.add(
      _cubic(
        x + 0.50, 0.67,
        x + 0.50, 0.96,
        x + 0.18, 1.00,
        x + 0.07, 0.84,
        true,
      ),
    );
  }

  static _RawStroke _line(
    double x1,
    double y1,
    double x2,
    double y2,
    bool isAccent,
  ) {
    return _RawStroke(
      isAccent: isAccent,
      buildPath: (s) => Path()
        ..moveTo(x1 * s, y1 * s)
        ..lineTo(x2 * s, y2 * s),
    );
  }

  static _RawStroke _cubic(
    double x0,
    double y0,
    double cx1,
    double cy1,
    double cx2,
    double cy2,
    double x1,
    double y1,
    bool isAccent,
  ) {
    return _RawStroke(
      isAccent: isAccent,
      buildPath: (s) => Path()
        ..moveTo(x0 * s, y0 * s)
        ..cubicTo(cx1 * s, cy1 * s, cx2 * s, cy2 * s, x1 * s, y1 * s),
    );
  }
}

class _RawStroke {
  const _RawStroke({
    required this.buildPath,
    required this.isAccent,
  });

  final Path Function(double scale) buildPath;
  final bool isAccent;
}
