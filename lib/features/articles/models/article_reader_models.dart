import 'package:flutter/material.dart';

/// Yerel okuma ekranı için arka plan ve tipografi renk temaları.
enum ArticleReaderTone {
  white(
    storageKey: 'white',
    label: 'Beyaz',
    backgroundColor: Color(0xFFFFFFFF),
    surfaceColor: Color(0xFFF6F7F9),
    textColor: Color(0xFF1A1D21),
    secondaryTextColor: Color(0xFF5D6673),
    dividerColor: Color(0xFFE5E7EB),
    underlineColor: Color(0xFFD97706),
    underlineFillColor: Color(0x26F59E0B),
    brightness: Brightness.light,
  ),
  paper(
    storageKey: 'paper',
    label: 'Kağıt Tonu',
    backgroundColor: Color(0xFFF7F0E2),
    surfaceColor: Color(0xFFEDE3CE),
    textColor: Color(0xFF2B231A),
    secondaryTextColor: Color(0xFF6E6151),
    dividerColor: Color(0xFFDFD3BC),
    underlineColor: Color(0xFFB45309),
    underlineFillColor: Color(0x28D97706),
    brightness: Brightness.light,
  ),
  dark(
    storageKey: 'dark',
    label: 'Koyu',
    backgroundColor: Color(0xFF14171D),
    surfaceColor: Color(0xFF1E232C),
    textColor: Color(0xFFE5E7EB),
    secondaryTextColor: Color(0xFF9CA3AF),
    dividerColor: Color(0xFF2B313C),
    underlineColor: Color(0xFFFBBF24),
    underlineFillColor: Color(0x2BFBBF24),
    brightness: Brightness.dark,
  );

  const ArticleReaderTone({
    required this.storageKey,
    required this.label,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.dividerColor,
    required this.underlineColor,
    required this.underlineFillColor,
    required this.brightness,
  });

  final String storageKey;
  final String label;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color dividerColor;
  final Color underlineColor;
  final Color underlineFillColor;
  final Brightness brightness;

  static ArticleReaderTone fromStorageKey(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final tone in ArticleReaderTone.values) {
      if (tone.storageKey == normalized) {
        return tone;
      }
    }
    return ArticleReaderTone.paper;
  }
}

/// Makale metninde işaretlenen kelimelerin görsel stili.
enum ArticleMarkStyle {
  underline('underline'),
  highlight('highlight'),
  strikethrough('strikethrough');

  const ArticleMarkStyle(this.storageKey);

  final String storageKey;

  static ArticleMarkStyle fromStorageKey(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final style in ArticleMarkStyle.values) {
      if (style.storageKey == normalized) {
        return style;
      }
    }
    return ArticleMarkStyle.underline;
  }
}

/// Alt çizgi, fosforlu kalem ve üstü çizili işaretleme renk paleti.
enum ArticleMarkColor {
  amber(
    storageKey: 'amber',
    swatchColor: Color(0xFFD97706),
    darkAccentColor: Color(0xFFFBBF24),
    lightHighlightFill: Color(0x66FDE047),
    darkHighlightFill: Color(0x66FACC15),
  ),
  blue(
    storageKey: 'blue',
    swatchColor: Color(0xFF2563EB),
    darkAccentColor: Color(0xFF60A5FA),
    lightHighlightFill: Color(0x5260A5FA),
    darkHighlightFill: Color(0x663B82F6),
  ),
  green(
    storageKey: 'green',
    swatchColor: Color(0xFF16A34A),
    darkAccentColor: Color(0xFF4ADE80),
    lightHighlightFill: Color(0x594ADE80),
    darkHighlightFill: Color(0x6622C55E),
  ),
  rose(
    storageKey: 'rose',
    swatchColor: Color(0xFFE11D48),
    darkAccentColor: Color(0xFFFB7185),
    lightHighlightFill: Color(0x4DFB7185),
    darkHighlightFill: Color(0x66F43F5E),
  ),
  purple(
    storageKey: 'purple',
    swatchColor: Color(0xFF7C3AED),
    darkAccentColor: Color(0xFFA78BFA),
    lightHighlightFill: Color(0x4DA78BFA),
    darkHighlightFill: Color(0x668B5CF6),
  );

  const ArticleMarkColor({
    required this.storageKey,
    required this.swatchColor,
    required this.darkAccentColor,
    required this.lightHighlightFill,
    required this.darkHighlightFill,
  });

  final String storageKey;
  final Color swatchColor;
  final Color darkAccentColor;
  final Color lightHighlightFill;
  final Color darkHighlightFill;

  Color accentForTone(ArticleReaderTone tone) =>
      tone.brightness == Brightness.dark ? darkAccentColor : swatchColor;

  Color highlightFillForTone(ArticleReaderTone tone) =>
      tone.brightness == Brightness.dark
          ? darkHighlightFill
          : lightHighlightFill;

  static ArticleMarkColor fromStorageKey(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final color in ArticleMarkColor.values) {
      if (color.storageKey == normalized) {
        return color;
      }
    }
    return ArticleMarkColor.amber;
  }
}

/// Okuma ekranının yerel olarak saklanan görünüm ve işaretleme ayarları.
class ArticleReaderPreferences {
  const ArticleReaderPreferences({
    this.tone = ArticleReaderTone.paper,
    this.fontSize = defaultFontSize,
    this.markStyle = ArticleMarkStyle.underline,
    this.markColor = ArticleMarkColor.amber,
  });

  static const double minFontSize = 14.0;
  static const double maxFontSize = 28.0;
  static const double defaultFontSize = 18.0;

  static const ArticleReaderPreferences defaults = ArticleReaderPreferences();

  final ArticleReaderTone tone;
  final double fontSize;
  final ArticleMarkStyle markStyle;
  final ArticleMarkColor markColor;

  Color get effectiveMarkAccent => markColor.accentForTone(tone);

  Color get effectiveHighlightFill => markColor.highlightFillForTone(tone);

  ArticleReaderPreferences copyWith({
    ArticleReaderTone? tone,
    double? fontSize,
    ArticleMarkStyle? markStyle,
    ArticleMarkColor? markColor,
  }) {
    final nextSize =
        (fontSize ?? this.fontSize).clamp(minFontSize, maxFontSize).toDouble();
    return ArticleReaderPreferences(
      tone: tone ?? this.tone,
      fontSize: nextSize,
      markStyle: markStyle ?? this.markStyle,
      markColor: markColor ?? this.markColor,
    );
  }
}

/// Bir makale paragrafında kullanıcının altını çizdiği / işaretlediği metin aralığı.
class ArticleUnderline {
  const ArticleUnderline({
    this.id,
    required this.articleId,
    required this.paragraphIndex,
    required this.startOffset,
    required this.endOffset,
    this.createdAt,
  });

  final int? id;
  final String articleId;
  final int paragraphIndex;
  final int startOffset;
  final int endOffset;
  final DateTime? createdAt;

  bool containsOffset(int offset) => offset >= startOffset && offset < endOffset;

  bool overlaps(int start, int end) =>
      startOffset < end && start < endOffset;

  factory ArticleUnderline.fromDbRow(Map<String, Object?> row) {
    final createdMillis = row['created_at'] as int?;
    return ArticleUnderline(
      id: row['id'] as int?,
      articleId: (row['article_id'] as String? ?? '').trim(),
      paragraphIndex: (row['paragraph_index'] as int?) ?? 0,
      startOffset: (row['start_offset'] as int?) ?? 0,
      endOffset: (row['end_offset'] as int?) ?? 0,
      createdAt: createdMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(createdMillis)
          : null,
    );
  }

  Map<String, Object?> toDbRow() {
    return <String, Object?>{
      'article_id': articleId,
      'paragraph_index': paragraphIndex,
      'start_offset': startOffset,
      'end_offset': endOffset,
      'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
    };
  }
}
