import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/api_config.dart';
import '../models/article.dart';
import '../utils/article_text_parser.dart';

/// Makale sesli okuma motoru modu.
enum ArticleAudioMode {
  /// Stüdyo / Podcast kalitesinde yapay zeka ses dosyası (`.m4a` / `.mp3`).
  podcastAudio,

  /// Cihazın yerleşik `flutter_tts` ses motoru (çevrimdışı & tüm eski makaleler).
  deviceTts,
}

/// Cihaz TTS aksan seçimi.
enum ArticleTtsAccent {
  us('en-US', 'US'),
  uk('en-GB', 'UK');

  const ArticleTtsAccent(this.localeCode, this.shortLabel);

  final String localeCode;
  final String shortLabel;
}

/// Test edilebilir cihaz TTS arayüzü.
abstract class ArticleTtsEngine {
  Future<void> configure({
    required String language,
    required double speechRate,
    required VoidCallback onCompleted,
    required void Function(String message) onError,
  });

  Future<void> setLanguage(String language);
  Future<void> setSpeechRate(double rate);
  Future<bool> speak(String text);
  Future<void> stop();
  void dispose();
}

class _FlutterArticleTtsEngine implements ArticleTtsEngine {
  _FlutterArticleTtsEngine([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  @override
  Future<void> configure({
    required String language,
    required double speechRate,
    required VoidCallback onCompleted,
    required void Function(String message) onError,
  }) async {
    _tts.setCompletionHandler(onCompleted);
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((dynamic msg) => onError(msg?.toString() ?? 'error'));
    if (!_configured) {
      await _tts.awaitSpeakCompletion(false);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
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
      _configured = true;
    }
    await setLanguage(language);
    await setSpeechRate(speechRate);
  }

  @override
  Future<void> setLanguage(String language) async {
    final candidates = <String>[
      language,
      if (language != 'en-US') 'en-US',
      if (language != 'en-GB') 'en-GB',
      'en',
    ];
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
      await _tts.setLanguage('en-US');
    } catch (_) {}
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    try {
      await _tts.setSpeechRate(rate);
    } catch (_) {}
  }

  @override
  Future<bool> speak(String text) async {
    try {
      final dynamic res = await _tts.speak(text);
      if (res == 1 || res == true) return true;
      // Android TTS servisi ilk bağlanmada 0 dönebilir; kısa bekleme ile 1 kez daha dene.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      final dynamic retryRes = await _tts.speak(text);
      return retryRes == 1 || retryRes == true || retryRes == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_configured) {
      _tts.stop().catchError((_) {});
    }
  }
}

/// Test edilebilir podcast ses oynatıcı arayüzü.
abstract class ArticlePodcastPlayer {
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Stream<void> get onPlayerComplete;

  Future<void> setSourceFile(String filePath);
  Future<void> setSourceUrl(String url);
  Future<void> setPlaybackRate(double rate);
  Future<void> resume();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  void dispose();
}

class _AudioPlayersPodcastPlayer implements ArticlePodcastPlayer {
  _AudioPlayersPodcastPlayer([AudioPlayer? player])
      : _player = player ?? AudioPlayer();

  static final AudioContext _speechAudioContext = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: true,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
    ),
  );

  final AudioPlayer _player;
  bool _audioContextConfigured = false;

  Future<void> _ensurePlayerConfigured() async {
    if (_audioContextConfigured) return;
    _audioContextConfigured = true;
    try {
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
    } catch (_) {}
    try {
      await _player.setAudioContext(_speechAudioContext);
    } catch (_) {}
  }

  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> setSourceFile(String filePath) async {
    await _ensurePlayerConfigured();
    await _player.setSource(DeviceFileSource(filePath));
  }

  @override
  Future<void> setSourceUrl(String url) async {
    await _ensurePlayerConfigured();
    await _player.setSource(UrlSource(url));
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    await _player.setPlaybackRate(rate);
  }

  @override
  Future<void> resume() async {
    await _player.resume();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  void dispose() {
    _player.dispose();
  }
}

/// Makale okuma ekranı için çift motorlu (Podcast AI Ses + Cihaz TTS yedeği)
/// cümle-cümle ve paragraf-paragraf sesli okuma denetleyicisi.
///
/// - Makalede `audio_url` varsa öncelikle **Podcast AI** modunda insan sesine
///   yakın stüdyo ses dosyasını yerel önbelleğe indirip oynatır; ağ/dosya
///   sorununda sessizce **Cihaz Sesi (`flutter_tts`)** yedeğine düşer.
/// - Makalede `audio_url` yoksa (tüm eski makaleler dahil) doğrudan **Cihaz
///   Sesi** ile cümle-cümle ve çevrimdışı çalışır.
/// - Her iki modda da: Oynat/Duraklat, Önceki/Sonraki Cümle, Önceki/Sonraki
///   Paragraf, Hız (`0.75x`, `1.0x`, `1.25x`, `1.5x`) ve canlı cümle vurgusu
///   birebir çalışır.
class ArticleAudioController extends ChangeNotifier {
  ArticleAudioController({
    required this.article,
    required this.paragraphs,
    int initialPositionMs = 0,
    ArticleTtsEngine? ttsEngine,
    ArticlePodcastPlayer? podcastPlayer,
    http.Client? httpClient,
    Future<String?> Function(String audioUrl)? audioFileResolver,
  })  : _ttsEngine = ttsEngine ?? _FlutterArticleTtsEngine(),
        _podcastPlayer = podcastPlayer ?? _AudioPlayersPodcastPlayer(),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _audioFileResolver = audioFileResolver {
    _sentences = ArticleTextParser.splitParagraphSentences(paragraphs);
    _mode = article.hasPodcastAudio
        ? ArticleAudioMode.podcastAudio
        : ArticleAudioMode.deviceTts;
    if (initialPositionMs > 0) {
      _position = Duration(milliseconds: initialPositionMs);
      positionNotifier.value = _position;
      _currentSentenceIndex = _sentenceIndexForPosition(_position);
    }
    _attachPodcastListeners();
  }

  static const List<double> speedOptions = <double>[0.75, 1.0, 1.25, 1.5];

  final Article article;
  final List<String> paragraphs;
  final ArticleTtsEngine _ttsEngine;
  final ArticlePodcastPlayer _podcastPlayer;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Future<String?> Function(String audioUrl)? _audioFileResolver;

  late final List<ArticleSentenceSpan> _sentences;
  late ArticleAudioMode _mode;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  bool _isVisible = false;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _podcastLoaded = false;
  bool _ttsConfigured = false;
  bool _isDisposed = false;

  int _currentSentenceIndex = 0;
  int _ttsGeneration = 0;
  double _playbackSpeed = 1.0;
  ArticleTtsAccent _accent = ArticleTtsAccent.us;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _statusNotice;
  bool _hasAppliedCustomRate = false;

  /// Yüksek frekanslı (~200 ms) konum güncellemelerini tüm makale metnini
  /// yeniden çizmeden yalnızca alt oynatıcı çubuğuna iletir.
  final ValueNotifier<Duration> positionNotifier =
      ValueNotifier<Duration>(Duration.zero);

  List<ArticleSentenceSpan> get sentences => _sentences;
  bool get hasPlayableContent => _sentences.isNotEmpty;
  bool get hasPodcastAudio => article.hasPodcastAudio;
  ArticleAudioMode get mode => _mode;
  bool get isVisible => _isVisible;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  double get playbackSpeed => _playbackSpeed;
  ArticleTtsAccent get accent => _accent;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get statusNotice => _statusNotice;

  int get totalSentences => _sentences.length;
  int get totalParagraphs => paragraphs.length;

  int get currentSentenceIndex => _sentences.isEmpty
      ? 0
      : _currentSentenceIndex.clamp(0, _sentences.length - 1);

  ArticleSentenceSpan? get activeSentence {
    if (!_isVisible || _sentences.isEmpty) return null;
    return _sentences[currentSentenceIndex];
  }

  int get currentParagraphIndex => activeSentence?.paragraphIndex ?? 0;

  bool get canGoPreviousSentence => currentSentenceIndex > 0;
  bool get canGoNextSentence =>
      _sentences.isNotEmpty && currentSentenceIndex < _sentences.length - 1;

  bool get canGoPreviousParagraph => currentParagraphIndex > 0;
  bool get canGoNextParagraph =>
      paragraphs.isNotEmpty && currentParagraphIndex < paragraphs.length - 1;

  double get progressFraction {
    if (_mode == ArticleAudioMode.podcastAudio && _duration.inMilliseconds > 0) {
      return (_position.inMilliseconds / _duration.inMilliseconds)
          .clamp(0.0, 1.0);
    }
    if (_sentences.isEmpty) return 0.0;
    return ((currentSentenceIndex + 1) / _sentences.length).clamp(0.0, 1.0);
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _attachPodcastListeners() {
    _posSub = _podcastPlayer.onPositionChanged.listen((pos) {
      if (_isDisposed || _mode != ArticleAudioMode.podcastAudio) return;
      _position = pos;
      positionNotifier.value = pos;
      final mapped = _sentenceIndexForPosition(pos);
      if (mapped != _currentSentenceIndex) {
        _currentSentenceIndex = mapped;
        // Yalnızca aktif cümle değiştiğinde makale metnini yeniden çiz;
        // her 200 ms konum güncellemesinde ana UI iş parçacığını yorma.
        _safeNotify();
      }
    });

    _durSub = _podcastPlayer.onDurationChanged.listen((dur) {
      if (_isDisposed || _mode != ArticleAudioMode.podcastAudio) return;
      if (dur.inMilliseconds > 0) {
        _duration = dur;
        _safeNotify();
      }
    });

    _completeSub = _podcastPlayer.onPlayerComplete.listen((_) {
      if (_isDisposed || _mode != ArticleAudioMode.podcastAudio) return;
      _isPlaying = false;
      _position = _duration;
      positionNotifier.value = _duration;
      if (_sentences.isNotEmpty) {
        _currentSentenceIndex = _sentences.length - 1;
      }
      _safeNotify();
    });
  }

  /// AppBar'daki kulaklık butonuna basıldığında oynatıcıyı açar/kapatır.
  /// Açıldığında otomatik başlatmaz; kullanıcı alttaki Oynat (Play) tuşuna
  /// bastığında okuma başlar.
  Future<void> togglePlayerVisibility() async {
    if (!hasPlayableContent) return;
    if (_isVisible) {
      await closePlayer();
      return;
    }
    _isVisible = true;
    _statusNotice = null;
    _safeNotify();
  }

  Future<void> closePlayer() async {
    await stop();
    _isVisible = false;
    _statusNotice = null;
    _safeNotify();
  }

  Future<void> togglePlayPause() async {
    if (!hasPlayableContent) return;
    if (!_isVisible) {
      _isVisible = true;
    }
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (!hasPlayableContent || _isDisposed) return;
    _statusNotice = null;

    if (_mode == ArticleAudioMode.podcastAudio && article.hasPodcastAudio) {
      final started = await _playPodcastAudio();
      if (started) return;
      // Podcast dosyası indirilemez/çalamazsa sessizce cihaz TTS yedeğine geç.
      _mode = ArticleAudioMode.deviceTts;
      _statusNotice =
          'Podcast sesi şu an açılamadı; cihaz sesiyle devam ediliyor.';
      _safeNotify();
    }

    await _playDeviceTtsAt(_currentSentenceIndex);
  }

  Future<void> pause() async {
    if (_isDisposed) return;
    _isPlaying = false;
    _isLoading = false;
    if (_mode == ArticleAudioMode.podcastAudio) {
      try {
        await _podcastPlayer.pause();
      } catch (_) {}
    } else {
      _ttsGeneration++;
      await _ttsEngine.stop();
    }
    _safeNotify();
  }

  Future<void> stop() async {
    if (_isDisposed) return;
    _isPlaying = false;
    _isLoading = false;
    _ttsGeneration++;
    await _ttsEngine.stop();
    try {
      await _podcastPlayer.stop();
    } catch (_) {}
    _podcastLoaded = false;
    _hasAppliedCustomRate = false;
    _position = Duration.zero;
    positionNotifier.value = Duration.zero;
    _currentSentenceIndex = 0;
    _safeNotify();
  }

  /// Bir önceki cümleye atlar (oynuyorsa anında o cümleden devam eder).
  Future<void> previousSentence() async {
    if (_sentences.isEmpty) return;
    final target = (currentSentenceIndex - 1).clamp(0, _sentences.length - 1);
    await jumpToSentence(target);
  }

  /// Bir sonraki cümleye atlar.
  Future<void> nextSentence() async {
    if (_sentences.isEmpty) return;
    final target = (currentSentenceIndex + 1).clamp(0, _sentences.length - 1);
    await jumpToSentence(target);
  }

  /// Bir önceki paragrafın ilk cümlesine atlar.
  Future<void> previousParagraph() async {
    if (_sentences.isEmpty) return;
    final currentP = currentParagraphIndex;
    // Paragrafın ortasındaysak önce o paragrafın başına dön, zaten başındaysak
    // bir önceki paragrafın başına geç (klasik sesli kitap davranışı).
    final firstOfCurrent = _firstSentenceIndexOfParagraph(currentP);
    if (firstOfCurrent != null && currentSentenceIndex > firstOfCurrent) {
      await jumpToSentence(firstOfCurrent);
      return;
    }
    for (var pIdx = currentP - 1; pIdx >= 0; pIdx--) {
      final target = _firstSentenceIndexOfParagraph(pIdx);
      if (target != null) {
        await jumpToSentence(target);
        return;
      }
    }
  }

  /// Bir sonraki paragrafın ilk cümlesine atlar.
  Future<void> nextParagraph() async {
    if (_sentences.isEmpty) return;
    final currentP = currentParagraphIndex;
    for (var pIdx = currentP + 1; pIdx < paragraphs.length; pIdx++) {
      final target = _firstSentenceIndexOfParagraph(pIdx);
      if (target != null) {
        await jumpToSentence(target);
        return;
      }
    }
  }

  Future<void> jumpToSentence(int sentenceIndex) async {
    if (_sentences.isEmpty || _isDisposed) return;
    final clamped = sentenceIndex.clamp(0, _sentences.length - 1);
    final wasPlaying = _isPlaying;
    _currentSentenceIndex = clamped;

    if (_mode == ArticleAudioMode.podcastAudio) {
      final targetMs = _startMsForSentence(clamped);
      final targetDuration = Duration(milliseconds: targetMs);
      _position = targetDuration;
      positionNotifier.value = targetDuration;
      _safeNotify();
      if (_podcastLoaded) {
        try {
          await _podcastPlayer.seek(targetDuration);
          if (wasPlaying) {
            await _podcastPlayer.resume();
          }
        } catch (_) {}
      } else if (wasPlaying) {
        await play();
      }
      return;
    }

    _safeNotify();
    if (wasPlaying) {
      await _playDeviceTtsAt(clamped);
    }
  }

  /// Okuma hızını sıradaki değere geçirir: `0.75x → 1.0x → 1.25x → 1.5x`.
  Future<void> cycleSpeed() async {
    final idx = speedOptions.indexOf(_playbackSpeed);
    final next = speedOptions[(idx + 1) % speedOptions.length];
    await setPlaybackSpeed(next);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    _safeNotify();

    if (_mode == ArticleAudioMode.podcastAudio) {
      if (_podcastLoaded) {
        final shouldCallRate = speed != 1.0 || _hasAppliedCustomRate;
        if (shouldCallRate) {
          try {
            await _podcastPlayer.setPlaybackRate(speed);
            _hasAppliedCustomRate = speed != 1.0;
          } catch (_) {}
        }
      }
      return;
    }

    await _ttsEngine.setSpeechRate(_mapSpeedToFlutterTtsRate(speed));
    if (_isPlaying) {
      await _playDeviceTtsAt(_currentSentenceIndex);
    }
  }

  /// Cihaz TTS modunda Amerikan (`en-US`) ve İngiliz (`en-GB`) aksanlarını değiştirir.
  Future<void> toggleAccent() async {
    _accent = _accent == ArticleTtsAccent.us
        ? ArticleTtsAccent.uk
        : ArticleTtsAccent.us;
    _safeNotify();

    if (_mode == ArticleAudioMode.deviceTts) {
      await _ttsEngine.setLanguage(_accent.localeCode);
      if (_isPlaying) {
        await _playDeviceTtsAt(_currentSentenceIndex);
      }
    }
  }

  /// Podcast ses dosyası olan makalelerde kullanıcı isterse Podcast AI ↔ Cihaz
  /// Sesi arasında geçiş yapabilir.
  Future<void> toggleEngineMode() async {
    if (!article.hasPodcastAudio || _isDisposed) return;
    final wasPlaying = _isPlaying || _isLoading;
    final savedSentence = currentSentenceIndex;
    final switchingFromPodcast = _mode == ArticleAudioMode.podcastAudio;

    _isPlaying = false;
    _isLoading = false;
    _ttsGeneration++;

    if (switchingFromPodcast) {
      // Podcast'ten Cihaz Sesi'ne geçerken sadece pause() değil stop() çağır;
      // böylece Android MediaPlayer ses odağını (AudioFocus) tamamen bırakır
      // ve FlutterTts sessiz kalmadan konuşabilir.
      try {
        await _podcastPlayer.stop();
      } catch (_) {}
      _podcastLoaded = false;
      _hasAppliedCustomRate = false;
    } else {
      await _ttsEngine.stop();
    }

    _mode = switchingFromPodcast
        ? ArticleAudioMode.deviceTts
        : ArticleAudioMode.podcastAudio;
    _statusNotice = null;
    _currentSentenceIndex = savedSentence;
    if (_mode == ArticleAudioMode.podcastAudio) {
      final startMs = _startMsForSentence(savedSentence);
      final targetPos = Duration(milliseconds: startMs);
      _position = targetPos;
      positionNotifier.value = targetPos;
    }
    _safeNotify();

    if (wasPlaying) {
      if (_mode == ArticleAudioMode.deviceTts) {
        await _playDeviceTtsAt(savedSentence);
      } else {
        await play();
      }
    }
  }

  int? _firstSentenceIndexOfParagraph(int paragraphIndex) {
    for (var i = 0; i < _sentences.length; i++) {
      if (_sentences[i].paragraphIndex == paragraphIndex) {
        return i;
      }
    }
    return null;
  }

  double _mapSpeedToFlutterTtsRate(double speed) {
    // flutter_tts Android'de 0.48 doğal 1.0x hızına karşılık gelir.
    return (0.48 * speed).clamp(0.28, 0.85);
  }

  Future<bool> _playPodcastAudio() async {
    final rawUrl = article.audioUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return false;

    try {
      if (!_podcastLoaded) {
        _isLoading = true;
        _safeNotify();

        final localPath = await _resolvePodcastLocalFile(rawUrl);
        if (_isDisposed) return false;

        if (localPath != null && localPath.isNotEmpty) {
          try {
            await _podcastPlayer.setSourceFile(localPath);
          } catch (_) {
            // Bozuk yerel dosya oynatılamadıysa önbellekten sil.
            try {
              final f = File(localPath);
              if (await f.exists()) await f.delete();
            } catch (_) {}
            rethrow;
          }
        } else {
          final candidates = _candidateAudioUrls(rawUrl);
          Object? lastErr;
          var loadedUrl = false;
          for (final url in candidates) {
            try {
              await _podcastPlayer.setSourceUrl(url);
              loadedUrl = true;
              break;
            } catch (err) {
              lastErr = err;
            }
          }
          if (!loadedUrl) {
            throw lastErr ?? Exception('Podcast audio could not be loaded');
          }
        }

        _podcastLoaded = true;
        // Android MediaPlayer'da 1.0x hızında setPlaybackRate çağırmak yazılımsal
        // Sonic DSP yeniden örneklemeyi tetikleyip cızırtı/kesinti yapabilir;
        // yalnızca 1.0x dışı bir hız seçildiyse uygula.
        if (_playbackSpeed != 1.0) {
          await _podcastPlayer.setPlaybackRate(_playbackSpeed);
          _hasAppliedCustomRate = true;
        } else {
          _hasAppliedCustomRate = false;
        }
      }

      final startMs = _startMsForSentence(currentSentenceIndex);
      if (startMs > 0 || _position.inMilliseconds > 0) {
        final seekTarget = _position.inMilliseconds > 0 &&
                _sentenceIndexForPosition(_position) == currentSentenceIndex
            ? _position
            : Duration(milliseconds: startMs);
        await _podcastPlayer.seek(seekTarget);
      }

      _isLoading = false;
      _isPlaying = true;
      _safeNotify();
      await _podcastPlayer.resume();
      return true;
    } catch (error) {
      debugPrint('[ArticleAudioController] Podcast ses hatasi: $error');
      _isLoading = false;
      _isPlaying = false;
      _podcastLoaded = false;
      _safeNotify();
      return false;
    }
  }

  String _resolveAbsoluteAudioUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final cleanRel = trimmed.replaceFirst(RegExp(r'^/+'), '');
    return 'https://line-reader.pages.dev/$cleanRel';
  }

  List<String> _candidateAudioUrls(String rawUrl) {
    final primary = _resolveAbsoluteAudioUrl(rawUrl);
    final urls = <String>[primary];
    // Cloudflare Pages henüz yayınlamadıysa veya mobil operatör engellediyse
    // GitHub raw `content/audio/...` (ve kök) yedek adreslerini dene.
    const pagesPrefix = 'https://line-reader.pages.dev/';
    if (primary.startsWith(pagesPrefix)) {
      final relPath = primary.substring(pagesPrefix.length);
      final rawBase = ApiConfig.articlesGithubFallbackJsonUrl
          .replaceFirst(RegExp(r'/articles\.json$'), '');
      if (!relPath.startsWith('content/')) {
        urls.add('$rawBase/content/$relPath');
      }
      urls.add('$rawBase/$relPath');
    }
    return urls;
  }

  /// İndirilen veya önbellekteki baytların gerçekten geçerli bir ses dosyası
  /// (M4A/MP4 `ftyp`, WAV `RIFF`, MP3 `ID3`/sync) olduğunu doğrular;
  /// Cloudflare Pages SPA fallback'inin döndürdüğü `200 text/html` sayfalarını
  /// kesin olarak reddeder.
  static bool isValidAudioBytes(List<int> bytes, {String? contentType}) {
    if (bytes.length < 1024) return false;
    final ct = (contentType ?? '').toLowerCase();
    if (ct.contains('text/html') ||
        ct.contains('application/json') ||
        ct.contains('text/plain') ||
        ct.contains('application/xml')) {
      return false;
    }
    // HTML / metin başlangıç kontrolü (`<!DOCTYPE`, `<html`, `{`)
    var firstNonWs = 0;
    while (firstNonWs < bytes.length &&
        firstNonWs < 32 &&
        (bytes[firstNonWs] == 0x20 ||
            bytes[firstNonWs] == 0x09 ||
            bytes[firstNonWs] == 0x0A ||
            bytes[firstNonWs] == 0x0D ||
            bytes[firstNonWs] == 0xEF ||
            bytes[firstNonWs] == 0xBB ||
            bytes[firstNonWs] == 0xBF)) {
      firstNonWs++;
    }
    if (firstNonWs < bytes.length && bytes[firstNonWs] == 0x3C /* '<' */) {
      return false;
    }
    // M4A / MP4 container: offset 4..7 == 'ftyp'
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return true;
    }
    // WAV container: 'RIFF'
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return true;
    }
    // MP3 ID3 tag veya MPEG frame sync (0xFF 0xE0+)
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return true;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return true;
    }
    // OGG ('OggS')
    if (bytes.length >= 4 &&
        bytes[0] == 0x4F &&
        bytes[1] == 0x67 &&
        bytes[2] == 0x67 &&
        bytes[3] == 0x53) {
      return true;
    }
    return false;
  }

  Future<bool> _isValidCachedAudioFile(File file) async {
    try {
      if (!await file.exists()) return false;
      final len = await file.length();
      if (len < 1024) return false;
      final raf = await file.open();
      try {
        final header = await raf.read(32);
        // Header + minimum boyut bilgisini doğrulamak için sentetik uzunluk yerine
        // header'ı kontrol ediyoruz.
        final padded = List<int>.filled(1024, 0);
        for (var i = 0; i < header.length && i < padded.length; i++) {
          padded[i] = header[i];
        }
        return isValidAudioBytes(padded);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolvePodcastLocalFile(String rawUrl) async {
    final customResolver = _audioFileResolver;
    if (customResolver != null) {
      return customResolver(rawUrl);
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'article_audio'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final safeId = article.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final lowerUrl = rawUrl.toLowerCase();
      final ext = lowerUrl.endsWith('.wav')
          ? '.wav'
          : (lowerUrl.endsWith('.mp3') ? '.mp3' : '.m4a');
      final cacheFile = File(p.join(cacheDir.path, '$safeId$ext'));
      if (await cacheFile.exists()) {
        if (await _isValidCachedAudioFile(cacheFile)) {
          try {
            await cacheFile.setLastModified(DateTime.now());
          } catch (_) {}
          return cacheFile.path;
        }
        // Önceden bozuk/HTML önbellek yazılmışsa temizle ve yeniden indir.
        try {
          await cacheFile.delete();
        } catch (_) {}
      }

      for (final url in _candidateAudioUrls(rawUrl)) {
        try {
          final response = await _httpClient
              .get(
                Uri.parse(url),
                headers: const <String, String>{'User-Agent': 'LineReaderApp'},
              )
              .timeout(const Duration(seconds: 20));
          final ct = response.headers['content-type'];
          if (response.statusCode == 200 &&
              isValidAudioBytes(response.bodyBytes, contentType: ct)) {
            await cacheFile.writeAsBytes(response.bodyBytes, flush: true);
            unawaited(_pruneAudioCache(cacheDir, maxFiles: 8));
            return cacheFile.path;
          }
        } catch (_) {
          // Sonraki yedek URL'yi dene.
        }
      }
    } catch (error) {
      debugPrint('[ArticleAudioController] Yerel ses onbellek hatasi: $error');
    }
    return null;
  }

  /// Podcast ses önbelleğinin telefon hafızasını şişirmemesi için yalnızca
  /// en son dinlenen [maxFiles] makalenin ses dosyasını tutar.
  Future<void> _pruneAudioCache(Directory cacheDir, {int maxFiles = 8}) async {
    try {
      final files = <File>[];
      await for (final entity in cacheDir.list()) {
        if (entity is File) {
          files.add(entity);
        }
      }
      if (files.length <= maxFiles) return;

      final withTime = <({File file, DateTime modified})>[];
      for (final file in files) {
        try {
          withTime.add((file: file, modified: await file.lastModified()));
        } catch (_) {}
      }
      withTime.sort((a, b) => b.modified.compareTo(a.modified));

      for (final entry in withTime.skip(maxFiles)) {
        try {
          await entry.file.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _playDeviceTtsAt(int sentenceIndex) async {
    if (_sentences.isEmpty || _isDisposed) return;
    final clamped = sentenceIndex.clamp(0, _sentences.length - 1);
    final myGen = ++_ttsGeneration;
    _currentSentenceIndex = clamped;
    _isLoading = false;
    _isPlaying = true;
    _safeNotify();

    try {
      await _ttsEngine.configure(
        language: _accent.localeCode,
        speechRate: _mapSpeedToFlutterTtsRate(_playbackSpeed),
        onCompleted: () => _handleTtsSentenceCompleted(myGen),
        onError: (msg) {
          if (_isDisposed || myGen != _ttsGeneration) return;
          _isPlaying = false;
          _statusNotice = 'Sesli okuma motoru başlatılamadı.';
          _safeNotify();
        },
      );
      if (_ttsConfigured) {
        await _ttsEngine.stop();
      }
      _ttsConfigured = true;

      if (_isDisposed || myGen != _ttsGeneration) return;
      final spoken = await _ttsEngine.speak(_sentences[clamped].text);
      if (!spoken && !_isDisposed && myGen == _ttsGeneration) {
        _isPlaying = false;
        _statusNotice =
            'Cihaz ses motoru başlatılamadı. Tekrar Oynat tuşuna basın.';
        _safeNotify();
      }
    } catch (error) {
      debugPrint('[ArticleAudioController] TTS okuma hatasi: $error');
      if (_isDisposed || myGen != _ttsGeneration) return;
      _isPlaying = false;
      _statusNotice = 'Cihaz ses motoru kullanılamadı.';
      _safeNotify();
    }
  }

  void _handleTtsSentenceCompleted(int generation) {
    if (_isDisposed ||
        generation != _ttsGeneration ||
        !_isPlaying ||
        _mode != ArticleAudioMode.deviceTts) {
      return;
    }

    if (_currentSentenceIndex + 1 < _sentences.length) {
      _playDeviceTtsAt(_currentSentenceIndex + 1);
    } else {
      _isPlaying = false;
      _safeNotify();
    }
  }

  /// Verilen cümle indeksi için Podcast ses dosyasındaki başlangıç milisaniyesini
  /// döndürür (önce `audioSegments`, yoksa karakter uzunluğuna göre orantılı).
  int _startMsForSentence(int sentenceIndex) {
    if (_sentences.isEmpty) return 0;
    final clamped = sentenceIndex.clamp(0, _sentences.length - 1);

    final segments = article.audioSegments;
    if (segments.isNotEmpty) {
      for (final seg in segments) {
        if (seg.sentenceIndex == clamped) {
          return seg.startMs;
        }
      }
      if (clamped < segments.length) {
        return segments[clamped].startMs;
      }
    }

    final totalMs = _duration.inMilliseconds;
    if (totalMs <= 0) return 0;

    var totalChars = 0;
    var charsBefore = 0;
    for (var i = 0; i < _sentences.length; i++) {
      final weight = _sentences[i].text.length + 6;
      if (i < clamped) charsBefore += weight;
      totalChars += weight;
    }
    if (totalChars <= 0) return 0;
    return ((charsBefore / totalChars) * totalMs).round();
  }

  int _sentenceIndexForPosition(Duration pos) {
    if (_sentences.isEmpty) return 0;
    final ms = pos.inMilliseconds;

    final segments = article.audioSegments;
    if (segments.isNotEmpty) {
      var matched = 0;
      for (var i = 0; i < segments.length; i++) {
        final seg = segments[i];
        if (ms >= seg.startMs) {
          matched = seg.sentenceIndex;
        }
        if (ms >= seg.startMs && ms < seg.endMs) {
          return seg.sentenceIndex.clamp(0, _sentences.length - 1);
        }
      }
      return matched.clamp(0, _sentences.length - 1);
    }

    final totalMs = _duration.inMilliseconds;
    if (totalMs <= 0) return _currentSentenceIndex;

    var totalChars = 0;
    for (final s in _sentences) {
      totalChars += s.text.length + 6;
    }
    if (totalChars <= 0) return 0;

    final targetChar = (ms / totalMs).clamp(0.0, 1.0) * totalChars;
    var acc = 0;
    for (var i = 0; i < _sentences.length; i++) {
      acc += _sentences[i].text.length + 6;
      if (acc >= targetChar) {
        return i;
      }
    }
    return _sentences.length - 1;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _ttsGeneration++;
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    positionNotifier.dispose();
    _ttsEngine.dispose();
    _podcastPlayer.dispose();
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }
}
