import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'core/localization/app_locale.dart';
import 'core/platform/process_text_channel.dart';
import 'core/platform/web_back_bridge.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'features/home/home_screen.dart';
import 'features/lookup_overlay/quick_lookup_overlay_app.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    // Düşük ve orta segment telefonlarda bellek şişmesini ve takılmayı önleyen RAM tavanı
    PaintingBinding.instance.imageCache.maximumSize = 100;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 40 << 20; // 40 MB
  }
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
    WebBackBridge.shared.ensureInitialized();
  }
  ProcessTextChannel.ensureInitialized();
  runApp(const LineReaderApp());
}

/// Android'de başka bir uygulamada kelime seçilip "Line'da Bak" seçildiğinde
/// `ProcessTextOverlayActivity` tarafından şeffaf mini kart olarak başlatılan
/// hafif giriş noktası.
@pragma('vm:entry-point')
void processTextOverlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuickLookupOverlayApp());
}

class LineReaderApp extends StatefulWidget {
  const LineReaderApp({super.key});

  @override
  State<LineReaderApp> createState() => _LineReaderAppState();
}

class _LineReaderAppState extends State<LineReaderApp> {
  late final AppLocaleController _localeController;

  @override
  void initState() {
    super.initState();
    _localeController = AppLocaleController()..load();
    AppThemeController.shared.load();
  }

  @override
  void dispose() {
    _localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLocaleScope(
      controller: _localeController,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          _localeController,
          AppThemeController.shared,
        ]),
        builder: (context, _) {
          final preset = AppThemeController.shared.preset;
          return MaterialApp(
            title: 'Line Reader',
            debugShowCheckedModeBanner: false,
            navigatorObservers: kIsWeb
                ? <NavigatorObserver>[WebBackBridge.shared.navigatorObserver]
                : const <NavigatorObserver>[],
            theme: AppTheme.forPreset(
              preset,
              classicBrightness: Brightness.light,
            ),
            darkTheme: AppTheme.forPreset(
              preset,
              classicBrightness: Brightness.dark,
            ),
            themeMode: preset.themeMode,
            themeAnimationDuration: Duration.zero,
            home: kIsWeb ? const HomeScreen() : const SplashScreen(),
          );
        },
      ),
    );
  }
}
