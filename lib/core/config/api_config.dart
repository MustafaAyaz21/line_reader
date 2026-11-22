/// Ücretsiz çeviri/sözlük servisleri ve isteğe bağlı Gemini API uç nokta ayarları.
abstract final class ApiConfig {
  /// İsteğe bağlı Gemini API uç noktası (kullanıcı uygulama içinden anahtar
  /// kaydettiğinde aktif olur; anahtar yoksa anahtarsız ücretsiz servisler çalışır).
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Varsayılan güncel Gemini modeli.
  static const String geminiModel = 'gemini-3.0-flash';

  /// Birincil model HTTP 404 döndürürse sırayla denenecek alternatif güncel modeller.
  static const List<String> geminiFallbackModels = <String>[
    'gemini-3-flash-preview',
    'gemini-3.0-flash-lite',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
  ];

  /// Gemini ses üretimi (AUDIO modality) için öncelikli ve yedek modeller.
  static const String geminiTtsModel = 'gemini-2.5-flash-preview-tts';
  static const List<String> geminiTtsFallbackModels = <String>[
    'gemini-3.0-flash',
    'gemini-2.5-pro-preview-tts',
  ];
  static const String geminiTtsVoiceName = 'Kore';

  /// Birincil ücretsiz bağlam + iki dilli sözlük uç noktası (anahtar gerektirmez).
  static const String contextualTranslateBaseUrl =
      'https://translate.googleapis.com/translate_a/single';

  /// Yedek ücretsiz açık sözlük servisi (anahtar gerektirmez).
  static const String freeDictionaryBaseUrl =
      'https://api.dictionaryapi.dev/api/v2/entries/en';

  /// Yedek ücretsiz çeviri servisi (anahtar gerektirmez).
  static const String myMemoryBaseUrl =
      'https://api.mymemory.translated.net/get';

  /// Makaleler için varsayılan uzak JSON veri kaynağı (raw GitHub URL).
  /// İleride makale kaynağını değiştirmek için bu tek sabit güncellenebilir.
  static const String articlesJsonUrl =
      'https://raw.githubusercontent.com/MustafaAyaz21/line_reader/main/articles.json';

  static const Duration requestTimeout = Duration(seconds: 12);
}
