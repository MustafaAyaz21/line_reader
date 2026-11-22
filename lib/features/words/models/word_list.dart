import 'package:flutter/material.dart';

/// Yeni kelime listesi oluşturup oluşan listeyi (veya doğrulama/hata mesajını)
/// döndüren geri çağırma imzası.
typedef CreateWordListCallback = Future<({WordList? list, String? error})>
    Function(String name, int colorValue);

/// Özel kelime listeleri için hazır renk paleti.
abstract final class WordListColors {
  static const List<int> palette = <int>[
    0xFFF59E0B, // Amber / Favoriler
    0xFF2563EB, // Mavi
    0xFF10B981, // Zümrüt Yeşili
    0xFFEF4444, // Mercan Kırmızısı
    0xFF8B5CF6, // Mor
    0xFF06B6D4, // Turkuaz
    0xFFF97316, // Turuncu
    0xFFEC4899, // Pembe
    0xFF4F46E5, // İndigo
    0xFF64748B, // Arduvaz Gri
  ];
}

/// Yerel SQLite veri tabanında saklanan kelime listesi (klasör) modeli.
class WordList {
  const WordList({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.isDefault,
    required this.createdAt,
    this.wordCount = 0,
  });

  final int id;
  final String name;
  final int colorValue;
  final bool isDefault;
  final DateTime createdAt;
  final int wordCount;

  Color get color => Color(colorValue);

  factory WordList.fromMap(Map<String, Object?> map) {
    return WordList(
      id: map['id'] as int,
      name: map['name'] as String,
      colorValue: map['color_value'] as int,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
      ),
      wordCount: (map['word_count'] as int?) ?? 0,
    );
  }

  WordList copyWith({
    int? id,
    String? name,
    int? colorValue,
    bool? isDefault,
    DateTime? createdAt,
    int? wordCount,
  }) {
    return WordList(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      wordCount: wordCount ?? this.wordCount,
    );
  }
}
