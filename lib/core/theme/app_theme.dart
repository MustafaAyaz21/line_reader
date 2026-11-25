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
      AppThemePreset.amethystGalaxy => _amethystGalaxy(),
      AppThemePreset.oceanDepths => _oceanDepths(),
      AppThemePreset.warmLatteBokeh => _warmLatteBokeh(),
      AppThemePreset.sageSunlight => _sageSunlight(),
      AppThemePreset.sakuraGarden => _sakuraGarden(),
      AppThemePreset.aleviPower => _aleviPower(),
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

  /// Hareketli 1 — Ametist Galaksi:
  /// Koyu mor-gece uzay zemini üzerinde yarı saydam koyu buzlu cam yüzeyler,
  /// net açık renkli yazılar ve ametist mor / gül-mercan vurgular.
  static ThemeData _amethystGalaxy() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFA855F7),
      brightness: Brightness.dark,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFFC084FC),
      onPrimary: const Color(0xFF1A072E),
      primaryContainer: const Color(0xD93B1760),
      onPrimaryContainer: const Color(0xFFF3E8FF),
      secondary: const Color(0xFFF48FB1),
      onSecondary: const Color(0xFF33081C),
      secondaryContainer: const Color(0xD94C1838),
      onSecondaryContainer: const Color(0xFFFFE4F0),
      tertiary: const Color(0xFF93C5FD),
      onTertiary: const Color(0xFF0A1F40),
      tertiaryContainer: const Color(0xD91E2952),
      onTertiaryContainer: const Color(0xFFE5F0FF),
      surface: const Color(0xFF0E081C),
      onSurface: const Color(0xFFF5F0FF),
      onSurfaceVariant: const Color(0xFFC9BFE6),
      surfaceContainerLowest: const Color(0xED0B0617),
      surfaceContainerLow: const Color(0xDB150D2B),
      surfaceContainer: const Color(0xE31B1236),
      surfaceContainerHigh: const Color(0xED241845),
      surfaceContainerHighest: const Color(0xDE2D1F54),
      outline: const Color(0xFF836EA8),
      outlineVariant: const Color(0x6BA68CE0),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.amethystGalaxy,
      appBarColor: Color(0xA6100921),
      navBarColor: Color(0xE0110A24),
      dialogSurfaceColor: Color(0xFA170E2E),
      readerPaperColor: Color(0xE6110A22),
      readerSurfaceColor: Color(0xED1D1338),
      readerTextColor: Color(0xFFF3EEFF),
      readerSecondaryTextColor: Color(0xFFC4B8E3),
      readerDividerColor: Color(0x61A68CE0),
      readerAccentColor: Color(0xFFC084FC),
      readerBrightness: Brightness.dark,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  /// Hareketli 2 — Okyanus Derinlikleri:
  /// Derin petrol-lacivert sualtı zemini üzerinde yarı saydam koyu deniz camı
  /// yüzeyler, net açık yazılar ve biyolüminesans turkuaz vurgular.
  static ThemeData _oceanDepths() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF14B8A6),
      brightness: Brightness.dark,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFF42D9D9),
      onPrimary: const Color(0xFF032329),
      primaryContainer: const Color(0xD90B3D47),
      onPrimaryContainer: const Color(0xFFE0FCFC),
      secondary: const Color(0xFF6FEBC9),
      onSecondary: const Color(0xFF042B22),
      secondaryContainer: const Color(0xD90D3E36),
      onSecondaryContainer: const Color(0xFFE0FFF5),
      tertiary: const Color(0xFF7DD3FC),
      onTertiary: const Color(0xFF06253A),
      tertiaryContainer: const Color(0xD910334D),
      onTertiaryContainer: const Color(0xFFE3F5FF),
      surface: const Color(0xFF06151D),
      onSurface: const Color(0xFFECF8FA),
      onSurfaceVariant: const Color(0xFFA9CFD8),
      surfaceContainerLowest: const Color(0xED041017),
      surfaceContainerLow: const Color(0xDB091E29),
      surfaceContainer: const Color(0xE30E2734),
      surfaceContainerHigh: const Color(0xED133140),
      surfaceContainerHighest: const Color(0xDE1A3D4F),
      outline: const Color(0xFF568A99),
      outlineVariant: const Color(0x666CC4D4),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.oceanDepths,
      appBarColor: Color(0xA606161F),
      navBarColor: Color(0xE0071822),
      dialogSurfaceColor: Color(0xFA0A202B),
      readerPaperColor: Color(0xE6071720),
      readerSurfaceColor: Color(0xED0E2633),
      readerTextColor: Color(0xFFEAF7FA),
      readerSecondaryTextColor: Color(0xFFA3CAD4),
      readerDividerColor: Color(0x5E6CC4D4),
      readerAccentColor: Color(0xFF42D9D9),
      readerBrightness: Brightness.dark,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  /// Hareketli 3 — Sıcak Latte Bokeh:
  /// Mavi ışıksız sıcak latte-kum zemini üzerinde krem buzlu cam yüzeyler,
  /// yüksek kontrastlı koyu kömür yazılar (#292524 / #57534E) ve kehribar vurgular.
  static ThemeData _warmLatteBokeh() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB45309),
      brightness: Brightness.light,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFFA84D0C),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xEBFFE7CE),
      onPrimaryContainer: const Color(0xFF3E1A04),
      secondary: const Color(0xFF8C5319),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xEBF7E5CC),
      onSecondaryContainer: const Color(0xFF351D06),
      tertiary: const Color(0xFF7C4D3A),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xEBF5E2DA),
      onTertiaryContainer: const Color(0xFF331B12),
      surface: const Color(0xFFFBF7F0),
      onSurface: const Color(0xFF292524),
      onSurfaceVariant: const Color(0xFF57534E),
      surfaceContainerLowest: const Color(0xF7FFFFFF),
      surfaceContainerLow: const Color(0xE8FFFDF9),
      surfaceContainer: const Color(0xEEFAF2E7),
      surfaceContainerHigh: const Color(0xF2F5E9DA),
      surfaceContainerHighest: const Color(0xEBECE0D0),
      outline: const Color(0xFF8C7B6B),
      outlineVariant: const Color(0x66B59C84),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.warmLatteBokeh,
      appBarColor: Color(0xB8FBF7F0),
      navBarColor: Color(0xE3FAF3E8),
      dialogSurfaceColor: Color(0xFAFCF8F2),
      readerPaperColor: Color(0xEEFFFDF8),
      readerSurfaceColor: Color(0xEEF5EADA),
      readerTextColor: Color(0xFF292524),
      readerSecondaryTextColor: Color(0xFF57534E),
      readerDividerColor: Color(0x5EB59C84),
      readerAccentColor: Color(0xFFA84D0C),
      readerBrightness: Brightness.light,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  /// Hareketli 4 — Adaçayı & Gün Işığı:
  /// Fildişi-krem zemini üzerinde ferah adaçayı cam yüzeyler, yüksek kontrastlı
  /// koyu kömür yazılar (#292524 / #57534E) ve doğal adaçayı yeşili vurgular.
  static ThemeData _sageSunlight() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B6E4C),
      brightness: Brightness.light,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFF356A48),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xEBDCF0E1),
      onPrimaryContainer: const Color(0xFF102E1B),
      secondary: const Color(0xFF8A6118),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xEBF8ECCB),
      onSecondaryContainer: const Color(0xFF332204),
      tertiary: const Color(0xFF4A6B62),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xEBDCECE8),
      onTertiaryContainer: const Color(0xFF132C26),
      surface: const Color(0xFFF5F9F3),
      onSurface: const Color(0xFF292524),
      onSurfaceVariant: const Color(0xFF57534E),
      surfaceContainerLowest: const Color(0xF7FFFFFF),
      surfaceContainerLow: const Color(0xE8FCFEFA),
      surfaceContainer: const Color(0xEEF2F7EF),
      surfaceContainerHigh: const Color(0xF2EBF2E7),
      surfaceContainerHighest: const Color(0xEBE3ECDF),
      outline: const Color(0xFF728273),
      outlineVariant: const Color(0x6692A894),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.sageSunlight,
      appBarColor: Color(0xB8F5F9F3),
      navBarColor: Color(0xE3F2F7EE),
      dialogSurfaceColor: Color(0xFAF8FBF6),
      readerPaperColor: Color(0xEEFCFDFB),
      readerSurfaceColor: Color(0xEEECF3E8),
      readerTextColor: Color(0xFF292524),
      readerSecondaryTextColor: Color(0xFF57534E),
      readerDividerColor: Color(0x5E92A894),
      readerAccentColor: Color(0xFF356A48),
      readerBrightness: Brightness.light,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  /// Özel Tema 1 — Sakura Bahçesi:
  /// Keskin, bulanıksız şeftali-pembe kiraz çiçekleri ve dere atmosferi;
  /// koyu erik-kahve (#361923) yüksek kontrastlı yazılar ve gül-krem yüzeyler.
  static ThemeData _sakuraGarden() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB84A6E),
      brightness: Brightness.light,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFFA83B60),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xEBFFE0EA),
      onPrimaryContainer: const Color(0xFF3A1220),
      secondary: const Color(0xFF56343F),
      onSecondary: const Color(0xFFFFF7F9),
      secondaryContainer: const Color(0xEBF7DCE5),
      onSecondaryContainer: const Color(0xFF361923),
      tertiary: const Color(0xFF8C4A5E),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xEBFFE8EC),
      onTertiaryContainer: const Color(0xFF3A1822),
      surface: const Color(0xFFFFF5F7),
      onSurface: const Color(0xFF361923),
      onSurfaceVariant: const Color(0xFF694552),
      surfaceContainerLowest: const Color(0xF7FFFFFF),
      surfaceContainerLow: const Color(0xE0FFF7F9),
      surfaceContainer: const Color(0xEBFFF0F4),
      surfaceContainerHigh: const Color(0xF0FCE7EE),
      surfaceContainerHighest: const Color(0xEBF5DCE5),
      outline: const Color(0xFF9C6D7D),
      outlineVariant: const Color(0x66C76282),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.sakuraGarden,
      appBarColor: Color(0xB8FFF3F6),
      navBarColor: Color(0xE6FFF4F7),
      dialogSurfaceColor: Color(0xFAFFF8FA),
      readerPaperColor: Color(0xF0FFF9FA),
      readerSurfaceColor: Color(0xEEFAE8EE),
      readerTextColor: Color(0xFF361923),
      readerSecondaryTextColor: Color(0xFF694552),
      readerDividerColor: Color(0x5EC76282),
      readerAccentColor: Color(0xFFA83B60),
      readerBrightness: Brightness.light,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  /// Özel Tema 2 — Alevi Power:
  /// Kozmik lacivert-mor gökyüzü, dönen galaksiler, güneş patlaması ve Zülfikar
  /// üzerinde yüksek okunaklılık sağlayan koyu indigo yüzeyler ve sıcak altın vurgular.
  static ThemeData _aleviPower() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFF59E0B),
      brightness: Brightness.dark,
    );
    final colorScheme = base.copyWith(
      primary: const Color(0xFFFBBF24),
      onPrimary: const Color(0xFF12183A),
      primaryContainer: const Color(0xD93B2778),
      onPrimaryContainer: const Color(0xFFFEF08A),
      secondary: const Color(0xFF7DD3FC),
      onSecondary: const Color(0xFF0A1432),
      secondaryContainer: const Color(0xD91A2B66),
      onSecondaryContainer: const Color(0xFFE0F2FE),
      tertiary: const Color(0xFFFDE047),
      onTertiary: const Color(0xFF141B3F),
      tertiaryContainer: const Color(0xD94C1D95),
      onTertiaryContainer: const Color(0xFFFEF9C3),
      surface: const Color(0xFF0E1538),
      onSurface: const Color(0xFFF8FAFC),
      onSurfaceVariant: const Color(0xFFCBD5E1),
      surfaceContainerLowest: const Color(0xE60A102B),
      surfaceContainerLow: const Color(0xD910183D),
      surfaceContainer: const Color(0xDF141E4B),
      surfaceContainerHigh: const Color(0xE61A265C),
      surfaceContainerHighest: const Color(0xEB22306E),
      outline: const Color(0xFF64748B),
      outlineVariant: const Color(0x5CFBBF24),
    );

    const visuals = AppThemeVisuals(
      preset: AppThemePreset.aleviPower,
      appBarColor: Color(0xCC0E1538),
      navBarColor: Color(0xEB0C1232),
      dialogSurfaceColor: Color(0xF5121A44),
      readerPaperColor: Color(0xEB0E1538),
      readerSurfaceColor: Color(0xEB182356),
      readerTextColor: Color(0xFFF8FAFC),
      readerSecondaryTextColor: Color(0xFFCBD5E1),
      readerDividerColor: Color(0x52FBBF24),
      readerAccentColor: Color(0xFFFBBF24),
      readerBrightness: Brightness.dark,
    );

    return _buildGradientTheme(colorScheme: colorScheme, visuals: visuals);
  }

  static ThemeData _buildGradientTheme({
    required ColorScheme colorScheme,
    required AppThemeVisuals visuals,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
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
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide(color: colorScheme.outlineVariant),
        labelStyle: TextStyle(color: colorScheme.onSurface),
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
        backgroundColor: isDark
            ? const Color(0xFF1F2A4D)
            : const Color(0xFF292524),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }
}
