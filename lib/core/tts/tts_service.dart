import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'gemini_audio_service.dart';

/// Şu an hangi metnin sesli okunduğunu belirtir.
enum TtsSpeakingTarget {
  none,
  word,
  sentence,
}

/// Çift modlu sesli okuma (Text-to-Speech) servisi:
/// - **Gemini Ses Modu**: Kullanıcı geçerli bir Gemini API anahtarı girdiyse
///   öncelikle Gemini'nin `responseModalities: ["AUDIO"]` ses üretimiyle doğal
///   İngilizce telaffuz üretip `AudioPlayer` üzerinden çalar.
/// - **Anahtarsız / Güvenli Yedek Mod**: API anahtarı yoksa veya Gemini ses
///   çağrısında herhangi bir hata (kota, yetki, model, ağ, boş veri vb.) oluşursa
///   uygulamayı kilitlemeden sessizce cihazın yerleşik `flutter_tts` (`en-US`)
///   motoruna düşerek okumayı tamamlar.
class TtsService extends ChangeNotifier {
  TtsService({
    FlutterTts? tts,
    GeminiAudioService? geminiAudioService,
    AudioPlayer? audioPlayer,
    String? Function()? geminiApiKeyProvider,
    bool Function()? shouldUseGeminiProvider,
  })  : _tts = tts ?? FlutterTts(),
        _geminiAudioService = geminiAudioService,
        _ownsGeminiAudioService = geminiAudioService == null,
        _audioPlayer = audioPlayer,
        _ownsAudioPlayer = audioPlayer == null,
        _geminiApiKeyProvider = geminiApiKeyProvider,
        _shouldUseGeminiProvider = shouldUseGeminiProvider;

  static const List<String> _preferredLanguages = <String>[
    'en-US',
    'en-GB',
    'en',
  ];
  static const double _defaultSpeechRate = 0.48;
  static const double _defaultVolume = 1.0;
  static const double _defaultPitch = 1.0;

  final FlutterTts _tts;
  final String? Function()? _geminiApiKeyProvider;
  final bool Function()? _shouldUseGeminiProvider;

  GeminiAudioService? _geminiAudioService;
  bool? _ownsGeminiAudioService;

  AudioPlayer? _audioPlayer;
  bool? _ownsAudioPlayer;
  StreamSubscription<void>? _playerCompleteSubscription;

  bool _isFlutterTtsConfigured = false;
  bool _isDisposed = false;
  bool _isLoadingAudio = false;
  int _requestGeneration = 0;
  TtsSpeakingTarget _speakingTarget = TtsSpeakingTarget.none;
  String? _speakingText;
  String? _errorMessage;

  TtsSpeakingTarget get speakingTarget => _speakingTarget;
  String? get speakingText => _speakingText;
  bool get isSpeaking => _speakingTarget != TtsSpeakingTarget.none;
  bool get isLoadingAudio => _isLoadingAudio;
  String? get errorMessage => _errorMessage;

  /// Belirli bir metnin (ör. listedeki tek bir kelimenin) şu an aktif olarak
  /// okunup okunmadığını veya hazırlanıp hazırlanmadığını kontrol eder.
  bool isSpeakingText(
    String text, {
    TtsSpeakingTarget target = TtsSpeakingTarget.word,
  }) {
    if (_speakingTarget != target) return false;
    final current = _speakingText;
    if (current == null) return false;
    return current.toLowerCase() == text.trim().toLowerCase();
  }

  String? get _activeGeminiKey {
    final key = _geminiApiKeyProvider?.call()?.trim();
    if (key == null || key.isEmpty) return null;
    final allowed = _shouldUseGeminiProvider?.call() ?? true;
    return allowed ? key : null;
  }

  GeminiAudioService _resolveGeminiAudioService() {
    final existing = _geminiAudioService;
    if (existing != null) return existing;
    final created = GeminiAudioService();
    _geminiAudioService = created;
    _ownsGeminiAudioService = true;
    return created;
  }

  AudioPlayer _resolveAudioPlayer() {
    final existing = _audioPlayer;
    if (existing != null) return existing;

    final player = AudioPlayer();
    _audioPlayer = player;
    _ownsAudioPlayer = true;
    _attachPlayerListeners(player);
    return player;
  }

  void _attachPlayerListeners(AudioPlayer player) {
    _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = player.onPlayerComplete.listen((_) {
      if (_isDisposed) return;
      _isLoadingAudio = false;
      _speakingTarget = TtsSpeakingTarget.none;
      _speakingText = null;
      _safeNotifyListeners();
    });
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void clearError({bool notify = true}) {
    if (_errorMessage == null) return;
    _errorMessage = null;
    if (notify) {
      _safeNotifyListeners();
    }
  }

  Future<bool> _ensureFlutterTtsConfigured() async {
    if (_isFlutterTtsConfigured) return true;

    try {
      _tts.setStartHandler(() {
        _errorMessage = null;
        _isLoadingAudio = false;
        _safeNotifyListeners();
      });

      _tts.setCompletionHandler(() {
        _isLoadingAudio = false;
        _speakingTarget = TtsSpeakingTarget.none;
        _speakingText = null;
        _safeNotifyListeners();
      });

      _tts.setCancelHandler(() {
        _isLoadingAudio = false;
        _speakingTarget = TtsSpeakingTarget.none;
        _speakingText = null;
        _safeNotifyListeners();
      });

      _tts.setErrorHandler((dynamic message) {
        debugPrint('[TtsService] Native TTS hatasi: $message');
        _isLoadingAudio = false;
        _speakingTarget = TtsSpeakingTarget.none;
        _speakingText = null;
        _errorMessage =
            'Sesli okuma başlatılamadı. Cihazın TTS motorunu kontrol edin.';
        _safeNotifyListeners();
      });

      await _tts.awaitSpeakCompletion(false);
      await _tts.setSpeechRate(_defaultSpeechRate);
      await _tts.setVolume(_defaultVolume);
      await _tts.setPitch(_defaultPitch);

      var languageSelected = false;
      for (final lang in _preferredLanguages) {
        try {
          final available = await _tts.isLanguageAvailable(lang);
          if (available == true || available == 1) {
            await _tts.setLanguage(lang);
            languageSelected = true;
            break;
          }
        } catch (_) {
          // Sonraki dil seçeneğini dene.
        }
      }

      if (!languageSelected) {
        try {
          await _tts.setLanguage('en-US');
        } catch (_) {
          // Cihazın varsayılan diliyle devam etmeyi dene.
        }
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          await _tts.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playback,
            <IosTextToSpeechAudioCategoryOptions>[
              IosTextToSpeechAudioCategoryOptions.mixWithOthers,
              IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            ],
          );
        } catch (_) {}
      }

      _isFlutterTtsConfigured = true;
      return true;
    } on MissingPluginException catch (error) {
      debugPrint('[TtsService] MissingPluginException: $error');
      _errorMessage =
          'Sesli okuma eklentisi henüz yüklenmedi. Uygulamayı yeniden derleyip başlatın.';
      _safeNotifyListeners();
      return false;
    } on PlatformException catch (error) {
      debugPrint('[TtsService] PlatformException: $error');
      _errorMessage =
          'Bu cihazda sesli okuma (TTS) motoru bulunamadı veya kullanılamıyor.';
      _safeNotifyListeners();
      return false;
    } catch (error) {
      debugPrint('[TtsService] Yapilandirma hatasi: $error');
      _errorMessage = 'Sesli okuma servisi hazırlanırken bir sorun oluştu.';
      _safeNotifyListeners();
      return false;
    }
  }

  /// Verilen metni sesli okur; aynı hedef zaten okunuyorsa/hazırlanıyorsa durdurur.
  /// Gemini anahtarı aktifse önce Gemini sesini dener, herhangi bir sorunda
  /// sessizce cihazın yerleşik `flutter_tts` motoruna düşer.
  Future<String?> toggleSpeak({
    required String text,
    required TtsSpeakingTarget target,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return 'Okunacak metin bulunamadı.';
    }

    if (isSpeakingText(trimmed, target: target)) {
      await stop();
      return null;
    }

    // Önceki çalan sesi veya bekleyen isteği temizle.
    await stop(notify: false);
    final int myGeneration = ++_requestGeneration;
    _errorMessage = null;

    // 1) Gemini API anahtarı aktifse önce Gemini ses üretimini dene.
    final geminiKey = _activeGeminiKey;
    if (geminiKey != null) {
      _speakingTarget = target;
      _speakingText = trimmed;
      _isLoadingAudio = true;
      _safeNotifyListeners();

      final audioBytes = await _resolveGeminiAudioService().synthesize(
        apiKey: geminiKey,
        text: trimmed,
        isSentence: target == TtsSpeakingTarget.sentence,
      );

      // İstek sürerken kullanıcı durdurduysa veya panel kapandıysa sessizce çık.
      if (_isDisposed || myGeneration != _requestGeneration) {
        return null;
      }

      if (audioBytes != null && audioBytes.isNotEmpty) {
        final played = await _playAudioBytes(
          audioBytes: audioBytes,
          generation: myGeneration,
        );
        if (played) {
          return null;
        }
        // Oynatıcı hata verdiyse aşağıdan güvenli şekilde flutter_tts'e düş.
      } else {
        debugPrint(
          '[TtsService] Gemini ses uretilemedi, yerlesik flutter_tts '
          'motoruna dusuluyor.',
        );
      }

      if (_isDisposed || myGeneration != _requestGeneration) {
        return null;
      }
      _isLoadingAudio = false;
    }

    // 2) Anahtarsız mod veya Gemini yedeği: cihazın yerleşik flutter_tts motoru.
    return _speakWithFlutterTts(
      text: trimmed,
      target: target,
      generation: myGeneration,
    );
  }

  Future<bool> _playAudioBytes({
    required Uint8List audioBytes,
    required int generation,
  }) async {
    try {
      final player = _resolveAudioPlayer();
      if (_playerCompleteSubscription == null) {
        _attachPlayerListeners(player);
      }

      await player.stop();
      if (_isDisposed || generation != _requestGeneration) {
        return true;
      }

      _isLoadingAudio = false;
      _safeNotifyListeners();

      await player.play(BytesSource(audioBytes));
      return true;
    } catch (error) {
      debugPrint(
        '[TtsService] AudioPlayer oynatma hatasi (flutter_tts yedege geciliyor): '
        '$error',
      );
      _isLoadingAudio = false;
      return false;
    }
  }

  Future<String?> _speakWithFlutterTts({
    required String text,
    required TtsSpeakingTarget target,
    required int generation,
  }) async {
    final configured = await _ensureFlutterTtsConfigured();
    if (_isDisposed || generation != _requestGeneration) {
      return null;
    }

    if (!configured) {
      _speakingTarget = TtsSpeakingTarget.none;
      _speakingText = null;
      _isLoadingAudio = false;
      _safeNotifyListeners();
      return _errorMessage;
    }

    try {
      _speakingTarget = target;
      _speakingText = text;
      _isLoadingAudio = false;
      _safeNotifyListeners();

      final result = await _tts.speak(text);
      if (_isDisposed || generation != _requestGeneration) {
        return null;
      }

      if (result == 0 || result == false) {
        _speakingTarget = TtsSpeakingTarget.none;
        _speakingText = null;
        _errorMessage =
            'Cihazda uygun bir sesli okuma (TTS) motoru bulunamadı.';
        _safeNotifyListeners();
        return _errorMessage;
      }

      return null;
    } on MissingPluginException catch (error) {
      debugPrint('[TtsService] speak MissingPluginException: $error');
      _speakingTarget = TtsSpeakingTarget.none;
      _speakingText = null;
      _isLoadingAudio = false;
      _errorMessage =
          'Sesli okuma eklentisi hazır değil. Uygulamayı tam yeniden başlatın.';
      _safeNotifyListeners();
      return _errorMessage;
    } on PlatformException catch (error) {
      debugPrint('[TtsService] speak PlatformException: $error');
      _speakingTarget = TtsSpeakingTarget.none;
      _speakingText = null;
      _isLoadingAudio = false;
      _errorMessage =
          'Sesli okuma sırasında cihaz ses motoru hatası oluştu.';
      _safeNotifyListeners();
      return _errorMessage;
    } catch (error) {
      debugPrint('[TtsService] speak genel hata: $error');
      _speakingTarget = TtsSpeakingTarget.none;
      _speakingText = null;
      _isLoadingAudio = false;
      _errorMessage = 'Sesli okuma başlatılamadı. Lütfen tekrar deneyin.';
      _safeNotifyListeners();
      return _errorMessage;
    }
  }

  Future<void> stop({bool notify = true}) async {
    _requestGeneration++;
    final hadActiveState =
        _speakingTarget != TtsSpeakingTarget.none || _isLoadingAudio;
    _speakingTarget = TtsSpeakingTarget.none;
    _speakingText = null;
    _isLoadingAudio = false;

    if (hadActiveState && notify) {
      _safeNotifyListeners();
    }

    final player = _audioPlayer;
    if (player != null) {
      try {
        await player.stop();
      } catch (error) {
        debugPrint('[TtsService] AudioPlayer stop hatasi: $error');
      }
    }

    if (_isFlutterTtsConfigured) {
      try {
        await _tts.stop();
      } catch (error) {
        debugPrint('[TtsService] flutter_tts stop hatasi: $error');
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _requestGeneration++;
    _playerCompleteSubscription?.cancel();
    if (_ownsAudioPlayer ?? false) {
      _audioPlayer?.dispose();
    }
    if (_ownsGeminiAudioService ?? false) {
      _geminiAudioService?.dispose();
    }
    if (_isFlutterTtsConfigured) {
      _tts.stop().catchError((_) {});
    }
    super.dispose();
  }
}
