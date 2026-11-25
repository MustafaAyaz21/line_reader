import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';

import '../../core/platform/process_text_channel.dart';
import '../home/home_screen.dart';

/// Lüks, akıcı ve sürekli akan altın çizgili Line Apps açılış ekranı (~2.1 saniye).
/// Koyu obsidiyen zeminde parlayan altın bir okuma imleci tek bir sürekli hat
/// halinde "Line" formunu çizer, altından zarif "APPS" tipografisi belirir.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _totalDuration = Duration(milliseconds: 2150);

  late final AnimationController _controller;
  late final Animation<double> _signatureOpacity;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _totalDuration,
    );

    _signatureOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.40, 0.80, curve: Curves.easeOut),
    );

    _controller.addStatusListener(_handleAnimationStatus);
    ProcessTextChannel.ensureInitialized();
    ProcessTextChannel.pendingTextNotifier
        .addListener(_handleExternalProcessText);

    if (ProcessTextChannel.hasPendingText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToHome();
      });
    } else {
      _controller.forward();
    }
  }

  void _handleExternalProcessText() {
    if (ProcessTextChannel.hasPendingText && mounted) {
      _navigateToHome();
    }
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
        transitionDuration: const Duration(milliseconds: 320),
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
    ProcessTextChannel.pendingTextNotifier
        .removeListener(_handleExternalProcessText);
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: SafeArea(
        child: Stack(
          children: [
            // Hafif lüks ambiyans parıltısı
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD97706).withAlpha(18),
                      blurRadius: 100,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
            // Tam merkezde akan altın çizgi kompozisyonu
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      size: const Size(280, 160),
                      painter: _FlowingGoldenLinePainter(
                        progress: _controller.value,
                      ),
                    ),
                  );
                },
              ),
            ),
            // Alt geliştirici imzası
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: FadeTransition(
                  opacity: _signatureOpacity,
                  child: const Text(
                    'Developed by Mustafa Ayaz',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.2,
                      color: Color(0x80D1D5DB),
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

/// Akıcı tek bir altın okuma çizgisinin "Line" kelimesini çizip parıldamasını
/// ve ardından "APPS" tipografisini getirmesini sağlayan ressam.
class _FlowingGoldenLinePainter extends CustomPainter {
  const _FlowingGoldenLinePainter({
    required this.progress,
  });

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // 1) "Line" sürekli hat yolu (Continuous Flowing Script Path)
    final Path linePath = Path();
    
    // Başlangıç: Sol taraftan gelen hafif zarif okuma hattı
    linePath.moveTo(w * 0.08, h * 0.44);
    linePath.cubicTo(w * 0.16, h * 0.44, w * 0.20, h * 0.42, w * 0.24, h * 0.18);
    // 'L' büyük harf gövdesi ve alt kıvrımı
    linePath.cubicTo(w * 0.25, h * 0.08, w * 0.22, h * 0.08, w * 0.21, h * 0.18);
    linePath.cubicTo(w * 0.19, h * 0.38, w * 0.21, h * 0.58, w * 0.25, h * 0.58);
    linePath.cubicTo(w * 0.30, h * 0.58, w * 0.34, h * 0.52, w * 0.36, h * 0.42);
    
    // 'i' harfi gövdesi
    linePath.cubicTo(w * 0.38, h * 0.32, w * 0.39, h * 0.32, w * 0.40, h * 0.44);
    linePath.cubicTo(w * 0.41, h * 0.56, w * 0.44, h * 0.58, w * 0.47, h * 0.48);
    
    // 'n' harfi ilk kemer
    linePath.cubicTo(w * 0.49, h * 0.34, w * 0.51, h * 0.32, w * 0.53, h * 0.44);
    linePath.cubicTo(w * 0.54, h * 0.56, w * 0.56, h * 0.58, w * 0.59, h * 0.44);
    linePath.cubicTo(w * 0.61, h * 0.32, w * 0.63, h * 0.34, w * 0.65, h * 0.48);
    linePath.cubicTo(w * 0.66, h * 0.58, w * 0.69, h * 0.58, w * 0.72, h * 0.46);
    
    // 'e' harfi döngüsü ve bitiş kuyruğu
    linePath.cubicTo(w * 0.74, h * 0.34, w * 0.78, h * 0.34, w * 0.78, h * 0.44);
    linePath.cubicTo(w * 0.78, h * 0.50, w * 0.74, h * 0.58, w * 0.69, h * 0.58);
    linePath.cubicTo(w * 0.74, h * 0.58, w * 0.82, h * 0.56, w * 0.92, h * 0.56);

    // 2) Altın çizgi boyası
    final Paint linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // Çizgi animasyon ilerlemesi (0.0 -> 0.72)
    final double drawT = Curves.easeInOutCubic.transform(
      (progress / 0.72).clamp(0.0, 1.0),
    );

    // Altın ışıltı gradyanı
    final Rect bounds = Rect.fromLTWH(0, 0, w, h);
    final Shader goldShader = const LinearGradient(
      colors: [
        Color(0xFFFDE68A), // Açık altın
        Color(0xFFF59E0B), // Sıcak kehribar
        Color(0xFFD97706), // Bronz altın
        Color(0xFFFBBF24), // Parlak altın
      ],
      stops: [0.0, 0.35, 0.70, 1.0],
    ).createShader(bounds);

    linePaint.shader = goldShader;
    glowPaint.color = const Color(0xFFF59E0B).withAlpha(140);

    // Metrikler üzerinden yolu çiz
    Offset? cursorHead;
    for (final PathMetric metric in linePath.computeMetrics()) {
      final double currentLen = metric.length * drawT;
      if (currentLen > 0.0) {
        final Path extracted = metric.extractPath(0, currentLen);
        canvas.drawPath(extracted, glowPaint);
        canvas.drawPath(extracted, linePaint);

        final Tangent? tangent = metric.getTangentForOffset(currentLen);
        if (tangent != null) {
          cursorHead = tangent.position;
        }
      }
    }

    // 'i' harfinin noktası (ilerleme %46'yı geçtiğinde zarif bir parıltıyla konur)
    if (progress > 0.46) {
      final double dotT = ((progress - 0.46) / 0.16).clamp(0.0, 1.0);
      final double dotScale = Curves.elasticOut.transform(dotT);
      final Offset dotPos = Offset(w * 0.41, h * 0.25);
      final Paint dotPaint = Paint()..color = const Color(0xFFFDE68A);
      final Paint dotGlow = Paint()
        ..color = const Color(0xFFF59E0B).withAlpha(160)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      canvas.drawCircle(dotPos, 2.8 * dotScale, dotGlow);
      canvas.drawCircle(dotPos, 2.2 * dotScale, dotPaint);
    }

    // Çizen ucun başındaki parıldayan canlı imleç parçacığı
    if (cursorHead != null && progress < 0.78) {
      final double pulse = math.sin(progress * 18) * 0.5 + 0.5;
      final Paint headGlow = Paint()
        ..color = const Color(0xFFFDE68A).withAlpha((180 + 75 * pulse).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final Paint headCenter = Paint()..color = Colors.white;

      canvas.drawCircle(cursorHead, 4.2, headGlow);
      canvas.drawCircle(cursorHead, 2.2, headCenter);
    }

    // 3) Alt tipografi: "APPS" ve alt çizgi (progress > 0.50)
    if (progress > 0.50) {
      final double appsT = ((progress - 0.50) / 0.38).clamp(0.0, 1.0);
      final double opacity = Curves.easeOut.transform(appsT);

      // İnce şık ayırıcı altın çizgi
      final Paint dividerPaint = Paint()
        ..color = const Color(0xFFF59E0B).withAlpha((opacity * 160).round())
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;

      final double divLeft = w * 0.34;
      final double divRight = w * 0.34 + (w * 0.32 * appsT);
      canvas.drawLine(
        Offset(divLeft, h * 0.68),
        Offset(divRight, h * 0.68),
        dividerPaint,
      );

      // "APPS" metni
      final textSpan = TextSpan(
        text: 'A  P  P  S',
        style: TextStyle(
          color: const Color(0xFFF3F4F6).withAlpha((opacity * 240).round()),
          fontSize: 12.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 4.8,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w);

      textPainter.paint(
        canvas,
        Offset((w - textPainter.width) * 0.5, h * 0.74),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FlowingGoldenLinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
