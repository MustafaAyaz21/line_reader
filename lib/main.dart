import 'package:flutter/material.dart';

import 'core/localization/app_locale.dart';
import 'core/platform/process_text_channel.dart';
import 'core/theme/app_theme.dart';
import 'features/lookup_overlay/quick_lookup_overlay_app.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        listenable: _localeController,
        builder: (context, _) {
          return MaterialApp(
            title: 'Line Reader',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.system,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
