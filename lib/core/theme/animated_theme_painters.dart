import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme_preset.dart';

/// 4 hareketli arka plan temasını (Ametist Galaksi, Okyanus Derinlikleri,
/// Sıcak Latte Bokeh, Adaçayı & Gün Işığı) saf vektör Canvas çizimiyle,
/// dikişsiz (integer-harmonic) ve çok sakin tempoda çizen boyayıcı.
class AnimatedThemePainter extends CustomPainter {
  const AnimatedThemePainter({
    required this.preset,
    required this.progress,
    this.isPreview = false,
    this.isEcoMode = false,
  });

  final AppThemePreset preset;

  /// `0.0 .. 1.0` arası normalize edilmiş döngü ilerlemesi.
  /// Tüm hareketler tam sayı harmonik kullandığı için döngü başında sıçrama olmaz.
  final double progress;

  /// Ayarlar önizleme kartı için daha kompakt ve belirgin oranlar kullanır.
  final bool isPreview;

  /// Pil Dostu Animasyon modunda parçacık sayısı azaltılır.
  final bool isEcoMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    switch (preset) {
      case AppThemePreset.amethystGalaxy:
        _paintAmethystGalaxy(canvas, rect, size);
        return;
      case AppThemePreset.oceanDepths:
        _paintOceanDepths(canvas, rect, size);
        return;
      case AppThemePreset.warmLatteBokeh:
        _paintWarmLatteBokeh(canvas, rect, size);
        return;
      case AppThemePreset.sageSunlight:
        _paintSageSunlight(canvas, rect, size);
        return;
      case AppThemePreset.sakuraGarden:
        _paintSakuraGarden(canvas, rect, size);
        return;
      case AppThemePreset.aleviPower:
        _paintAleviPower(canvas, rect, size);
        return;
      default:
        return;
    }
  }

  // ---------------------------------------------------------------------------
  // 1. AMETİST GALAKSİ
  // ---------------------------------------------------------------------------
  void _paintAmethystGalaxy(Canvas canvas, Rect rect, Size size) {
    final t = progress;
    final tau = math.pi * 2;

    // Koyu mor-gece uzay zemini (#0C0719 -> #140B26)
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF0C0719),
          Color(0xFF140B26),
          Color(0xFF0E081E),
        ],
        stops: <double>[0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // Hafif uzay nebulası derinliği
    _drawSoftGlow(
      canvas,
      Offset(size.width * 0.22, size.height * 0.18),
      size.shortestSide * 0.65,
      const Color(0xFF4C1D95),
      0.16,
    );
    _drawSoftGlow(
      canvas,
      Offset(size.width * 0.82, size.height * 0.80),
      size.shortestSide * 0.60,
      const Color(0xFF831843),
      0.14,
    );

    // Çok yavaş göz kırpan arka plan yıldızları
    final starCount = isPreview ? 18 : 42;
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < starCount; i++) {
      final sx = _hash(i * 13 + 1) * size.width;
      final sy = _hash(i * 29 + 7) * size.height;
      final freq = (i % 3) + 1; // 1, 2 veya 3 tam döngü
      final phase = _hash(i * 43 + 3) * tau;
      final twinkle = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * tau * freq + phase));
      final radius = (isPreview ? 0.7 : 0.9) + _hash(i * 19 + 5) * (isPreview ? 0.9 : 1.3);
      final tint = i % 5 == 0
          ? const Color(0xFFE9D5FF)
          : i % 7 == 0
              ? const Color(0xFFFBCFE8)
              : const Color(0xFFF8FAFC);
      starPaint.color = tint.withAlpha((twinkle * 165).round());
      canvas.drawCircle(Offset(sx, sy), radius, starPaint);
    }

    // Galaksi merkezi (hafif eğik eliptik düzlem)
    final center = Offset(size.width * 0.5, size.height * (isPreview ? 0.52 : 0.44));
    final minDim = size.shortestSide;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.28);

    // Katmanlı vektör ametist / mor / gül-mercan eliptik galaksi halkaları
    final ringSpecs = <({double rx, double ry, Color color, double stroke, double alpha})>[
      (rx: minDim * 0.46, ry: minDim * 0.19, color: const Color(0xFF7E22CE), stroke: isPreview ? 7 : 18, alpha: 0.13),
      (rx: minDim * 0.37, ry: minDim * 0.15, color: const Color(0xFFA855F7), stroke: isPreview ? 5 : 13, alpha: 0.17),
      (rx: minDim * 0.28, ry: minDim * 0.115, color: const Color(0xFFE879F9), stroke: isPreview ? 4 : 10, alpha: 0.20),
      (rx: minDim * 0.19, ry: minDim * 0.08, color: const Color(0xFFFB7185), stroke: isPreview ? 3 : 8, alpha: 0.22),
    ];

    for (var i = 0; i < ringSpecs.length; i++) {
      final spec = ringSpecs[i];
      final breathe = 1.0 + 0.025 * math.sin(t * tau * 2 + i * 1.1);
      final oval = Rect.fromCenter(
        center: Offset.zero,
        width: spec.rx * 2 * breathe,
        height: spec.ry * 2 * breathe,
      );
      // GPU dostu yumuşak dış hare (MaskFilter.blur kullanmadan)
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.stroke
        ..color = spec.color.withAlpha((spec.alpha * 165).round());
      canvas.drawOval(oval, ringPaint);

      final midPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.stroke * 0.45
        ..color = spec.color.withAlpha((spec.alpha * 225).round());
      canvas.drawOval(oval, midPaint);

      final crispPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isPreview ? 0.8 : 1.15
        ..color = spec.color.withAlpha(((spec.alpha + 0.18) * 255).round());
      canvas.drawOval(oval, crispPaint);
    }

    // Çok ağır, meditatif hızda dönen kesikli yörünge çizgileri
    _drawDashedOrbit(
      canvas,
      rx: minDim * 0.42,
      ry: minDim * 0.175,
      dashCount: isPreview ? 22 : 38,
      angleOffset: t * tau * 1,
      color: const Color(0xFFD8B4FE).withAlpha(78),
      strokeWidth: isPreview ? 0.8 : 1.1,
    );
    _drawDashedOrbit(
      canvas,
      rx: minDim * 0.31,
      ry: minDim * 0.13,
      dashCount: isPreview ? 18 : 30,
      angleOffset: -t * tau * 1 + 0.4,
      color: const Color(0xFFF9A8D4).withAlpha(72),
      strokeWidth: isPreview ? 0.7 : 1.0,
    );

    // Yörüngede çok yavaş süzülen pastel sarı, gök mavisi, pembe ve lila yıldızlar
    const orbitColors = <Color>[
      Color(0xFFFEF08A), // Pastel sarı
      Color(0xFF7DD3FC), // Gök mavisi
      Color(0xFFF9A8D4), // Pembe
      Color(0xFFD8B4FE), // Lila
    ];
    final orbiterCount = isPreview ? 8 : 14;
    for (var i = 0; i < orbiterCount; i++) {
      final lane = 0.21 + (i % 4) * 0.085;
      final rx = minDim * lane;
      final ry = rx * 0.42;
      final dir = i.isEven ? 1.0 : -1.0;
      final speed = (i % 2 == 0) ? 1.0 : 2.0;
      final angle = _hash(i * 31 + 11) * tau + dir * t * tau * speed;
      final pos = Offset(math.cos(angle) * rx, math.sin(angle) * ry);
      final color = orbitColors[i % orbitColors.length];
      final sparkle = 0.65 + 0.35 * math.sin(t * tau * 3 + i * 0.9);
      final r = (isPreview ? 1.5 : 2.2) + (i % 3) * (isPreview ? 0.4 : 0.7);

      _drawSoftGlow(canvas, pos, r * 3.8, color, 0.38 * sparkle);
      canvas.drawCircle(
        pos,
        r,
        Paint()..color = color.withAlpha((sparkle * 235).round()),
      );
    }

    canvas.restore();

    // Merkezde yumuşakça nefes alan parlak pembe-beyaz "Kuantum Pulsar" çekirdek ışığı
    final pulse = 0.5 + 0.5 * math.sin(t * tau * 4);
    final coreOuter = minDim * (isPreview ? 0.18 : 0.16) * (0.92 + 0.16 * pulse);
    _drawSoftGlow(canvas, center, coreOuter, const Color(0xFFF472B6), 0.36 + 0.14 * pulse);
    _drawSoftGlow(canvas, center, coreOuter * 0.52, const Color(0xFFFCE7F3), 0.58 + 0.18 * pulse);
    _drawSoftGlow(canvas, center, coreOuter * 0.22, Colors.white, 0.85);

    // İnce 4 kollu pulsar yıldız parıltısı
    final flareLen = minDim * (isPreview ? 0.095 : 0.085) * (0.88 + 0.24 * pulse);
    final flarePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = isPreview ? 1.1 : 1.6
      ..color = const Color(0xFFFFF1F7).withAlpha((165 + pulse * 60).round());
    canvas.drawLine(
      Offset(center.dx - flareLen, center.dy),
      Offset(center.dx + flareLen, center.dy),
      flarePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - flareLen * 0.75),
      Offset(center.dx, center.dy + flareLen * 0.75),
      flarePaint,
    );
  }

  void _drawDashedOrbit(
    Canvas canvas, {
    required double rx,
    required double ry,
    required int dashCount,
    required double angleOffset,
    required Color color,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    final step = (math.pi * 2) / dashCount;
    for (var i = 0; i < dashCount; i++) {
      final a0 = angleOffset + i * step;
      final a1 = a0 + step * 0.44;
      final p0 = Offset(math.cos(a0) * rx, math.sin(a0) * ry);
      final p1 = Offset(math.cos(a1) * rx, math.sin(a1) * ry);
      canvas.drawLine(p0, p1, paint);
    }
  }

  // ---------------------------------------------------------------------------
  // 2. OKYANUS DERİNLİKLERİ
  // ---------------------------------------------------------------------------
  void _paintOceanDepths(Canvas canvas, Rect rect, Size size) {
    final t = progress;
    final tau = math.pi * 2;

    // Derin okyanus petrol yeşili-lacivert zemini (#07171F -> #051218 -> #081D24)
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF07171F),
          Color(0xFF051218),
          Color(0xFF081D24),
        ],
        stops: <double>[0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // Yukarıdan diyagonal inip çok ağır salınan yumuşak sualtı ışık hüzmeleri
    final rayCount = isPreview ? 3 : 5;
    for (var i = 0; i < rayCount; i++) {
      final baseX = size.width * (0.12 + i * (0.76 / math.max(1, rayCount - 1)));
      final sway = math.sin(t * tau * 2 + i * 1.3) * size.width * 0.035;
      final topW = size.width * (isPreview ? 0.09 : 0.065);
      final botW = size.width * (isPreview ? 0.24 : 0.19);
      final rayPath = Path()
        ..moveTo(baseX - topW + sway, -10)
        ..lineTo(baseX + topW + sway, -10)
        ..lineTo(baseX + size.width * 0.16 + botW + sway * 1.4, size.height * 0.85)
        ..lineTo(baseX + size.width * 0.16 - botW + sway * 1.4, size.height * 0.85)
        ..close();
      final rayAlpha = 0.045 + 0.025 * (0.5 + 0.5 * math.sin(t * tau * 2 + i));
      final rayPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            const Color(0xFF5EEAD4).withAlpha((rayAlpha * 255).round()),
            const Color(0xFF38BDF8).withAlpha((rayAlpha * 0.45 * 255).round()),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ).createShader(rect);
      canvas.drawPath(rayPath, rayPaint);
    }

    // Yavaşça yükselen narin su kabarcıkları
    final bubbleCount = isPreview ? 10 : 22;
    final bubbleStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isPreview ? 0.7 : 1.0;
    for (var i = 0; i < bubbleCount; i++) {
      final speed = (i % 3) + 1;
      final yNorm = (1.0 - ((_hash(i * 17 + 3) + t * speed) % 1.0));
      final bx = _hash(i * 23 + 9) * size.width +
          math.sin(t * tau * 3 + i * 1.4) * (isPreview ? 3.5 : 8.0);
      final by = yNorm * size.height;
      final br = (isPreview ? 1.2 : 1.6) + _hash(i * 37 + 2) * (isPreview ? 2.0 : 3.2);
      final fade = math.sin(yNorm * math.pi).clamp(0.0, 1.0);
      bubbleStroke.color = const Color(0xFF99F6E4).withAlpha((fade * 95).round());
      canvas.drawCircle(Offset(bx, by), br, bubbleStroke);
      canvas.drawCircle(
        Offset(bx - br * 0.3, by - br * 0.3),
        br * 0.25,
        Paint()..color = Colors.white.withAlpha((fade * 110).round()),
      );
    }

    // Ağır ve huzurlu tempoda yüzen stilize küçük balık sürüsü
    final fishCount = isPreview ? 4 : 7;
    for (var i = 0; i < fishCount; i++) {
      final goingRight = i % 2 == 0;
      final laneY = size.height * (0.28 + (i % 4) * 0.13);
      final rawX = (_hash(i * 41 + 5) + (goingRight ? t : -t)) % 1.0;
      final fx = (rawX < 0 ? rawX + 1.0 : rawX) * (size.width + 60) - 30;
      final fy = laneY + math.sin(t * tau * 2 + i * 1.1) * (isPreview ? 4 : 12);
      final fishSize = (isPreview ? 6.5 : 11.0) + (i % 3) * (isPreview ? 1.5 : 2.8);
      _drawStylizedFish(
        canvas,
        center: Offset(fx, fy),
        size: fishSize,
        facingRight: goingRight,
        tailWag: math.sin(t * tau * 8 + i * 1.7),
        color: i % 3 == 0
            ? const Color(0xFF5EEAD4).withAlpha(115)
            : const Color(0xFF7DD3FC).withAlpha(95),
      );
    }

    // Suyun içinde çok yavaş süzülen parlayan yarı saydam denizanaları
    final jellySpecs = isPreview
        ? <({double x, double y, double scale, Color color})>[
            (x: 0.26, y: 0.42, scale: 0.55, color: const Color(0xFF67E8F9)),
            (x: 0.74, y: 0.36, scale: 0.45, color: const Color(0xFF5EEAD4)),
          ]
        : <({double x, double y, double scale, Color color})>[
            (x: 0.22, y: 0.30, scale: 1.0, color: const Color(0xFF67E8F9)),
            (x: 0.76, y: 0.44, scale: 0.82, color: const Color(0xFF5EEAD4)),
            (x: 0.48, y: 0.62, scale: 0.68, color: const Color(0xFFA5F3FC)),
          ];

    for (var i = 0; i < jellySpecs.length; i++) {
      final spec = jellySpecs[i];
      final bobY = math.sin(t * tau * 2 + i * 2.0) * (isPreview ? 4 : 14);
      final driftX = math.cos(t * tau * 1 + i * 1.5) * (isPreview ? 3 : 10);
      final pos = Offset(size.width * spec.x + driftX, size.height * spec.y + bobY);
      _drawJellyfish(
        canvas,
        center: pos,
        radius: (isPreview ? 12 : 22) * spec.scale,
        color: spec.color,
        phase: t * tau * 3 + i * 1.7,
      );
    }

    // Alt kısımda koyu mercan resifi siluetleri, yavaş dalgalanan su yosunları ve biyolüminesans ışıklar
    _drawReefAndKelp(canvas, size, t);
  }

  void _drawJellyfish(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required double phase,
  }) {
    final pulse = 1.0 + 0.08 * math.sin(phase);
    final rx = radius * pulse;
    final ry = radius * 0.74 / pulse;

    // Yumuşak biyolüminesans hare
    _drawSoftGlow(canvas, center, radius * 2.1, color, 0.22);

    // Yarı saydam kubbe
    final domeRect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    final domePath = Path()
      ..moveTo(domeRect.left, center.dy)
      ..arcTo(domeRect, math.pi, math.pi, false)
      ..quadraticBezierTo(
        center.dx,
        center.dy + ry * 0.18,
        domeRect.left,
        center.dy,
      )
      ..close();

    canvas.drawPath(
      domePath,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 0.9,
          colors: <Color>[
            color.withAlpha(115),
            color.withAlpha(42),
          ],
        ).createShader(domeRect),
    );
    canvas.drawPath(
      domePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isPreview ? 0.9 : 1.2
        ..color = color.withAlpha(140),
    );

    // İnce dalgalanan dokunaçlar
    final tentaclePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isPreview ? 0.8 : 1.15
      ..strokeCap = StrokeCap.round
      ..color = color.withAlpha(105);

    const tentacleCount = 4;
    for (var i = 0; i < tentacleCount; i++) {
      final frac = (i + 1) / (tentacleCount + 1);
      final startX = domeRect.left + domeRect.width * frac;
      final len = radius * (1.35 + (i % 2) * 0.35);
      final wave1 = math.sin(phase + i * 0.9) * radius * 0.26;
      final wave2 = math.cos(phase + i * 0.9) * radius * 0.28;
      final path = Path()
        ..moveTo(startX, center.dy + ry * 0.05)
        ..cubicTo(
          startX + wave1,
          center.dy + len * 0.38,
          startX - wave2,
          center.dy + len * 0.72,
          startX + wave1 * 0.6,
          center.dy + len,
        );
      canvas.drawPath(path, tentaclePaint);
    }
  }

  void _drawStylizedFish(
    Canvas canvas, {
    required Offset center,
    required double size,
    required bool facingRight,
    required double tailWag,
    required Color color,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (!facingRight) {
      canvas.scale(-1, 1);
    }
    final paint = Paint()..color = color;

    // Zarif damla gövde
    final body = Path()
      ..moveTo(size * 0.65, 0)
      ..quadraticBezierTo(size * 0.1, -size * 0.38, -size * 0.55, 0)
      ..quadraticBezierTo(size * 0.1, size * 0.38, size * 0.65, 0)
      ..close();
    canvas.drawPath(body, paint);

    // Hafif sallanan kuyruk
    final wag = tailWag * size * 0.16;
    final tail = Path()
      ..moveTo(-size * 0.45, 0)
      ..lineTo(-size * 0.92, -size * 0.30 + wag)
      ..lineTo(-size * 0.80, wag * 0.3)
      ..lineTo(-size * 0.92, size * 0.30 + wag)
      ..close();
    canvas.drawPath(tail, paint);

    canvas.restore();
  }

  void _drawReefAndKelp(Canvas canvas, Size size, double t) {
    final tau = math.pi * 2;
    final h = size.height;
    final w = size.width;
    final reefHeight = h * (isPreview ? 0.24 : 0.14);

    // Çok yavaş dalgalanan su yosunları (arka plan)
    final kelpCount = isPreview ? 5 : 9;
    for (var i = 0; i < kelpCount; i++) {
      final kx = w * (0.06 + i * (0.88 / math.max(1, kelpCount - 1)));
      final kh = reefHeight * (0.95 + _hash(i * 11 + 2) * 0.95);
      final sway = math.sin(t * tau * 2 + i * 0.85) * (isPreview ? 5 : 14);
      final kelpPath = Path()
        ..moveTo(kx, h)
        ..cubicTo(
          kx - sway * 0.5,
          h - kh * 0.35,
          kx + sway,
          h - kh * 0.7,
          kx + sway * 0.65,
          h - kh,
        );
      canvas.drawPath(
        kelpPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPreview ? 2.2 : 4.2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF0C3640).withAlpha(185),
      );
    }

    // Koyu mercan resifi silueti
    final reefPath = Path()
      ..moveTo(0, h)
      ..lineTo(0, h - reefHeight * 0.55)
      ..quadraticBezierTo(w * 0.14, h - reefHeight * 0.92, w * 0.28, h - reefHeight * 0.42)
      ..quadraticBezierTo(w * 0.46, h - reefHeight * 0.18, w * 0.62, h - reefHeight * 0.62)
      ..quadraticBezierTo(w * 0.80, h - reefHeight * 1.0, w, h - reefHeight * 0.48)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(reefPath, Paint()..color = const Color(0xFF041016));

    // Minik biyolüminesans mercan ışıkları
    final glowCount = isPreview ? 5 : 10;
    for (var i = 0; i < glowCount; i++) {
      final gx = w * (0.08 + i * (0.84 / math.max(1, glowCount - 1)));
      final gy = h - reefHeight * (0.22 + _hash(i * 19 + 4) * 0.45);
      final pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * tau * 3 + i * 1.3));
      final color = i.isEven ? const Color(0xFF2DD4BF) : const Color(0xFF38BDF8);
      _drawSoftGlow(canvas, Offset(gx, gy), isPreview ? 6 : 12, color, 0.32 * pulse);
      canvas.drawCircle(
        Offset(gx, gy),
        isPreview ? 1.2 : 2.1,
        Paint()..color = color.withAlpha((pulse * 220).round()),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 3. SICAK LATTE BOKEH
  // ---------------------------------------------------------------------------
  void _paintWarmLatteBokeh(Canvas canvas, Rect rect, Size size) {
    final t = progress;
    final tau = math.pi * 2;

    // Sıcak latte-kum gradient zemin (#FBF7F0 -> #F3E5D5), mavi ışıksız
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFFBF7F0),
          Color(0xFFF7EFE3),
          Color(0xFFF3E5D5),
        ],
        stops: <double>[0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // Yumuşak sıcak atmosfer parıltıları
    _drawSoftGlow(
      canvas,
      Offset(size.width * 0.82, size.height * 0.16),
      size.shortestSide * 0.65,
      const Color(0xFFFDE2B8),
      0.42,
    );
    _drawSoftGlow(
      canvas,
      Offset(size.width * 0.18, size.height * 0.85),
      size.shortestSide * 0.62,
      const Color(0xFFF6C89F),
      0.32,
    );

    // Aşağıdan yukarıya yavaşça yükselen kayısı, karamel ve bal tonlarında bokeh daireleri
    const bokehColors = <Color>[
      Color(0xFFFDBA74), // Kayısı
      Color(0xFFE09F5A), // Karamel
      Color(0xFFF5C16C), // Bal
      Color(0xFFFED7AA), // Sıcak krem-şeftali
    ];
    final count = isPreview ? 9 : 18;
    for (var i = 0; i < count; i++) {
      final speed = (i % 2) + 1;
      final yCycle = 1.0 - ((_hash(i * 17 + 5) + t * speed) % 1.0);
      final radius = size.shortestSide *
          ((isPreview ? 0.09 : 0.055) + _hash(i * 23 + 11) * (isPreview ? 0.11 : 0.09));
      final bx = _hash(i * 31 + 3) * size.width +
          math.sin(t * tau * 2 + i * 1.2) * size.width * 0.04;
      final by = -radius + yCycle * (size.height + radius * 2);
      final fade = math.sin(yCycle * math.pi).clamp(0.0, 1.0);
      final color = bokehColors[i % bokehColors.length];

      final paint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withAlpha((fade * 95).round()),
            color.withAlpha((fade * 52).round()),
            color.withAlpha(0),
          ],
          stops: const <double>[0.0, 0.62, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(bx, by), radius: radius));
      canvas.drawCircle(Offset(bx, by), radius, paint);

      // İnce bokeh dış halesi
      canvas.drawCircle(
        Offset(bx, by),
        radius * 0.76,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPreview ? 0.7 : 1.1
          ..color = const Color(0xFFFFF8EC).withAlpha((fade * 90).round()),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 4. ADAÇAYI & GÜN IŞIĞI
  // ---------------------------------------------------------------------------
  void _paintSageSunlight(Canvas canvas, Rect rect, Size size) {
    final t = progress;
    final tau = math.pi * 2;

    // Fildişi-krem zemin (#F5F9F3 -> #FBF6EC)
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFF5F9F3),
          Color(0xFFF7F8F0),
          Color(0xFFFBF6EC),
        ],
        stops: <double>[0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // Sakinçe süzülen yumuşak adaçayı yeşili ve gün ışığı sis bulutları
    final clouds = <({double x, double y, double r, Color color, double alpha, double phase})>[
      (x: 0.22, y: 0.22, r: 0.62, color: const Color(0xFFA7CBA9), alpha: 0.34, phase: 0.0),
      (x: 0.78, y: 0.26, r: 0.58, color: const Color(0xFFFDE69B), alpha: 0.38, phase: 1.4),
      (x: 0.30, y: 0.76, r: 0.66, color: const Color(0xFF9AC2A0), alpha: 0.30, phase: 2.8),
      (x: 0.80, y: 0.78, r: 0.60, color: const Color(0xFFFBE3B0), alpha: 0.34, phase: 4.1),
      (x: 0.52, y: 0.50, r: 0.54, color: const Color(0xFFC5DEC5), alpha: 0.24, phase: 5.2),
    ];

    for (var i = 0; i < clouds.length; i++) {
      final c = clouds[i];
      final dx = math.sin(t * tau * 1 + c.phase) * size.width * 0.07;
      final dy = math.cos(t * tau * 1 + c.phase) * size.height * 0.05;
      _drawSoftGlow(
        canvas,
        Offset(size.width * c.x + dx, size.height * c.y + dy),
        size.shortestSide * c.r,
        c.color,
        c.alpha,
      );
    }

    // Sakinçe süzülüp hafifçe parlayan pastel ışık tanecikleri
    const moteColors = <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFFEF3C7),
      Color(0xFFD9F0DB),
      Color(0xFFFDE68A),
    ];
    final moteCount = isPreview ? 12 : 24;
    for (var i = 0; i < moteCount; i++) {
      final speed = (i % 2) + 1;
      final yCycle = 1.0 - ((_hash(i * 19 + 7) + t * speed) % 1.0);
      final mx = _hash(i * 29 + 3) * size.width +
          math.sin(t * tau * 2 + i * 1.1) * (isPreview ? 5 : 16);
      final my = yCycle * size.height;
      final shimmer = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * tau * 3 + i * 1.5));
      final edgeFade = math.sin(yCycle * math.pi).clamp(0.0, 1.0);
      final alpha = shimmer * edgeFade;
      final r = (isPreview ? 1.5 : 2.2) + _hash(i * 13 + 5) * (isPreview ? 1.6 : 2.6);
      final color = moteColors[i % moteColors.length];

      _drawSoftGlow(canvas, Offset(mx, my), r * 3.6, const Color(0xFFFDE68A), 0.28 * alpha);
      canvas.drawCircle(
        Offset(mx, my),
        r,
        Paint()..color = color.withAlpha((alpha * 225).round()),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 5. SAKURA BAHÇESİ (ÖZEL TEMA — BULANIKSIZ, KESKİN VEKTÖR)
  // ---------------------------------------------------------------------------
  void _paintSakuraGarden(Canvas canvas, Rect rect, Size size) {
    final t = progress;
    final tau = math.pi * 2;
    final w = size.width;
    final h = size.height;

    // 1. Keskin şeftali-pembe gökyüzü
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFFFFEBD9),
          Color(0xFFFFDFDD),
          Color(0xFFF9C7D4),
        ],
        stops: <double>[0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.68));
    canvas.drawRect(rect, skyPaint);

    // Yumuşak uzak pembe tepeler
    final hillPath = Path()
      ..moveTo(0, h * 0.52)
      ..quadraticBezierTo(w * 0.28, h * 0.45, w * 0.55, h * 0.51)
      ..quadraticBezierTo(w * 0.82, h * 0.46, w, h * 0.52)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hillPath, Paint()..color = const Color(0xFFE8B8C8));

    // 2. Sakin yansımalı dere
    final waterRect = Rect.fromLTWH(0, h * 0.54, w, h * 0.46);
    final waterPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFFFFE3D8),
          Color(0xFFF6C2CC),
          Color(0xFFB37B8C),
        ],
        stops: <double>[0.0, 0.45, 1.0],
      ).createShader(waterRect);
    canvas.drawRect(waterRect, waterPaint);

    // Kıyı gölgeleri
    final leftBank = Path()
      ..moveTo(0, h * 0.56)
      ..quadraticBezierTo(w * 0.34, h * 0.62, w * 0.36, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(leftBank, Paint()..color = const Color(0xFF533B46));

    final rightBank = Path()
      ..moveTo(w, h * 0.55)
      ..quadraticBezierTo(w * 0.72, h * 0.65, w * 0.68, h)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(rightBank, Paint()..color = const Color(0xFF5C3D49));

    // Sol kıyı bahçe taşları
    final stones = <({double x, double y, double rx, double ry, Color dark, Color light})>[
      (x: 0.09, y: 0.69, rx: 0.12, ry: 0.032, dark: const Color(0xFF7C626E), light: const Color(0xFF99828D)),
      (x: 0.21, y: 0.72, rx: 0.10, ry: 0.025, dark: const Color(0xFF6E5561), light: const Color(0xFF8C7581)),
      (x: 0.12, y: 0.80, rx: 0.15, ry: 0.035, dark: const Color(0xFF8A737E), light: const Color(0xFFA8949E)),
      (x: 0.24, y: 0.86, rx: 0.13, ry: 0.030, dark: const Color(0xFF735B66), light: const Color(0xFF917A85)),
      (x: 0.08, y: 0.90, rx: 0.14, ry: 0.034, dark: const Color(0xFF634C57), light: const Color(0xFF826C77)),
    ];
    for (final s in stones) {
      final cx = w * s.x;
      final cy = h * s.y;
      final rx = w * s.rx;
      final ry = h * s.ry;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 2), width: rx * 2, height: ry * 2),
        Paint()..color = s.dark,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx - 1, cy - 1), width: rx * 1.84, height: ry * 1.56),
        Paint()..color = s.light,
      );
    }

    // Dere yüzeyinde çok hafif su dalgacıkları
    final ripplePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = isPreview ? 1.0 : 1.5
      ..color = const Color(0x8CFFF4F0);
    final rippleCount = isPreview ? 4 : 6;
    for (var i = 0; i < rippleCount; i++) {
      final ry = h * (0.61 + i * 0.055);
      final rx = w * 0.44 + math.sin(t * tau * 3 + i * 1.4) * w * 0.025;
      final rw = w * (0.08 + (i % 3) * 0.04);
      canvas.drawLine(Offset(rx, ry), Offset(rx + rw, ry), ripplePaint);
    }

    // Sağ alt kıyı sakura çalıları
    final bushSway = math.sin(t * tau * 2) * w * 0.01;
    _drawSakuraCanopy(
      canvas,
      Offset(w * 0.84 + bushSway, h * 0.83),
      w * 0.11,
      const Color(0xFFDF8AA3),
      const Color(0xFFF5B5C8),
      const Color(0xFF9D536B),
    );
    _drawSakuraCanopy(
      canvas,
      Offset(w * 0.95 - bushSway * 0.8, h * 0.73),
      w * 0.10,
      const Color(0xFFE79CB3),
      const Color(0xFFFAD0DE),
      const Color(0xFFA65C74),
    );

    // 3. YUKARI TAŞINMIŞ sol sakura dalı ve sağ dal (rüzgarda hafif esner)
    final leftSway = math.sin(t * tau * 2) * w * 0.014;
    final rightSway = math.cos(t * tau * 2) * w * 0.013;

    final branchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF5B2D3C);

    // Sol ana dal (daha yukarıdan uzanıyor)
    branchPaint.strokeWidth = isPreview ? 3.2 : 7.5;
    final leftMainBranch = Path()
      ..moveTo(-6, h * 0.28)
      ..quadraticBezierTo(w * 0.18, h * 0.23, w * 0.40 + leftSway, h * 0.16);
    canvas.drawPath(leftMainBranch, branchPaint);

    // Sol üst yan dal
    branchPaint.strokeWidth = isPreview ? 2.1 : 4.8;
    final leftSubBranch = Path()
      ..moveTo(w * 0.10, h * 0.24)
      ..quadraticBezierTo(w * 0.22, h * 0.14, w * 0.30 + leftSway, h * 0.09);
    canvas.drawPath(leftSubBranch, branchPaint);

    // Sağ ana dal
    branchPaint.strokeWidth = isPreview ? 2.8 : 6.5;
    final rightMainBranch = Path()
      ..moveTo(w + 6, h * 0.31)
      ..quadraticBezierTo(w * 0.82, h * 0.24, w * 0.68 + rightSway, h * 0.16);
    canvas.drawPath(rightMainBranch, branchPaint);

    // 4. Sol Sakura Ağacı Bulutsu Taçları
    _drawSakuraCanopy(
      canvas,
      Offset(w * 0.07 + leftSway * 0.85, h * 0.15),
      w * 0.15,
      const Color(0xFFE788A5),
      const Color(0xFFF9BECF),
      const Color(0xFFB55776),
    );
    _drawSakuraCanopy(
      canvas,
      Offset(w * 0.26 + leftSway, h * 0.19),
      w * 0.13,
      const Color(0xFFEE9AB4),
      const Color(0xFFFFD0DF),
      const Color(0xFFBC607E),
    );
    _drawSakuraCanopy(
      canvas,
      Offset(w * 0.41 + leftSway * 1.15, h * 0.25),
      w * 0.095,
      const Color(0xFFF2A9BF),
      const Color(0xFFFFDCE7),
      const Color(0xFFC46C88),
    );

    // 5. Sağ Sakura Ağacı Bulutsu Taçları
    _drawSakuraCanopy(
      canvas,
      Offset(w * 0.96 + rightSway * 0.8, h * 0.13),
      w * 0.15,
      const Color(0xFFF2A3BA),
      const Color(0xFFFFD9E5),
      const Color(0xFFC26784),
    );
    _drawSakuraCanopy(
      canvas,
      Offset(w * 0.79 + rightSway, h * 0.19),
      w * 0.12,
      const Color(0xFFF6B4C8),
      const Color(0xFFFFE4EC),
      const Color(0xFFCB7792),
    );

    // Preview modunda köşe bulutlarını da göster
    if (isPreview) {
      _drawSakuraCanopy(
        canvas,
        Offset(w * 0.05 + leftSway * 0.8, h * 0.325),
        w * 0.10,
        const Color(0xFFE68BA7),
        const Color(0xFFFAC6D6),
        const Color(0xFFB25876),
      );
      _drawSakuraCanopy(
        canvas,
        Offset(w * 0.95 + rightSway * 0.85, h * 0.325),
        w * 0.10,
        const Color(0xFFEC96B0),
        const Color(0xFFFCCAD9),
        const Color(0xFFB95E7C),
      );
    }

    // 6. Yavaşça süzülen keskin sakura yaprakları
    final petalCount = isPreview ? 8 : (isEcoMode ? 7 : 14);
    for (var i = 0; i < petalCount; i++) {
      if (!isPreview && i % 4 == 0) continue; // Ön plan katmanında çizilir
      _drawSakuraPetal(canvas, size, i, t);
    }
  }

  static void _drawSakuraCanopy(
    Canvas canvas,
    Offset center,
    double r,
    Color baseColor,
    Color lightColor,
    Color shadowColor, {
    double opacity = 1.0,
  }) {
    const puffs = <(double, double, double)>[
      (0.0, 0.0, 1.0),
      (-0.58, 0.16, 0.72),
      (0.58, 0.14, 0.74),
      (-0.32, -0.42, 0.68),
      (0.34, -0.38, 0.66),
      (0.02, 0.36, 0.64),
    ];
    final alpha = (opacity * 255).round().clamp(0, 255);
    final shadowPaint = Paint()..color = shadowColor.withAlpha(alpha);
    final basePaint = Paint()..color = baseColor.withAlpha(alpha);
    final lightPaint = Paint()..color = lightColor.withAlpha(alpha);

    for (final (ox, oy, sr) in puffs) {
      canvas.drawCircle(
        Offset(center.dx + ox * r, center.dy + oy * r + r * 0.09),
        r * sr,
        shadowPaint,
      );
    }
    for (final (ox, oy, sr) in puffs) {
      canvas.drawCircle(
        Offset(center.dx + ox * r, center.dy + oy * r),
        r * sr,
        basePaint,
      );
    }
    for (var i = 0; i < 3; i++) {
      final (ox, oy, sr) = puffs[i];
      canvas.drawCircle(
        Offset(center.dx + ox * r - r * 0.08, center.dy + oy * r - r * 0.16),
        r * sr * 0.54,
        lightPaint,
      );
    }
  }

  static void _drawSakuraPetal(Canvas canvas, Size size, int i, double t) {
    final tau = math.pi * 2;
    final speedY = (i % 3) + 1;
    final speedX = (i % 2) + 1;
    final seedX = _staticHash(i * 37 + 5);
    final seedY = _staticHash(i * 53 + 11);
    final px = ((seedX + t * speedX * 0.5) % 1.0) * size.width +
        math.sin(t * tau * 3 + i * 0.85) * size.width * 0.04;
    final py = ((seedY + t * speedY) % 1.0) * size.height;
    final petalSize = 3.2 + (i % 3) * 1.4;
    final angle = i * 1.1 + (i.isEven ? 1 : -1) * t * tau * 2;
    final color = i % 3 == 0
        ? const Color(0xFFFFD7E3)
        : i % 3 == 1
            ? const Color(0xFFF7A1BB)
            : const Color(0xFFFFEAF0);

    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(angle);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: petalSize * 2,
        height: petalSize * 1.12,
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }

  static double _staticHash(int seed) {
    final x = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  // ---------------------------------------------------------------------------
  // YARDIMCILAR
  // ---------------------------------------------------------------------------
  void _drawSoftGlow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double opacity,
  ) {
    if (radius <= 0 || opacity <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          color.withAlpha((opacity * 255).round().clamp(0, 255)),
          color.withAlpha((opacity * 0.42 * 255).round().clamp(0, 255)),
          color.withAlpha(0),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  /// Deterministik [0, 1) pseudo-random üretici (her karede aynı kararlı konumlar).
  double _hash(int seed) {
    final x = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  // ---------------------------------------------------------------------------
  // 6. ALEVİ POWER (Özel Tema 2 — Zülfikar, Mandala, Galaksiler & Bulutlar)
  // ---------------------------------------------------------------------------
  void _paintAleviPower(Canvas canvas, Rect rect, Size size) {
    final t = progress;
    const tau = math.pi * 2;
    final w = size.width;
    final h = size.height;
    final baseDim = math.min(w, h);
    final unit = isPreview ? baseDim / 360.0 : (baseDim / 420.0).clamp(0.75, 1.45);
    const inkColor = Color(0xFF0B1021);

    // 1) Derin Gece Lacivert -> Mor Gökyüzü
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF12216B),
          Color(0xFF1D338F),
          Color(0xFF3B2884),
          Color(0xFF58228B),
        ],
        stops: <double>[0.0, 0.45, 0.78, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, skyPaint);

    // Uzak koyu bulut katmanları
    final backCloudPaint = Paint()..color = const Color(0x730D1648);
    canvas.drawCircle(Offset(w * 0.20, h * 0.22), w * 0.28, backCloudPaint);
    canvas.drawCircle(Offset(w * 0.80, h * 0.30), w * 0.32, backCloudPaint);
    canvas.drawCircle(Offset(w * 0.30, h * 0.76), w * 0.36, backCloudPaint);

    // 2) Yıldız noktaları (Eco modda daha az)
    final dotCount = isPreview ? 18 : (isEcoMode ? 24 : 52);
    final dotPaint = Paint();
    for (var i = 0; i < dotCount; i++) {
      final dx = _hash(i * 11 + 3) * w;
      final dy = _hash(i * 17 + 9) * h;
      final dr = (i % 3 == 0 ? 2.4 : 1.4) * unit;
      final twinkle = 0.45 + 0.55 * math.sin(t * tau * 2 + i * 0.7).abs();
      dotPaint.color = Colors.white.withAlpha((twinkle * 255).round().clamp(0, 255));
      canvas.drawCircle(Offset(dx, dy), dr, dotPaint);
    }

    // 3) 3 Adet Dönen Spiral Galaksi
    _drawAleviGalaxy(canvas, Offset(w * 0.80, h * 0.10), 54 * unit, 25 * unit, -0.25 + t * tau, unit);
    _drawAleviGalaxy(canvas, Offset(w * 0.18, h * 0.72), 52 * unit, 24 * unit, 0.35 - t * tau, unit);
    _drawAleviGalaxy(canvas, Offset(w * 0.80, h * 0.80), 46 * unit, 21 * unit, -0.35 + t * tau, unit);

    // 4) Merkezi Güneş Patlaması & Mandala
    final center = Offset(w * 0.50, h * 0.47);
    _drawAleviSunburstAndMandala(canvas, center, unit, t, tau, inkColor);

    // 5) Kenar Bulutları (dikişsiz süzülen)
    final driftA = math.sin(t * tau) * 6 * unit;
    final driftB = math.cos(t * tau) * 5 * unit;
    _drawAleviCloud(canvas, Offset(-6 * unit + driftA, h * 0.25), 0.92 * unit, false, inkColor);
    _drawAleviCloud(canvas, Offset(w + 10 * unit - driftA, h * 0.26), 0.88 * unit, true, inkColor);
    _drawAleviCloud(canvas, Offset(-16 * unit + driftB, h * 0.56), 0.84 * unit, false, inkColor);
    _drawAleviCloud(canvas, Offset(w + 8 * unit - driftB, h * 0.54), 0.92 * unit, true, inkColor);

    // 6) Alt Mor Bulutlar + Ön Beyaz Bulutlar
    final purpleCloudPaint = Paint()..color = const Color(0xFF4C1D95);
    canvas.drawCircle(Offset(w * 0.16, h - 55 * unit), 105 * unit, purpleCloudPaint);
    canvas.drawCircle(Offset(w * 0.84, h - 50 * unit), 115 * unit, purpleCloudPaint);
    _drawAleviCloud(canvas, Offset(w * 0.14 + driftA * 0.6, h - 18 * unit), 1.22 * unit, false, inkColor);
    _drawAleviCloud(canvas, Offset(w * 0.86 - driftA * 0.6, h - 14 * unit), 1.26 * unit, true, inkColor);

    // 7) Sarı Çizgi Film Yıldızları
    _drawAleviStar(canvas, Offset(w * 0.30, h * 0.06), 12 * unit, -0.15 + math.sin(t * tau) * 0.06, 1.0, inkColor);
    _drawAleviStar(canvas, Offset(w * 0.19, h * 0.12), 23 * unit, 0.18 + math.cos(t * tau) * 0.06, 1.0 + math.sin(t * tau * 2) * 0.04, inkColor);
    _drawAleviStar(canvas, Offset(w * 0.09, h * 0.36), 13 * unit, -0.2, 1.0, inkColor);
    _drawAleviStar(canvas, Offset(w * 0.90, h * 0.37), 18 * unit, 0.2, 1.0 + math.cos(t * tau * 2) * 0.05, inkColor);
    _drawAleviStar(canvas, Offset(w * 0.18, h * 0.87), 20 * unit, -0.15, 1.0 + math.sin(t * tau * 2) * 0.04, inkColor);

    // 8) Zülfikar Kılıcı (Hafifçe Süzülen & Parlayan)
    final swordFloat = math.sin(t * tau * 2) * 6 * unit;
    _drawAleviZulfikar(canvas, Offset(center.dx, center.dy + swordFloat), unit, t, inkColor);

    // 9) Kılıç Etrafındaki Parlayan 4 Köşeli Kıvılcımlar
    _drawAleviSparkle(canvas, Offset(w * 0.48, h * 0.24), 11 * unit, const Color(0xFFFEF08A), t * tau * 3, inkColor);
    _drawAleviSparkle(canvas, Offset(w * 0.56, h * 0.14), 8.5 * unit, const Color(0xFFFDE047), t * tau * 2 + 1.0, inkColor);
    _drawAleviSparkle(canvas, Offset(w * 0.41, h * 0.63), 10 * unit, const Color(0xFFF472B6), t * tau * 3 + 2.0, inkColor);
    _drawAleviSparkle(canvas, Offset(w * 0.65, h * 0.72), 9.5 * unit, const Color(0xFF38BDF8), t * tau * 2 + 3.0, inkColor);
    _drawAleviSparkle(canvas, Offset(w * 0.50, h * 0.76), 9.5 * unit, const Color(0xFFFDE047), t * tau * 3 + 4.0, inkColor);
  }

  static void _drawAleviGalaxy(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double angle,
    double unit,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final rect = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
    final corePaint = Paint()
      ..shader = const RadialGradient(
        colors: <Color>[
          Color(0xF2FFFAE6),
          Color(0xA6C4B5FD),
          Color(0x40818CF8),
          Color(0x006366F1),
        ],
        stops: <double>[0.0, 0.28, 0.65, 1.0],
      ).createShader(rect);
    canvas.drawOval(rect, corePaint);

    final armPaint = Paint()
      ..color = const Color(0x8CE0E7FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * unit
      ..strokeCap = StrokeCap.round;

    for (var arm = 0; arm < 2; arm++) {
      final path = Path();
      for (var step = 0; step <= 24; step++) {
        final a = step * 0.15;
        final rad = a * (rx * 0.26);
        final ang = a + arm * math.pi;
        final px = math.cos(ang) * rad;
        final py = math.sin(ang) * rad * (ry / rx);
        if (step == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(path, armPaint);
    }
    canvas.restore();
  }

  static void _drawAleviStar(
    Canvas canvas,
    Offset center,
    double outerR,
    double angle,
    double scalePulse,
    Color inkColor,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(scalePulse, scalePulse);

    final innerR = outerR * 0.48;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outerR : innerR;
      final a = (i * math.pi) / 5 - math.pi / 2;
      final px = math.cos(a) * r;
      final py = math.sin(a) * r;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();

    final rect = Rect.fromCircle(center: Offset.zero, radius: outerR);
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFFFEF08A), Color(0xFFF59E0B)],
      ).createShader(rect);
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = (outerR * 0.14).clamp(1.6, 3.2)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
    canvas.restore();
  }

  static void _drawAleviSparkle(
    Canvas canvas,
    Offset center,
    double size,
    Color color,
    double phase,
    Color inkColor,
  ) {
    final s = size * (0.75 + 0.35 * math.sin(phase));
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final path = Path()
      ..moveTo(0, -s)
      ..quadraticBezierTo(0, 0, s, 0)
      ..quadraticBezierTo(0, 0, 0, s)
      ..quadraticBezierTo(0, 0, -s, 0)
      ..quadraticBezierTo(0, 0, 0, -s)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.restore();
  }

  static void _drawAleviCloud(
    Canvas canvas,
    Offset pos,
    double scale,
    bool flip,
    Color inkColor,
  ) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(flip ? -scale : scale, scale);

    final path = Path()
      ..moveTo(-90, 28)
      ..cubicTo(-110, 28, -112, -5, -80, -10)
      ..cubicTo(-75, -42, -32, -50, -14, -26)
      ..cubicTo(6, -54, 52, -46, 58, -14)
      ..cubicTo(88, -14, 96, 20, 74, 28)
      ..close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFFF1F5F9), Color(0xFFCBD5E1), Color(0xFF94A3B8)],
        stops: <double>[0.0, 0.65, 1.0],
      ).createShader(const Rect.fromLTRB(-110, -50, 95, 30));
    canvas.drawPath(path, fillPaint);

    canvas.drawPath(
      path,
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  static void _drawAleviSunburstAndMandala(
    Canvas canvas,
    Offset center,
    double unit,
    double t,
    double tau,
    Color inkColor,
  ) {
    // 1) Dış sivri güneş patlaması
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * tau * 0.25);
    const spikes = 16;
    final burstPath = Path();
    for (var i = 0; i < spikes * 2; i++) {
      final isOuter = i.isEven;
      final r = (isOuter ? (172.0 + math.sin(t * tau * 2 + i) * 5.0) : 112.0) * unit;
      final a = (i * math.pi) / spikes;
      final px = math.cos(a) * r;
      final py = math.sin(a) * r;
      if (i == 0) {
        burstPath.moveTo(px, py);
      } else {
        burstPath.lineTo(px, py);
      }
    }
    burstPath.close();

    final burstRect = Rect.fromCircle(center: Offset.zero, radius: 178 * unit);
    canvas.drawPath(
      burstPath,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0xFFFEF9C3), Color(0xFFFDE047), Color(0xFFF97316)],
          stops: <double>[0.1, 0.55, 1.0],
        ).createShader(burstRect),
    );
    canvas.drawPath(
      burstPath,
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * unit
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // 2) İçeride ters yönde dönen mandala deseni
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-t * tau * 0.5);
    final mandalaPaint = Paint()
      ..color = const Color(0x8CB45309)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * unit;
    const petals = 12;
    for (var i = 0; i < petals; i++) {
      canvas.save();
      canvas.rotate((i * tau) / petals);
      final petal = Path()
        ..moveTo(0, -56 * unit)
        ..quadraticBezierTo(22 * unit, -92 * unit, 0, -122 * unit)
        ..quadraticBezierTo(-22 * unit, -92 * unit, 0, -56 * unit);
      canvas.drawPath(petal, mandalaPaint);
      canvas.drawCircle(Offset(0, -98 * unit), 8.5 * unit, mandalaPaint);
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, 78 * unit, mandalaPaint);
    canvas.restore();
  }

  static void _drawAleviZulfikar(
    Canvas canvas,
    Offset center,
    double unit,
    double t,
    Color inkColor,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(0.84 * unit, 0.84 * unit);

    // Çelik Namlu (kavisli çift uçlu Zülfikar formu)
    final bladePath = Path()
      ..moveTo(-28, 175)
      ..cubicTo(-38, 45, -24, -120, 62, -262)
      ..lineTo(72, -268)
      ..quadraticBezierTo(50, -195, 36, -162)
      ..lineTo(106, -208)
      ..quadraticBezierTo(75, -145, 58, -98)
      ..cubicTo(32, -20, 26, 75, 24, 175)
      ..close();

    final bladePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFE0F2FE),
          Color(0xFF7DD3FC),
          Color(0xFF60A5FA),
          Color(0xFF93C5FD),
        ],
        stops: <double>[0.0, 0.35, 0.75, 1.0],
      ).createShader(const Rect.fromLTRB(-40, -260, 106, 175));
    canvas.drawPath(bladePath, bladePaint);

    // Hareketli parlama bandı (namlu içinde)
    canvas.save();
    canvas.clipPath(bladePath);
    final glintY = 160.0 - ((t * 420.0) % 420.0);
    canvas.drawRect(
      Rect.fromLTWH(-60, glintY, 200, 28),
      Paint()..color = const Color(0x59FFFFFF),
    );
    canvas.restore();

    canvas.drawPath(
      bladePath,
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4
        ..strokeJoin = StrokeJoin.round,
    );

    // Namlu içi beyaz ışık çizgisi
    final ridgePath = Path()
      ..moveTo(-14, 160)
      ..cubicTo(-20, 35, -8, -105, 54, -225);
    canvas.drawPath(
      ridgePath,
      Paint()
        ..color = const Color(0xB8FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.8
        ..strokeCap = StrokeCap.round,
    );

    // Balçak (Kıvrımlı altın koruma siperi)
    final guardPath = Path()
      ..moveTo(-78, 180)
      ..cubicTo(-96, 152, -55, 134, -44, 156)
      ..cubicTo(-38, 170, -16, 176, 0, 162)
      ..cubicTo(18, 176, 46, 176, 68, 192)
      ..cubicTo(96, 212, 74, 244, 48, 224)
      ..cubicTo(36, 214, 48, 200, 56, 206)
      ..cubicTo(40, 196, 16, 200, 0, 200)
      ..cubicTo(-30, 200, -64, 202, -78, 180)
      ..close();

    final goldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFFFEF08A), Color(0xFFF59E0B), Color(0xFFD97706)],
        stops: <double>[0.0, 0.5, 1.0],
      ).createShader(const Rect.fromLTRB(-80, 140, 80, 350));

    canvas.drawPath(guardPath, goldPaint);
    canvas.drawPath(
      guardPath,
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeJoin = StrokeJoin.round,
    );

    // Balçak ortasındaki elmas motifi
    final diamond = Path()
      ..moveTo(0, 168)
      ..lineTo(10, 182)
      ..lineTo(0, 196)
      ..lineTo(-10, 182)
      ..close();
    canvas.drawPath(diamond, Paint()..color = const Color(0xFFFDE047));
    canvas.drawPath(
      diamond,
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );

    // Kabza ve kıvrımlı altın topuz
    final hiltPath = Path()
      ..moveTo(-16, 198)
      ..lineTo(16, 198)
      ..cubicTo(14, 250, 24, 290, 20, 326)
      ..cubicTo(16, 355, -24, 360, -34, 334)
      ..cubicTo(-42, 314, -22, 294, -8, 306)
      ..cubicTo(0, 312, -8, 325, -14, 320)
      ..cubicTo(-18, 290, -14, 245, -16, 198)
      ..close();
    canvas.drawPath(hiltPath, goldPaint);
    canvas.drawPath(
      hiltPath,
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeJoin = StrokeJoin.round,
    );

    // Kabza içi süsleme kıvrımları & hareket çizgileri
    final detailPaint = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final hiltSwirl = Path()
      ..moveTo(-8, 224)
      ..quadraticBezierTo(10, 238, -6, 260)
      ..quadraticBezierTo(10, 280, -4, 300);
    canvas.drawPath(hiltSwirl, detailPaint);

    canvas.drawLine(const Offset(-42, 232), const Offset(-40, 286), detailPaint);
    canvas.drawLine(const Offset(36, 236), const Offset(38, 288), detailPaint);
    canvas.drawLine(const Offset(-48, 30), const Offset(-42, 110), detailPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AnimatedThemePainter oldDelegate) {
    return oldDelegate.preset != preset ||
        oldDelegate.progress != progress ||
        oldDelegate.isPreview != isPreview ||
        oldDelegate.isEcoMode != isEcoMode;
  }
}

/// Sakura Bahçesi ön plan katmanı: Ana Menü'de yalnızca ağacın kendi bulutsu
/// pembe yaprak tacının alt uçlarını Browser ve Articles kartlarının üst
/// köşelerine doğal olarak hafifçe uzatır (tıklamayı hiç engellemez).
class SakuraForegroundCanopyPainter extends CustomPainter {
  const SakuraForegroundCanopyPainter({
    required this.progress,
    this.isEcoMode = false,
  });

  final double progress;
  final bool isEcoMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = progress;
    final tau = math.pi * 2;
    final w = size.width;
    final h = size.height;

    final leftSway = math.sin(t * tau * 2) * w * 0.014;
    final rightSway = math.cos(t * tau * 2) * w * 0.013;

    // Sol üst (Browser kart köşesine doğalca uzanan bulutsu yaprak tacı)
    AnimatedThemePainter._drawSakuraCanopy(
      canvas,
      Offset(w * 0.045 + leftSway * 0.8, h * 0.325),
      w * 0.10,
      const Color(0xFFE68BA7),
      const Color(0xFFFAC6D6),
      const Color(0xFFB25876),
      opacity: 0.90,
    );
    AnimatedThemePainter._drawSakuraCanopy(
      canvas,
      Offset(w * 0.15 + leftSway * 0.95, h * 0.34),
      w * 0.065,
      const Color(0xFFF0A4BC),
      const Color(0xFFFFD8E4),
      const Color(0xFFC26B87),
      opacity: 0.84,
    );

    // Sağ üst (Articles kart köşesine doğalca uzanan bulutsu yaprak tacı)
    AnimatedThemePainter._drawSakuraCanopy(
      canvas,
      Offset(w * 0.955 + rightSway * 0.85, h * 0.325),
      w * 0.10,
      const Color(0xFFEC96B0),
      const Color(0xFFFCCAD9),
      const Color(0xFFB95E7C),
      opacity: 0.90,
    );
    AnimatedThemePainter._drawSakuraCanopy(
      canvas,
      Offset(w * 0.85 + rightSway * 0.95, h * 0.34),
      w * 0.065,
      const Color(0xFFF4AFC4),
      const Color(0xFFFFE0EA),
      const Color(0xFFC7728D),
      opacity: 0.84,
    );

    // Kartların önünden süzülen 3-4 narin sakura yaprağı
    final petalCount = isEcoMode ? 7 : 14;
    for (var i = 0; i < petalCount; i += 4) {
      AnimatedThemePainter._drawSakuraPetal(canvas, size, i, t);
    }
  }

  @override
  bool shouldRepaint(covariant SakuraForegroundCanopyPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isEcoMode != isEcoMode;
  }
}
