import 'package:flutter/foundation.dart';

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

  /// Tarayıcı bağlamsal AI çevirisi ve bulut senkronizasyonu için Cloudflare Workers uç noktası.
  /// Yalnızca kayıtlı Firebase kullanıcılarının imzalı ID Token'ı ile yanıt verir;
  /// APK içinde hiçbir gizli anahtar tutulmaz.
  static const String browserAiTranslateEndpoint = String.fromEnvironment(
    'AI_TRANSLATE_ENDPOINT',
    defaultValue: 'https://linereader-ai.xreasayaz21.workers.dev',
  );

  /// Mobil operatörlerin kesmesi durumunda otomatik devreye giren birincil Cloudflare apex yedeği.
  static const String browserAiFallbackEndpoint =
      'https://getlinereader.com/api';

  /// İkincil Netlify proxy yedeği.
  static const String browserAiSecondaryFallbackEndpoint =
      'https://linereaderr.netlify.app/api';

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
  static String get contextualTranslateBaseUrl {
    if (kIsWeb) {
      return 'https://linereader-ai.xreasayaz21.workers.dev/dict';
    }
    return 'https://translate.googleapis.com/translate_a/single';
  }

  /// Web ortamında CORS engeli aşımı için kullanılacak alternatif uç noktalar
  static List<String> get contextualTranslateBaseUrls {
    if (kIsWeb) {
      return const <String>[
        'https://linereader-ai.xreasayaz21.workers.dev/dict',
        'https://getlinereader.com/api/dict',
      ];
    }
    return const <String>[
      'https://translate.googleapis.com/translate_a/single',
    ];
  }

  /// Yedek ücretsiz açık sözlük servisi (anahtar gerektirmez).
  static const String freeDictionaryBaseUrl =
      'https://api.dictionaryapi.dev/api/v2/entries/en';

  /// Yedek ücretsiz çeviri servisi (anahtar gerektirmez).
  static const String myMemoryBaseUrl =
      'https://api.mymemory.translated.net/get';

  /// Kelime arama ekranı için D1 önbellekli doğal örnek cümle uç noktası (8–22 kelime).
  static const String wordExamplesWorkerUrl =
      'https://linereader-ai.xreasayaz21.workers.dev/examples';

  /// Yedek ücretsiz insan çevirili cümle korpusu (Tatoeba).
  static const String tatoebaSearchBaseUrl =
      'https://tatoeba.org/en/api_v0/search';

  /// Makaleler için birincil uzak JSON veri kaynağı (Cloudflare Worker + D1:
  /// yayınlaya basıldığı anda 1 saniye altında güncellenir).
  static const String articlesJsonUrl =
      'https://linereader-ai.xreasayaz21.workers.dev/articles.json';

  /// Birincil Worker henüz boş veya erişilemezse devreye giren Cloudflare Pages CDN yedeği.
  static const String articlesFallbackJsonUrl =
      'https://getlinereader.com/articles.json';

  /// İkincil CDN de geçici olarak erişilemezse devreye giren GitHub raw yedeği.
  static const String articlesGithubFallbackJsonUrl =
      'https://raw.githubusercontent.com/MustafaAyaz21/line_reader/main/articles.json';

  static const Duration requestTimeout = Duration(seconds: 12);
}
