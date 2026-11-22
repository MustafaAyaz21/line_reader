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
  );

  const AppThemePreset({
    required this.storageKey,
    required this.trTitle,
    required this.enTitle,
    required this.trSubtitle,
    required this.enSubtitle,
  });

  final String storageKey;
  final String trTitle;
  final String enTitle;
  final String trSubtitle;
  final String enSubtitle;

  bool get isGradientTheme => this != AppThemePreset.classic;

  bool get isDarkPreset =>
      this == AppThemePreset.nightDepth || this == AppThemePreset.electricCoral;

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
