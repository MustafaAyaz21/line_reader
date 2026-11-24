import 'package:flutter/material.dart';

/// Uygulama genelinde seçilebilen kod tabanlı, kalite kayıpsız tema ön ayarları.
enum AppThemePreset {
  classic(
    storageKey: 'classic',
    trTitle: 'Varsayılan',
    enTitle: 'Classic',
    trSubtitle: 'Sistem açık / koyu görünümü',
    enSubtitle: 'Follows system light / dark mode',
  ),
  pastelDawn(
    storageKey: 'pastel_dawn',
    trTitle: 'Pastel Şafak',
    enTitle: 'Pastel Dawn',
    trSubtitle: 'Şeftali, krem-sarı, nane ve buz mavisi',
    enSubtitle: 'Peach, cream yellow, mint & ice blue',
  ),
  nightDepth(
    storageKey: 'night_depth',
    trTitle: 'Gece Derinliği',
    enTitle: 'Night Depth',
    trSubtitle: 'Koyu okyanus, lacivert ve mürdüm-bordo',
    enSubtitle: 'Deep ocean, midnight navy & dark plum',
  ),
  softMist(
    storageKey: 'soft_mist',
    trTitle: 'Hafif Sis',
    enTitle: 'Soft Mist',
    trSubtitle: 'Krem-beyaz, lavanta, nane ve açık mavi',
    enSubtitle: 'Cream white, lavender, mint & soft blue',
  ),
  electricCoral(
    storageKey: 'electric_coral',
    trTitle: 'Elektrik Mercan',
    enTitle: 'Electric Coral',
    trSubtitle: 'Canlı elektrik mavisi ve sıcak mercan',
    enSubtitle: 'Vivid electric blue & warm coral glow',
  ),
  amethystGalaxy(
    storageKey: 'amethyst_galaxy',
    trTitle: 'Ametist Galaksi',
    enTitle: 'Amethyst Galaxy',
    trSubtitle: 'Dönen mor galaksi ve pulsar',
    enSubtitle: 'Swirling violet galaxy & pulsar',
    isAnimated: true,
  ),
  oceanDepths(
    storageKey: 'ocean_depths',
    trTitle: 'Okyanus Derinlikleri',
    enTitle: 'Ocean Depths',
    trSubtitle: 'Sakin derin deniz ve balıklar',
    enSubtitle: 'Calm deep sea & fish',
    isAnimated: true,
  ),
  warmLatteBokeh(
    storageKey: 'warm_latte_bokeh',
    trTitle: 'Sıcak Latte Bokeh',
    enTitle: 'Warm Latte Bokeh',
    trSubtitle: 'Sıcak karamel ve yumuşak ışıklar',
    enSubtitle: 'Warm caramel & soft lights',
    isAnimated: true,
  ),
  sageSunlight(
    storageKey: 'sage_sunlight',
    trTitle: 'Adaçayı & Gün Işığı',
    enTitle: 'Sage & Sunlight',
    trSubtitle: 'Ferah adaçayı ve pastel ışıltılar',
    enSubtitle: 'Fresh sage & pastel glow',
    isAnimated: true,
  ),
  sakuraGarden(
    storageKey: 'sakura_garden',
    trTitle: 'Sakura Bahçesi',
    enTitle: 'Sakura Garden',
    trSubtitle: 'Sallanan kiraz ağaçları ve dere',
    enSubtitle: 'Swaying cherry trees & stream',
    isAnimated: true,
    isSpecial: true,
  );

  const AppThemePreset({
    required this.storageKey,
    required this.trTitle,
    required this.enTitle,
    required this.trSubtitle,
    required this.enSubtitle,
    this.isAnimated = false,
    this.isSpecial = false,
  });

  final String storageKey;
  final String trTitle;
  final String enTitle;
  final String trSubtitle;
  final String enSubtitle;
  final bool isAnimated;
  final bool isSpecial;

  bool get isGradientTheme => this != AppThemePreset.classic;

  bool get isAnimatedTheme => isAnimated;

  bool get isSpecialTheme => isSpecial;

  bool get isDarkPreset =>
      this == AppThemePreset.nightDepth ||
      this == AppThemePreset.electricCoral ||
      this == AppThemePreset.amethystGalaxy ||
      this == AppThemePreset.oceanDepths;

  static List<AppThemePreset> get staticPresets => AppThemePreset.values
      .where((p) => !p.isAnimated && !p.isSpecial)
      .toList(growable: false);

  static List<AppThemePreset> get animatedPresets => AppThemePreset.values
      .where((p) => p.isAnimated && !p.isSpecial)
      .toList(growable: false);

  static List<AppThemePreset> get specialPresets => AppThemePreset.values
      .where((p) => p.isSpecial)
      .toList(growable: false);

  ThemeMode get themeMode {
    if (this == AppThemePreset.classic) return ThemeMode.system;
    return isDarkPreset ? ThemeMode.dark : ThemeMode.light;
  }

  String titleForLocale({required bool isEnglish}) =>
      isEnglish ? enTitle : trTitle;

  String subtitleForLocale({required bool isEnglish}) =>
      isEnglish ? enSubtitle : trSubtitle;

  static AppThemePreset fromStorageKey(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final preset in AppThemePreset.values) {
      if (preset.storageKey == normalized) {
        return preset;
      }
    }
    return AppThemePreset.classic;
  }
}
