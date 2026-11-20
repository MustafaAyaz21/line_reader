import 'dart:convert';

import '../../../core/utils/word_sanitizer.dart';

/// WebView'den gelen seçili kelime ve bağlam cümlesini taşıyan model.
class WordSelectionPayload {
  const WordSelectionPayload({
    required this.word,
    this.contextSentence,
  });

  final String word;
  final String? contextSentence;

  static WordSelectionPayload? fromMessage(String rawMessage) {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) return null;

    String rawWord = trimmed;
    String? rawSentence;

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, Object?>) {
          final parsedWord = decoded['word'];
          final parsedSentence = decoded['sentence'];
          if (parsedWord is String) {
            rawWord = parsedWord;
          }
          if (parsedSentence is String) {
            rawSentence = parsedSentence;
          }
        }
      } catch (_) {
        // JSON ayrıştırılamazsa ham metin olarak devam et.
      }
    }

    final cleanedWord = WordSanitizer.clean(rawWord) ?? _fallbackClean(rawWord);
    if (cleanedWord == null) return null;

    final cleanedSentence = rawSentence
        ?.trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    return WordSelectionPayload(
      word: cleanedWord,
      contextSentence:
          (cleanedSentence != null && cleanedSentence.isNotEmpty)
              ? cleanedSentence
              : null,
    );
  }

  static String? _fallbackClean(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty || normalized.length > 80) return null;
    return normalized;
  }
}
