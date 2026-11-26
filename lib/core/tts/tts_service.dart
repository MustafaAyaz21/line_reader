import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../settings/ipa_accent_controller.dart';
import 'gemini_audio_service.dart';
import 'pronunciation_audio_service.dart';

/// Şu an hangi metnin sesli okunduğunu belirtir.
enum TtsSpeakingTarget {
  none,
  word,
  sentence,
}

/// Yapay zekâ kullanmayan, US/UK aksan destekli hibrit sesli okuma servisi:
/// - **Kelimeler için Birincil Mod**: Önce 12 MB üst limitli cihaz önbelleğine
///   (RAM + disk LRU) bakar; yoksa Cloudflare / ücretsiz açık kaynak gerçek
///   insan telaffuzunu (US veya UK) çekip önbelleğe alır ve `AudioPlayer` ile
///   çalar. Limit dolduğunda en eski kayıtlar otomatik silinir.
/// - **Cümleler ve Çevrimdışı Yedek Mod**: Platforma göre kalibre edilmiş hız
///   (Web'de `0.95`, mobilde `0.50`) ve cihaz/tarayıcıdaki en doğal US/UK ses
///   seçimi (`setVoice`) ile yerleşik `flutter_tts` motorunu kullanır.
class TtsService extends ChangeNotifier {
  TtsService({
    FlutterTts? tts,
    GeminiAudioService? geminiAudioService,
    AudioPlayer? audioPlayer,
    String? Function()? geminiApiKeyProvider,
    bool Function()? shouldUseGeminiProvider,
    PronunciationAudioService? pronunciationAudioService,
    IpaAccent Function()? accentProvider,
  })  : _tts = tts ?? FlutterTts(),
        _audioPlayer = audioPlayer,
        _ownsAudioPlayer = audioPlayer == null,
        _pronunciationAudioService = pronunciationAudioService,
        _ownsPronunciationAudioService = pronunciationAudioService == null,
        _accentProvider = accentProvider;

  static const double _mobileSpeechRate = 0.50;
  static const double _webSpeechRate = 0.95;
  static const double _defaultVolume = 1.0;
  static const double _defaultPitch = 1.0;

  final FlutterTts _tts;
  final IpaAccent Function()? _accentProvider;

  PronunciationAudioService? _pronunciationAudioService;
  bool _ownsPronunciationAudioService;

  AudioPlayer? _audioPlayer;
  bool _ownsAudioPlayer;
  StreamSubscription<void>? _playerCompleteSubscription;

  bool _isFlutterTtsConfigured = false;
  IpaAccent? _configuredAccent;
  bool _hasSelectedNaturalVoice = false;
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

  IpaAccent _resolveAccent() {
    return _accentProvider?.call() ?? IpaAccentController.shared.accent;
  }

  PronunciationAudioService _resolvePronunciationAudioService() {
    final existing = _pronunciationAudioService;
    if (existing != null) return existing;
    final created = PronunciationAudioService();
    _pronunciationAudioService = created;
    _ownsPronunciationAudioService = true;
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

  Future<bool> _ensureFlutterTtsConfigured({required IpaAccent accent}) async {
    if (_isFlutterTtsConfigured &&
        _configuredAccent == accent &&
        _hasSelectedNaturalVoice) {
      return true;
    }

    try {
      if (!_isFlutterTtsConfigured) {
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

        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          await _preferGoogleAndroidEngine();
        }

        await _tts.awaitSpeakCompletion(false);
        await _tts.setSpeechRate(
          kIsWeb ? _webSpeechRate : _mobileSpeechRate,
        );
        await _tts.setVolume(_defaultVolume);
        await _tts.setPitch(_defaultPitch);

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
      }

      if (_configuredAccent != accent) {
        await _applyLanguageForAccent(accent);
        _configuredAccent = accent;
        _hasSelectedNaturalVoice = false;
      }

      if (!_hasSelectedNaturalVoice) {
        _hasSelectedNaturalVoice = await _selectBestVoiceForAccent(accent);
      }

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

  Future<void> _preferGoogleAndroidEngine() async {
    try {
      final rawEngines = await _tts.getEngines;
      if (rawEngines is! List) return;
      for (final engine in rawEngines) {
        final name = engine?.toString() ?? '';
        if (name == 'com.google.android.tts') {
          await _tts.setEngine(name);
          return;
        }
      }
    } catch (_) {
      // Varsayılan sistem motoru ile devam et.
    }
  }

  Future<void> _applyLanguageForAccent(IpaAccent accent) async {
    final candidates = accent == IpaAccent.uk
        ? const <String>['en-GB', 'en-US', 'en']
        : const <String>['en-US', 'en-GB', 'en'];

    for (final lang in candidates) {
      try {
        final available = await _tts.isLanguageAvailable(lang);
        if (available == true || available == 1) {
          await _tts.setLanguage(lang);
          return;
        }
      } catch (_) {}
    }

    try {
      await _tts.setLanguage(accent.ttsLocale);
    } catch (_) {}
  }

  Future<bool> _selectBestVoiceForAccent(IpaAccent accent) async {
    try {
      final rawVoices = await _tts.getVoices;
      if (rawVoices is! List || rawVoices.isEmpty) {
        return false;
      }

      Map<String, String>? bestVoice;
      var bestScore = -10000;

      for (final item in rawVoices) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        final locale = item['locale']?.toString().trim() ?? '';
        if (name.isEmpty || locale.isEmpty) continue;

        final normalizedLocale = locale.replaceAll('_', '-').toLowerCase();
        if (!normalizedLocale.startsWith('en')) continue;

        final score = _scoreNativeVoice(
          name: name,
          normalizedLocale: normalizedLocale,
          accent: accent,
        );
        if (score > bestScore) {
          bestScore = score;
          bestVoice = <String, String>{
            'name': name,
            'locale': locale,
          };
        }
      }

      if (bestVoice != null) {
        await _tts.setVoice(bestVoice);
        return true;
      }
    } catch (error) {
      debugPrint('[TtsService] Ses secimi atlandi: $error');
    }
    return false;
  }

  static int _scoreNativeVoice({
    required String name,
    required String normalizedLocale,
    required IpaAccent accent,
  }) {
    final lowerName = name.toLowerCase();
    var score = 0;

    final targetLocale = accent == IpaAccent.uk ? 'en-gb' : 'en-us';
    final fallbackLocale = accent == IpaAccent.uk ? 'en-us' : 'en-gb';

    if (normalizedLocale == targetLocale) {
      score += 120;
    } else if (normalizedLocale.startsWith(targetLocale)) {
      score += 105;
    } else if (normalizedLocale == fallbackLocale) {
      score += 55;
    } else {
      score += 20;
    }

    // Yüksek kaliteli / doğal ses tercihleri (Web, Android, iOS, macOS, Windows)
    if (lowerName.contains('natural') || lowerName.contains('neural')) {
      score += 80;
    }
    if (lowerName.contains('online')) {
      score += 35;
    }
    if (lowerName.contains('premium') || lowerName.contains('enhanced')) {
      score += 70;
    }
    if (lowerName.contains('siri')) {
      score += 65;
    }
    if (lowerName.contains('google')) {
      score += 60;
    }
    if (lowerName.contains('network') || lowerName.contains('wavenet')) {
      score += 45;
    }
    if (lowerName.contains('en-us-x-') || lowerName.contains('en-gb-x-')) {
      score += 35;
    }

    // Doğal bilinen profil isimleri
    if (accent == IpaAccent.us) {
      if (lowerName.contains('aria') ||
          lowerName.contains('jenny') ||
          lowerName.contains('guy') ||
          lowerName.contains('samantha') ||
          lowerName.contains('ava') ||
          lowerName.contains('allison') ||
          lowerName.contains('google us english')) {
        score += 50;
      }
    } else {
      if (lowerName.contains('sonia') ||
          lowerName.contains('ryan') ||
          lowerName.contains('libby') ||
          lowerName.contains('daniel') ||
          lowerName.contains('serena') ||
          lowerName.contains('martha') ||
          lowerName.contains('google uk english')) {
        score += 50;
      }
    }

    // Aşırı robotik / eski sentezleyicileri cezalandır
    if (lowerName.contains('espeak') ||
        lowerName.contains('pico') ||
        lowerName.contains('compact') ||
        lowerName.contains('eloquence') ||
        lowerName.contains('fred') ||
        lowerName.contains('albert') ||
        lowerName.contains('zarvox') ||
        lowerName.contains('trinoids') ||
        lowerName.contains('whisper')) {
      score -= 120;
    }
    if (lowerName.contains('microsoft david') ||
        lowerName.contains('microsoft zira') ||
        lowerName.contains('microsoft mark')) {
      score -= 50;
    }

    return score;
  }

  /// Verilen metni sesli okur; aynı hedef zaten okunuyorsa/hazırlanıyorsa durdurur.
  /// Kelimelerde önce 12 MB limitli çevrimdışı önbellek + Cloudflare/açık kaynak
  /// gerçek insan US/UK MP3 kaydını kullanır; bulunamazsa veya cümle ise
  /// iyileştirilmiş `flutter_tts` motoruna düşer.
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

    final accent = _resolveAccent();

    // 1) Kelime telaffuzu için önce gerçek insan MP3 (Önbellek -> Cloudflare -> Açık Kaynak)
    if (target == TtsSpeakingTarget.word &&
        PronunciationAudioService.normalizeWordForAudio(trimmed) != null) {
      final audioService = _resolvePronunciationAudioService();

      // RAM önbelleğinde hazırsa bekleme göstergesi açmadan anında çal.
      final instantHit = audioService.getCachedFromMemorySync(
        word: trimmed,
        accent: accent,
      );
      if (instantHit != null) {
        _speakingTarget = target;
        _speakingText = trimmed;
        _isLoadingAudio = false;
        _safeNotifyListeners();

        final played = await _playAudioBytes(
          audioBytes: instantHit.bytes,
          mimeType: instantHit.mimeType,
          generation: myGeneration,
        );
        if (played) {
          return null;
        }
      } else {
        _speakingTarget = target;
        _speakingText = trimmed;
        _isLoadingAudio = true;
        _safeNotifyListeners();

        final fetched = await audioService.fetchWordAudio(
          word: trimmed,
          accent: accent,
        );

        if (_isDisposed || myGeneration != _requestGeneration) {
          return null;
        }

        if (fetched != null && fetched.bytes.isNotEmpty) {
          final played = await _playAudioBytes(
            audioBytes: fetched.bytes,
            mimeType: fetched.mimeType,
            generation: myGeneration,
          );
          if (played) {
            return null;
          }
        }

        if (_isDisposed || myGeneration != _requestGeneration) {
          return null;
        }
        _isLoadingAudio = false;
      }
    }

    // 2) Cümleler veya çevrimdışı/eksik kelimeler: iyileştirilmiş flutter_tts.
    return _speakWithFlutterTts(
      text: trimmed,
      target: target,
      accent: accent,
      generation: myGeneration,
    );
  }

  Future<bool> _playAudioBytes({
    required Uint8List audioBytes,
    required String mimeType,
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

      await player.play(BytesSource(audioBytes, mimeType: mimeType));
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
    required IpaAccent accent,
    required int generation,
  }) async {
    final configured = await _ensureFlutterTtsConfigured(accent: accent);
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
    if (_ownsAudioPlayer) {
      _audioPlayer?.dispose();
    }
    if (_ownsPronunciationAudioService) {
      _pronunciationAudioService?.dispose();
    }
    if (_isFlutterTtsConfigured) {
      _tts.stop().catchError((_) {});
    }
    super.dispose();
  }
}
