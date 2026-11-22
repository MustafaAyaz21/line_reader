import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_theme_preset.dart';

/// Seçili gradyan temasını harici görsel dosyası kullanmadan, her ekran
/// çözünürlüğünde sıfır kalite kaybıyla çizen çok katmanlı ağ-gradyan boyayıcı.
class AppThemeMeshPainter extends CustomPainter {
  const AppThemeMeshPainter(this.preset);

  final AppThemePreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    switch (preset) {
      case AppThemePreset.classic:
        return;
      case AppThemePreset.pastelDawn:
        _paintPastelDawn(canvas, rect);
        return;
      case AppThemePreset.nightDepth:
        _paintNightDepth(canvas, rect);
        return;
      case AppThemePreset.softMist:
        _paintSoftMist(canvas, rect);
        return;
      case AppThemePreset.electricCoral:
        _paintElectricCoral(canvas, rect);
        return;
    }
  }

  /// 1. Görsel: Şeftali/mercankırmızı, krem-sarı, nane yeşili ve buz mavisi.
  void _paintPastelDawn(Canvas canvas, Rect rect) {
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFFFCCC2),
          Color(0xFFFDF3D2),
          Color(0xFFCFF7E5),
          Color(0xFFC8ECFF),
        ],
        stops: <double>[0.0, 0.38, 0.72, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    // Sol üst şeftali/mercan sıcaklığı
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(-0.85, -0.9),
      radius: 1.05,
      color: const Color(0xFFFFB4A6),
      alpha: 215,
    );
    // Sağ üst yumuşak pembe-lila geçiş
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.9, -0.85),
      radius: 0.95,
      color: const Color(0xFFF3BEEA),
      alpha: 185,
    );
    // Orta sağ krem-sarı gün doğumu ışığı
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.75, -0.05),
      radius: 0.95,
      color: const Color(0xFFFFF2B8),
      alpha: 210,
    );
    // Sol alt nane yeşili
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(-0.8, 0.55),
      radius: 1.0,
      color: const Color(0xFFB5F7DA),
      alpha: 205,
    );
    // Alt kenar buz mavisi ve lavanta-mavi
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.4, 0.95),
      radius: 1.05,
      color: const Color(0xFFBAE8FF),
      alpha: 215,
    );
  }

  /// 2. Görsel: Koyu okyanus mavisi, derin lacivert ve alt kısımda mürdüm/bordo.
  void _paintNightDepth(Canvas canvas, Rect rect) {
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF0A2C4F),
          Color(0xFF0B1C40),
          Color(0xFF171439),
          Color(0xFF3E1230),
        ],
        stops: <double>[0.0, 0.36, 0.68, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    // Üst sol koyu okyanus mavisi parıltı
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(-0.65, -0.88),
      radius: 1.05,
      color: const Color(0xFF114C7D),
      alpha: 195,
    );
    // Orta derin lacivert derinlik
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.65, -0.2),
      radius: 0.95,
      color: const Color(0xFF0F2654),
      alpha: 185,
    );
    // Alt sol koyu mürdüm geçişi
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(-0.55, 0.92),
      radius: 1.0,
      color: const Color(0xFF4D143D),
      alpha: 195,
    );
    // Alt sağ derin bordo geçişi
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.75, 0.88),
      radius: 1.05,
      color: const Color(0xFF631538),
      alpha: 205,
    );
  }

  /// 3. Görsel: Krem-beyaz, yumuşak lavanta, nane yeşili ve açık mavi.
  void _paintSoftMist(Canvas canvas, Rect rect) {
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFFDFBF4),
          Color(0xFFF8F5F7),
          Color(0xFFE7EFF8),
        ],
        stops: <double>[0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    // Sol üst / orta aydınlık krem-beyaz sis
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(-0.35, -0.45),
      radius: 1.1,
      color: const Color(0xFFFFFEF8),
      alpha: 230,
    );
    // Sağ üst yumuşak lavanta
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.92, -0.78),
      radius: 0.95,
      color: const Color(0xFFDABAF2),
      alpha: 195,
    );
    // Sol alt yumuşak nane yeşili
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(-0.88, 0.88),
      radius: 1.0,
      color: const Color(0xFFB3F2C8),
      alpha: 195,
    );
    // Sağ alt açık gök/periwinkle mavisi
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.88, 0.85),
      radius: 1.05,
      color: const Color(0xFF97B9EC),
      alpha: 205,
    );
  }

  /// 4. Görsel: Canlı elektrik mavisi ile sıcak mercan/kızıl geçişi.
  void _paintElectricCoral(Canvas canvas, Rect rect) {
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF102096),
          Color(0xFF213BFF),
          Color(0xFF6B39DE),
          Color(0xFFE84D52),
        ],
        stops: <double>[0.0, 0.34, 0.65, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    // Sol üst derin elektrik kobaltı
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(-0.8, -0.75),
      radius: 1.0,
      color: const Color(0xFF0E1B8C),
      alpha: 215,
    );
    // Orta-sağ parlak sıcak mercan/kızıl akışı
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.35, -0.1),
      radius: 0.98,
      color: const Color(0xFFFF6E5E),
      alpha: 215,
    );
    // Alt sol canlı elektrik mavisi dalgası
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(-0.65, 0.85),
      radius: 1.0,
      color: const Color(0xFF1E36FF),
      alpha: 210,
    );
    // Sağ üst/alt sıcak mercan kızıllığı
    _drawBloom(
      canvas,
      rect,
      center: const Alignment(0.9, 0.55),
      radius: 0.92,
      color: const Color(0xFFFF5852),
      alpha: 195,
    );

    // Metin ve buton kontrastı için dengeli yarı saydam koyu atmosfer katmanı
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0x3D090D2B),
    );
  }

  void _drawBloom(
    Canvas canvas,
    Rect rect, {
    required Alignment center,
    required double radius,
    required Color color,
    required int alpha,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: center,
        radius: radius,
        colors: <Color>[
          color.withAlpha(alpha),
          color.withAlpha((alpha * 0.45).round()),
          color.withAlpha(0),
        ],
        stops: const <double>[0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant AppThemeMeshPainter oldDelegate) {
    return oldDelegate.preset != preset;
  }
}

/// Herhangi bir ekranı seçili kod-tabanlı gradyan teması üzerine yerleştirir.
/// Varsayılan (Klasik) temada hiçbir ekstra katman çizmez.
class AppThemeBackdrop extends StatelessWidget {
  const AppThemeBackdrop({
    super.key,
    required this.child,
    this.presetOverride,
  });

  final Widget child;
  final AppThemePreset? presetOverride;

  @override
  Widget build(BuildContext context) {
    final visuals = AppThemeVisuals.of(context);
    final preset = presetOverride ?? visuals.preset;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (preset.isGradientTheme)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: AppThemeMeshPainter(preset),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

/// Ayarlar ve Okuma Görünümü ekranlarında temanın birebir kod-tabanlı canlı
/// önizleme kartını gösterir.
class AppThemePreviewSwatch extends StatelessWidget {
  const AppThemePreviewSwatch({
    super.key,
    required this.preset,
    this.width,
    this.height = 54,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.child,
  });

  final AppThemePreset preset;
  final double? width;
  final double height;
  final BorderRadius borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: preset.isGradientTheme
            ? CustomPaint(
                painter: AppThemeMeshPainter(preset),
                child: child ?? const SizedBox.expand(),
              )
            : DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFFF6F8FC),
                      Color(0xFFDCE7F7),
                      Color(0xFF2B6CB0),
                    ],
                    stops: <double>[0.0, 0.55, 1.0],
                  ),
                ),
                child: child ?? const SizedBox.expand(),
              ),
      ),
    );
  }
}
