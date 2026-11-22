import 'package:flutter/material.dart';

import 'core/localization/app_locale.dart';
import 'core/platform/process_text_channel.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ProcessTextChannel.ensureInitialized();
  runApp(const LineReaderApp());
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
