import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'animated_theme_painters.dart';
import 'app_theme.dart';
import 'app_theme_controller.dart';
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
      case AppThemePreset.amethystGalaxy:
      case AppThemePreset.oceanDepths:
      case AppThemePreset.warmLatteBokeh:
      case AppThemePreset.sageSunlight:
      case AppThemePreset.sakuraGarden:
      case AppThemePreset.aleviPower:
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

/// Herhangi bir ekranı seçili kod-tabanlı hareketsiz veya hareketli tema üzerine
/// yerleştirir. Varsayılan (Klasik) temada hiçbir ekstra katman çizmez.
class AppThemeBackdrop extends StatelessWidget {
  const AppThemeBackdrop({
    super.key,
    required this.child,
    this.presetOverride,
    this.showForegroundOverlay = false,
    this.transitionKey,
  });

  final Widget child;
  final AppThemePreset? presetOverride;

  /// Sakura Bahçesi gibi ön plan bulutsu yaprak örtüşmesi olan temalarda
  /// Ana Menü kartlarının üst köşelerine tıklamayı engellemeyen ön plan
  /// katmanını çizer.
  final bool showForegroundOverlay;

  /// Sekme değişimi gibi görsel geçişlerde hareketli arka planı kısa süre
  /// duraklatmak için kullanılır (ör. aktif sekme indeksi).
  final Object? transitionKey;

  @override
  Widget build(BuildContext context) {
    final visuals = AppThemeVisuals.of(context);
    final preset = presetOverride ?? visuals.preset;

    if (preset.isAnimatedTheme) {
      return _AnimatedThemeBackdropHost(
        preset: preset,
        showForegroundOverlay:
            showForegroundOverlay && preset == AppThemePreset.sakuraGarden,
        transitionKey: transitionKey,
        child: child,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (preset.isGradientTheme)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: _CachedStaticBackdrop(
                  cacheKey: preset,
                  paintStatic: (canvas, size) {
                    AppThemeMeshPainter(preset).paint(canvas, size);
                  },
                  fallbackPainter: AppThemeMeshPainter(preset),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

/// Statik gradyan veya hareketli temaların sabit arka plan katmanını
/// `(cacheKey, fiziksel boyut)` bazında tek seferlik `ui.Image` olarak
/// önbelleğe alır; GPU her karede 5-6 shader yerine tek bir hazır doku çizer.
class _CachedStaticBackdrop extends StatefulWidget {
  const _CachedStaticBackdrop({
    required this.cacheKey,
    required this.paintStatic,
    this.fallbackPainter,
    this.onCacheStateChanged,
  });

  final Object cacheKey;
  final void Function(Canvas canvas, Size size) paintStatic;
  final CustomPainter? fallbackPainter;
  final ValueChanged<bool>? onCacheStateChanged;

  @override
  State<_CachedStaticBackdrop> createState() => _CachedStaticBackdropState();
}

class _CachedStaticBackdropState extends State<_CachedStaticBackdrop> {
  ui.Image? _cachedImage;
  Object? _renderedKey;
  int _renderedPhysicalWidth = 0;
  int _renderedPhysicalHeight = 0;
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _cachedImage?.dispose();
    _cachedImage = null;
    super.dispose();
  }

  void _ensureRasterized(Size logicalSize, double dpr) {
    if (logicalSize.isEmpty || dpr <= 0) return;
    final pw = (logicalSize.width * dpr).round().clamp(1, 4096);
    final ph = (logicalSize.height * dpr).round().clamp(1, 4096);

    if (_renderedKey == widget.cacheKey &&
        _renderedPhysicalWidth == pw &&
        _renderedPhysicalHeight == ph) {
      return;
    }

    _renderedKey = widget.cacheKey;
    _renderedPhysicalWidth = pw;
    _renderedPhysicalHeight = ph;
    final myGen = ++_generation;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pw / logicalSize.width, ph / logicalSize.height);
    widget.paintStatic(canvas, logicalSize);
    final picture = recorder.endRecording();

    picture.toImage(pw, ph).then((image) {
      picture.dispose();
      if (!mounted || myGen != _generation) {
        image.dispose();
        return;
      }
      final prev = _cachedImage;
      setState(() {
        _cachedImage = image;
      });
      prev?.dispose();
      widget.onCacheStateChanged?.call(true);
    }).catchError((_) {
      picture.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isEmpty) {
          _ensureRasterized(size, dpr);
        }
        final img = _cachedImage;
        if (img != null) {
          return RawImage(
            image: img,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.low,
          );
        }
        if (widget.fallbackPainter != null) {
          return CustomPaint(
            isComplex: true,
            willChange: false,
            painter: widget.fallbackPainter,
          );
        }
        return const SizedBox.expand();
      },
    );
  }
}

/// Hareketli arka plan temalarını tek bir sakin `AnimationController` ile çizer.
/// Pencere küçültüldüğünde / arka plana alındığında veya kullanıcı "Animasyonu
/// Duraklat" anahtarını açtığında otomatik olarak duraklayıp CPU tüketimini
/// sıfıra indirir; "Pil Dostu Animasyon" modunda daha hafif döngü kullanır.
class _AnimatedThemeBackdropHost extends StatefulWidget {
  const _AnimatedThemeBackdropHost({
    required this.preset,
    required this.showForegroundOverlay,
    required this.transitionKey,
    required this.child,
  });

  final AppThemePreset preset;
  final bool showForegroundOverlay;
  final Object? transitionKey;
  final Widget child;

  @override
  State<_AnimatedThemeBackdropHost> createState() =>
      _AnimatedThemeBackdropHostState();
}

class _AnimatedThemeBackdropHostState extends State<_AnimatedThemeBackdropHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _normalCycle = Duration(seconds: 60);
  static const Duration _ecoCycle = Duration(seconds: 90);
  static const int _normalFrameIntervalMs = 42; // ~24 FPS (sakin, sıfır kasma)
  static const int _ecoFrameIntervalMs = 68; // ~15 FPS (pil dostu)

  late final AnimationController _controller;
  final ValueNotifier<double> _throttledProgress = ValueNotifier<double>(0.18);
  int _lastPaintMs = 0;

  bool _isAppVisible = true;
  bool _tickerEnabled = true;
  bool _isRouteTransitioning = false;
  bool _isScrolling = false;
  bool _isTabTransitioning = false;
  bool _hasCachedStaticBase = false;
  Timer? _scrollResumeTimer;
  Timer? _tabResumeTimer;
  Animation<double>? _routeAnim;
  Animation<double>? _secondaryRouteAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: AppThemeController.shared.isEcoAnimation
          ? _ecoCycle
          : _normalCycle,
      value: 0.18,
    )..addListener(_onTick);
    AppThemeController.shared.addListener(_syncPlayback);
  }

  void _onTick() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final interval = AppThemeController.shared.isEcoAnimation
        ? _ecoFrameIntervalMs
        : _normalFrameIntervalMs;
    if (nowMs - _lastPaintMs >= interval) {
      _lastPaintMs = nowMs;
      _throttledProgress.value = _controller.value;
    }
  }

  void _attachRouteAnimations(ModalRoute<dynamic>? route) {
    final nextPrimary = route?.animation;
    final nextSecondary = route?.secondaryAnimation;
    if (_routeAnim != nextPrimary) {
      _routeAnim?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnim = nextPrimary;
      _routeAnim?.addStatusListener(_onRouteAnimationStatus);
    }
    if (_secondaryRouteAnim != nextSecondary) {
      _secondaryRouteAnim?.removeStatusListener(_onRouteAnimationStatus);
      _secondaryRouteAnim = nextSecondary;
      _secondaryRouteAnim?.addStatusListener(_onRouteAnimationStatus);
    }
    _updateTransitionFlag();
  }

  void _onRouteAnimationStatus(AnimationStatus _) {
    _updateTransitionFlag();
    _syncPlayback();
  }

  void _updateTransitionFlag() {
    final primaryAnimating = _routeAnim != null &&
        (_routeAnim!.status == AnimationStatus.forward ||
            _routeAnim!.status == AnimationStatus.reverse);
    final secondaryAnimating = _secondaryRouteAnim != null &&
        (_secondaryRouteAnim!.status == AnimationStatus.forward ||
            _secondaryRouteAnim!.status == AnimationStatus.reverse);
    _isRouteTransitioning = primaryAnimating || secondaryAnimating;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    _attachRouteAnimations(ModalRoute.of(context));
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant _AnimatedThemeBackdropHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preset != widget.preset) {
      _hasCachedStaticBase = false;
    }
    if (oldWidget.transitionKey != widget.transitionKey) {
      _pauseBrieflyForTabSwitch();
    }
    _syncPlayback();
  }

  void _pauseBrieflyForTabSwitch() {
    _tabResumeTimer?.cancel();
    _isTabTransitioning = true;
    _tabResumeTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _isTabTransitioning = false;
      _syncPlayback();
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      if (!_isScrolling) {
        _isScrolling = true;
        _syncPlayback();
      }
      _scrollResumeTimer?.cancel();
      _scrollResumeTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        _isScrolling = false;
        _syncPlayback();
      });
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (_isAppVisible != visible) {
      _isAppVisible = visible;
      _syncPlayback();
    }
  }

  void _syncPlayback() {
    if (!mounted) return;
    final desiredDuration = AppThemeController.shared.isEcoAnimation
        ? _ecoCycle
        : _normalCycle;
    if (_controller.duration != desiredDuration) {
      _controller.duration = desiredDuration;
      if (_controller.isAnimating) {
        _controller.repeat();
      }
    }

    final shouldRun = _isAppVisible &&
        _tickerEnabled &&
        !_isRouteTransitioning &&
        !_isScrolling &&
        !_isTabTransitioning &&
        !AppThemeController.shared.isAnimationPaused;
    if (shouldRun) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop(canceled: false);
      }
    }
  }

  @override
  void dispose() {
    _scrollResumeTimer?.cancel();
    _tabResumeTimer?.cancel();
    _routeAnim?.removeStatusListener(_onRouteAnimationStatus);
    _secondaryRouteAnim?.removeStatusListener(_onRouteAnimationStatus);
    AppThemeController.shared.removeListener(_syncPlayback);
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onTick);
    _controller.dispose();
    _throttledProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEco = AppThemeController.shared.isEcoAnimation;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: _CachedStaticBackdrop(
                cacheKey: widget.preset,
                paintStatic: (canvas, size) {
                  AnimatedThemePainter.paintStaticBase(
                    widget.preset,
                    canvas,
                    size,
                  );
                },
                onCacheStateChanged: (ready) {
                  if (mounted && _hasCachedStaticBase != ready) {
                    setState(() {
                      _hasCachedStaticBase = ready;
                    });
                  }
                },
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ValueListenableBuilder<double>(
                valueListenable: _throttledProgress,
                builder: (context, progress, _) {
                  return CustomPaint(
                    painter: AnimatedThemePainter(
                      preset: widget.preset,
                      progress: progress,
                      isEcoMode: isEco,
                      skipStaticBackground: _hasCachedStaticBase,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: widget.child,
        ),
        if (widget.showForegroundOverlay)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: _throttledProgress,
                  builder: (context, progress, _) {
                    return CustomPaint(
                      painter: SakuraForegroundCanopyPainter(
                        progress: progress,
                        isEcoMode: isEco,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
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
        child: preset.isAnimatedTheme
            ? CustomPaint(
                painter: AnimatedThemePainter(
                  preset: preset,
                  progress: 0.22,
                  isPreview: true,
                ),
                child: child ?? const SizedBox.expand(),
              )
            : preset.isGradientTheme
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
