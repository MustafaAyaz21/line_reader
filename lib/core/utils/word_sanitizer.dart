/// WebView üzerinden yakalanan ham metni temizleyip normalize eder.
abstract final class WordSanitizer {
  static const int _maxLength = 48;
  static const int _maxWordCount = 3;

  static final RegExp _edgeNonLetters = RegExp(
    r'^[^\p{L}\p{M}]+|[^\p{L}\p{M}]+$',
    unicode: true,
  );
  static final RegExp _multiWhitespace = RegExp(r'\s+');

  /// Metni temizler ve küçük harfe çevirir.
  /// Geçerli bir kelime (veya kısa ifade) yoksa `null` döner.
  static String? clean(String rawText) {
    final normalizedSpace = rawText.trim().replaceAll(_multiWhitespace, ' ');
    if (normalizedSpace.isEmpty) {
      return null;
    }

    final stripped = normalizedSpace.replaceAll(_edgeNonLetters, '').trim();
    if (stripped.isEmpty) {
      return null;
    }

    // Uzun paragraf seçimlerinde BottomSheet açılmasını engelle.
    final words = stripped.split(' ');
    if (stripped.length > _maxLength || words.length > _maxWordCount) {
      return null;
    }

    // 'İ' karakterinde birleşik nokta kalıntısını önleyerek küçük harfe çevir.
    return stripped.replaceAll('İ', 'i').toLowerCase();
  }
}
