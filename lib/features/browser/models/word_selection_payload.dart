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

    final cleanedWord = WordSanitizer.clean(rawWord);
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
}
