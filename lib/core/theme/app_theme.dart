import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_preset.dart';

/// Aktif temanın gradyan arka planı, yarı saydam çubuk/kart katmanları ve
/// yüksek kontrastlı makale okuma yüzeyi için renk/stil uzantısı.
@immutable
class AppThemeVisuals extends ThemeExtension<AppThemeVisuals> {
  const AppThemeVisuals({
    required this.preset,
    required this.appBarColor,
    required this.navBarColor,
    required this.dialogSurfaceColor,
    required this.readerPaperColor,
    required this.readerSurfaceColor,
    required this.readerTextColor,
    required this.readerSecondaryTextColor,
    required this.readerDividerColor,
    required this.readerAccentColor,
    required this.readerBrightness,
  });

  final AppThemePreset preset;
  final Color appBarColor;
  final Color navBarColor;
  final Color dialogSurfaceColor;
  final Color readerPaperColor;
  final Color readerSurfaceColor;
  final Color readerTextColor;
  final Color readerSecondaryTextColor;
  final Color readerDividerColor;
  final Color readerAccentColor;
  final Brightness readerBrightness;

  bool get hasBackdrop => preset.isGradientTheme;

  static AppThemeVisuals of(BuildContext context) {
    final ext = Theme.of(context).extension<AppThemeVisuals>();
    if (ext != null) return ext;
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    return AppThemeVisuals(
      preset: AppThemePreset.classic,
      appBarColor: cs.surface,
      navBarColor: cs.surface,
      dialogSurfaceColor: cs.surface,
      readerPaperColor: isDark
          ? const Color(0xFF14171D)
          : const Color(0xFFF7F0E2),
      readerSurfaceColor: isDark
          ? const Color(0xFF1E232C)
          : const Color(0xFFEDE3CE),
      readerTextColor: isDark
          ? const Color(0xFFE5E7EB)
          : const Color(0xFF2B231A),
      readerSecondaryTextColor: isDark
          ? const Color(0xFF9CA3AF)
          : const Color(0xFF6E6151),
      readerDividerColor: isDark
          ? const Color(0xFF2B313C)
          : const Color(0xFFDFD3BC),
      readerAccentColor: isDark
          ? const Color(0xFFFBBF24)
          : const Color(0xFFB45309),
      readerBrightness: cs.brightness,
    );
  }

  @override
  AppThemeVisuals copyWith({
    AppThemePreset? preset,
    Color? appBarColor,
    Color? navBarColor,
    Color? dialogSurfaceColor,
    Color? readerPaperColor,
    Color? readerSurfaceColor,
    Color? readerTextColor,
    Color? readerSecondaryTextColor,
    Color? readerDividerColor,
    Color? readerAccentColor,
    Brightness? readerBrightness,
  }) {
    return AppThemeVisuals(
      preset: preset ?? this.preset,
      appBarColor: appBarColor ?? this.appBarColor,
      navBarColor: navBarColor ?? this.navBarColor,
      dialogSurfaceColor: dialogSurfaceColor ?? this.dialogSurfaceColor,
      readerPaperColor: readerPaperColor ?? this.readerPaperColor,
      readerSurfaceColor: readerSurfaceColor ?? this.readerSurfaceColor,
      readerTextColor: readerTextColor ?? this.readerTextColor,
      readerSecondaryTextColor:
          readerSecondaryTextColor ?? this.readerSecondaryTextColor,
      readerDividerColor: readerDividerColor ?? this.readerDividerColor,
      readerAccentColor: readerAccentColor ?? this.readerAccentColor,
      readerBrightness: readerBrightness ?? this.readerBrightness,
    );
  }

  @override
  AppThemeVisuals lerp(ThemeExtension<AppThemeVisuals>? other, double t) {
    if (other is! AppThemeVisuals) return this;
    return AppThemeVisuals(
      preset: t < 0.5 ? preset : other.preset,
      appBarColor: Color.lerp(appBarColor, other.appBarColor, t) ?? appBarColor,
      navBarColor: Color.lerp(navBarColor, other.navBarColor, t) ?? navBarColor,
      dialogSurfaceColor:
          Color.lerp(dialogSurfaceColor, other.dialogSurfaceColor, t) ??
              dialogSurfaceColor,
      readerPaperColor:
          Color.lerp(readerPaperColor, other.readerPaperColor, t) ??
              readerPaperColor,
      readerSurfaceColor:
          Color.lerp(readerSurfaceColor, other.readerSurfaceColor, t) ??
              readerSurfaceColor,
      readerTextColor:
          Color.lerp(readerTextColor, other.readerTextColor, t) ??
              readerTextColor,
      readerSecondaryTextColor: Color.lerp(
            readerSecondaryTextColor,
            other.readerSecondaryTextColor,
            t,
          ) ??
          readerSecondaryTextColor,
      readerDividerColor:
          Color.lerp(readerDividerColor, other.readerDividerColor, t) ??
              readerDividerColor,
      readerAccentColor:
          Color.lerp(readerAccentColor, other.readerAccentColor, t) ??
              readerAccentColor,
      readerBrightness: t < 0.5 ? readerBrightness : other.readerBrightness,
    );
  }
}

/// Uygulama genelinde kullanılan Material 3 tema ve 4 özel kod-tabanlı gradyan
/// tema yapılandırması.
abstract final class AppTheme {
  static const Color _seedColor = Color(0xFF2B6CB0);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    return _buildClassicTheme(colorScheme);
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return _buildClassicTheme(colorScheme);
  }

  /// Seçili [AppThemePreset] için açık veya koyu [ThemeData] döndürür.
  static ThemeData forPreset(
    AppThemePreset preset, {
    Brightness classicBrightness = Brightness.light,
  }) {
    return switch (preset) {
      AppThemePreset.classic =>
        classicBrightness == Brightness.dark ? dark() : light(),
      AppThemePreset.pastelDawn => _pastelDawn(),
      AppThemePreset.nightDepth => _nightDepth(),
      AppThemePreset.softMist => _softMist(),
      AppThemePreset.electricCoral => _electricCoral(),
    };
  }

  static ThemeData _buildClassicTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final visuals = AppThemeVisuals(
      preset: AppThemePreset.classic,
      appBarColor: colorScheme.surface,
      navBarColor: colorScheme.surface,
      dialogSurfaceColor: colorScheme.surface,
      readerPaperColor: isDark
          ? const Color(0xFF14171D)
          : const Color(0xFFF7F0E2),
      readerSurfaceColor: isDark
          ? const Color(0xFF1E232C)
          : const Color(0xFFEDE3CE),
      readerTextColor: isDark
          ? const Color(0xFFE5E7EB)
          : const Color(0xFF2B231A),
      readerSecondaryTextColor: isDark
          ? const Color(0xFF9CA3AF)
          : const Color(0xFF6E6151),
      readerDividerColor: isDark
          ? const Color(0xFF2B313C)
          : const Color(0xFFDFD3BC),
      readerAccentColor: isDark
          ? const Color(0xFFFBBF24)
          : const Color(0xFFB45309),
      readerBrightness: colorScheme.brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: <ThemeExtension<dynamic>>[visuals],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }

  /// 1. Görsel — Pastel Şafak:
  /// Şeftali/mercankırmızı, krem-sarı, nane yeşili ve buz mavisi geçişleri.
  static ThemeData _pastelDawn() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFD66A5A),
      brightness: Brightness.light,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFFB8493C),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xE8FFE3DC),
      onPrimaryContainer: const Color(0xFF431610),
      secondary: const Color(0xFF1E7B6A),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xE8D8F6EB),
      onSecondaryContainer: const Color(0xFF0E3830),
      tertiary: const Color(0xFF4B6FA5),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xE8DCEEFF),
      onTertiaryContainer: const Color(0xFF122C4D),
      surface: const Color(0xFFFFF8F3),
      onSurface: const Color(0xFF1F2430),
      onSurfaceVariant: const Color(0xFF4D5565),
      surfaceContainerLowest: const Color(0xF7FFFFFF),
      surfaceContainerLow: const Color(0xDEFFFFFF),
      surfaceContainer: const Color(0xEAFFF8F4),
      surfaceContainerHigh: const Color(0xF2FFF2EC),
      surfaceContainerHighest: const Color(0xE8F3E8E2),
      outline: const Color(0xFF8C7B75),
      outlineVariant: const Color(0x5EB68D84),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.pastelDawn,
      appBarColor: Color(0x99FFF8F3),
      navBarColor: Color(0xD9FFF8F4),
      dialogSurfaceColor: Color(0xFAFFF9F6),
      readerPaperColor: Color(0xEAFFFDFA),
      readerSurfaceColor: Color(0xEBFFF0E8),
      readerTextColor: Color(0xFF1F2430),
      readerSecondaryTextColor: Color(0xFF565E6E),
      readerDividerColor: Color(0x52B68D84),
      readerAccentColor: Color(0xFFB8493C),
      readerBrightness: Brightness.light,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  /// 2. Görsel — Gece Derinliği:
  /// Koyu okyanus mavisi, derin lacivert ve alt kısımda koyu mürdüm/bordo geçişi.
  static ThemeData _nightDepth() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3E8AD6),
      brightness: Brightness.dark,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFF7AC4FF),
      onPrimary: const Color(0xFF06213A),
      primaryContainer: const Color(0xD412365E),
      onPrimaryContainer: const Color(0xFFE4F3FF),
      secondary: const Color(0xFFE89AC1),
      onSecondary: const Color(0xFF3E1028),
      secondaryContainer: const Color(0xD43F1838),
      onSecondaryContainer: const Color(0xFFFFE5F1),
      tertiary: const Color(0xFF9EB4FF),
      onTertiary: const Color(0xFF0E1D4D),
      tertiaryContainer: const Color(0xD41F2957),
      onTertiaryContainer: const Color(0xFFE5EBFF),
      surface: const Color(0xFF0E1832),
      onSurface: const Color(0xFFF2F5FC),
      onSurfaceVariant: const Color(0xFFB9C6DF),
      surfaceContainerLowest: const Color(0xEB0A1226),
      surfaceContainerLow: const Color(0xD4121E3B),
      surfaceContainer: const Color(0xDF172445),
      surfaceContainerHigh: const Color(0xEB1D2B50),
      surfaceContainerHighest: const Color(0xD925355E),
      outline: const Color(0xFF667AA4),
      outlineVariant: const Color(0x668499C4),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.nightDepth,
      appBarColor: Color(0x88091730),
      navBarColor: Color(0xD40C1732),
      dialogSurfaceColor: Color(0xFA121E3A),
      readerPaperColor: Color(0xE00D1730),
      readerSurfaceColor: Color(0xEB182546),
      readerTextColor: Color(0xFFEDF2FC),
      readerSecondaryTextColor: Color(0xFFB1C0DB),
      readerDividerColor: Color(0x5C8499C4),
      readerAccentColor: Color(0xFF7AC4FF),
      readerBrightness: Brightness.dark,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  /// 3. Görsel — Hafif Sis / Pastel:
  /// Krem-beyaz, yumuşak lavanta, nane yeşili ve açık mavi geçişi.
  static ThemeData _softMist() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5D5BC9),
      brightness: Brightness.light,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFF5352C4),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xE8EAE6FF),
      onPrimaryContainer: const Color(0xFF1D1B54),
      secondary: const Color(0xFF247A67),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xE8D8F5EA),
      onSecondaryContainer: const Color(0xFF0D382E),
      tertiary: const Color(0xFF3E6EA8),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xE8DCEBFF),
      onTertiaryContainer: const Color(0xFF112C4D),
      surface: const Color(0xFFFAF9F7),
      onSurface: const Color(0xFF1C2230),
      onSurfaceVariant: const Color(0xFF4D5668),
      surfaceContainerLowest: const Color(0xF7FFFFFF),
      surfaceContainerLow: const Color(0xE0FFFFFF),
      surfaceContainer: const Color(0xEAF5F5FA),
      surfaceContainerHigh: const Color(0xF2EFEFF8),
      surfaceContainerHighest: const Color(0xE8E6E9F4),
      outline: const Color(0xFF7C849B),
      outlineVariant: const Color(0x5E8C95B2),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.softMist,
      appBarColor: Color(0x9EFBFBF9),
      navBarColor: Color(0xDCFAF9FC),
      dialogSurfaceColor: Color(0xFAF9F9FC),
      readerPaperColor: Color(0xEDFFFFFF),
      readerSurfaceColor: Color(0xEDF1F2F8),
      readerTextColor: Color(0xFF1C2230),
      readerSecondaryTextColor: Color(0xFF525B6D),
      readerDividerColor: Color(0x528C95B2),
      readerAccentColor: Color(0xFF5352C4),
      readerBrightness: Brightness.light,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  /// 4. Görsel — Elektrik Mercan:
  /// Canlı elektrik mavisi ile sıcak mercan/kızıl geçişi + okunaklı koyu cam kartlar.
  static ThemeData _electricCoral() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF685B),
      brightness: Brightness.dark,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFFFF7A6B),
      onPrimary: const Color(0xFF2B0705),
      primaryContainer: const Color(0xD93E1938),
      onPrimaryContainer: const Color(0xFFFFE6E2),
      secondary: const Color(0xFF7D9EFF),
      onSecondary: const Color(0xFF07164A),
      secondaryContainer: const Color(0xD916276B),
      onSecondaryContainer: const Color(0xFFE7EEFF),
      tertiary: const Color(0xFFFFB28A),
      onTertiary: const Color(0xFF3A1604),
      tertiaryContainer: const Color(0xD94A2229),
      onTertiaryContainer: const Color(0xFFFFEAE0),
      surface: const Color(0xFF10173B),
      onSurface: const Color(0xFFF6F8FF),
      onSurfaceVariant: const Color(0xFFC8D1EE),
      surfaceContainerLowest: const Color(0xEB0B102B),
      surfaceContainerLow: const Color(0xD911183D),
      surfaceContainer: const Color(0xE3161E4A),
      surfaceContainerHigh: const Color(0xED1C265B),
      surfaceContainerHighest: const Color(0xDE25306E),
      outline: const Color(0xFF7282BE),
      outlineVariant: const Color(0x739AAAE8),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.electricCoral,
      appBarColor: Color(0x940E1538),
      navBarColor: Color(0xDB0E1538),
      dialogSurfaceColor: Color(0xFA131B42),
      readerPaperColor: Color(0xE80F1536),
      readerSurfaceColor: Color(0xF01A224F),
      readerTextColor: Color(0xFFF4F7FF),
      readerSecondaryTextColor: Color(0xFFC0CAEA),
      readerDividerColor: Color(0x669AAAE8),
      readerAccentColor: Color(0xFFFF7A6B),
      readerBrightness: Brightness.dark,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  static ThemeData _buildGradientTheme({
    required ColorScheme colorScheme,
    required AppThemeVisuals visuals,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: <ThemeExtension<dynamic>>[visuals],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: visuals.appBarColor,
        foregroundColor: colorScheme.onSurface,
        systemOverlayStyle: colorScheme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: visuals.navBarColor,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: visuals.dialogSurfaceColor,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: visuals.dialogSurfaceColor,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: visuals.dialogSurfaceColor,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.brightness == Brightness.dark
            ? const Color(0xFF1F2A4D)
            : const Color(0xFF232836),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }
}
