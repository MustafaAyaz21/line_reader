import 'package:flutter/material.dart';

/// CEFR dil seviyelerini A1'den C2'ye sabit sırada tanımlar.
enum ArticleLevel {
  a1(
    code: 'A1',
    label: 'Başlangıç',
    subtitle: 'Temel günlük ifadeler ve kısa metinler',
    accentColor: Color(0xFF16A34A),
  ),
  a2(
    code: 'A2',
    label: 'Temel',
    subtitle: 'Günlük yaşam ve sade anlatımlar',
    accentColor: Color(0xFF0D9488),
  ),
  b1(
    code: 'B1',
    label: 'Orta',
    subtitle: 'Akıcı konu anlatımları ve kısa hikayeler',
    accentColor: Color(0xFF2563EB),
  ),
  b2(
    code: 'B2',
    label: 'Üst Orta',
    subtitle: 'Detaylı makaleler ve yorum yazıları',
    accentColor: Color(0xFF4F46E5),
  ),
  c1(
    code: 'C1',
    label: 'İleri',
    subtitle: 'Derinlikli, zengin kelime dağarcıklı metinler',
    accentColor: Color(0xFFD97706),
  ),
  c2(
    code: 'C2',
    label: 'Uzman',
    subtitle: 'Edebi ve akademik düzeyde kapsamlı okumalar',
    accentColor: Color(0xFFBE185D),
  );

  const ArticleLevel({
    required this.code,
    required this.label,
    required this.subtitle,
    required this.accentColor,
  });

  final String code;
  final String label;
  final String subtitle;
  final Color accentColor;

  /// Ham seviye metnini (`"a2"`, `"B1 - Intermediate"`, vb.) [ArticleLevel]'a çevirir.
  static ArticleLevel? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    for (final level in ArticleLevel.values) {
      if (normalized == level.code ||
          normalized.startsWith('${level.code} ') ||
          normalized.startsWith('${level.code}-') ||
          normalized.startsWith('${level.code}_')) {
        return level;
      }
    }
    return null;
  }
}
