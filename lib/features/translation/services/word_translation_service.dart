import '../models/word_meaning.dart';

/// Çeviri servisinde oluşabilecek hata türleri.
enum TranslationErrorType {
  unauthorized,
  rateLimited,
  network,
  invalidResponse,
  unknown,
}

/// Çeviri servisi hatalarını kullanıcı dostu mesajlarla taşır.
class TranslationException implements Exception {
  const TranslationException({
    required this.type,
    required this.message,
  });

  final TranslationErrorType type;
  final String message;

  @override
  String toString() => 'TranslationException($type): $message';
}

/// Bağlama duyarlı kelime anlamı getiren servisler için ortak arayüz.
abstract interface class WordTranslationService {
  Future<WordMeaning> lookup({
    required String word,
    String? contextSentence,
  });

  void dispose();
}
