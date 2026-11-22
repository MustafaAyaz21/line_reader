/// Ücretsiz çeviri/sözlük servisleri ve isteğe bağlı Gemini API uç nokta ayarları.
abstract final class ApiConfig {
  /// İsteğe bağlı Gemini API uç noktası (yalnızca tarayıcı bağlamsal AI
  /// çevirisi için derleme zamanı anahtarı ile aktif olur; son kullanıcıdan
  /// manuel API anahtarı istenmez).
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Derleme zamanında (`--dart-define=GEMINI_API_KEY=...`) tanımlanabilen
  /// yönetilen Gemini API anahtarı (yalnızca tarayıcı bağlamsal çevirisinde kullanılır).
  static const String managedGeminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  /// Tarayıcı bağlamsal AI çevirisi için Cloudflare Workers AI uç noktası.
  /// Yalnızca kayıtlı Firebase kullanıcılarının imzalı ID Token'ı ile yanıt verir;
  /// APK içinde hiçbir gizli anahtar tutulmaz.
  static const String browserAiTranslateEndpoint = String.fromEnvironment(
    'AI_TRANSLATE_ENDPOINT',
    defaultValue: 'https://linereader-ai.xreasayaz21.workers.dev',
  );

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

  /// Makaleler için birincil uzak JSON veri kaynağı (Cloudflare Pages CDN).
  /// İleride makale kaynağını değiştirmek için bu tek sabit güncellenebilir.
  static const String articlesJsonUrl =
      'https://line-reader.pages.dev/articles.json';

  /// Birincil CDN geçici olarak erişilemez olursa devreye giren yedek raw URL.
  static const String articlesFallbackJsonUrl =
      'https://raw.githubusercontent.com/MustafaAyaz21/line_reader/main/articles.json';

  static const Duration requestTimeout = Duration(seconds: 12);
}
