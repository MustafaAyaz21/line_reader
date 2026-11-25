import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/articles/controllers/article_reading_progress_controller.dart';
import '../../features/articles/models/article_reading_progress.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/words/data/word_repository.dart';
import '../config/api_config.dart';
import '../database/app_database.dart';
import '../settings/settings_repository.dart';
import '../theme/app_theme_controller.dart';
import '../theme/app_theme_preset.dart';

/// Kullanıcının kelimelerini, kelime listelerini, okuma ilerlemesini ve
/// seçili temasını Cloudflare D1 veritabanı ile çift yönlü senkronize eden servis.
class CloudSyncService {
  CloudSyncService({
    http.Client? httpClient,
    AuthController? authController,
    WordRepository? wordRepository,
    SettingsRepository? settingsRepository,
  })  : _httpClient = httpClient ?? http.Client(),
        _authController = authController,
        _wordRepository = wordRepository ?? WordRepository(AppDatabase.instance),
        _settingsRepository =
            settingsRepository ?? SettingsRepository(AppDatabase.instance);

  static final CloudSyncService shared = CloudSyncService();

  final http.Client _httpClient;
  AuthController? _authController;
  final WordRepository _wordRepository;
  final SettingsRepository _settingsRepository;

  bool _isSyncing = false;
  bool _pendingSyncAfterCurrent = false;
  bool _isApplyingRemoteTheme = false;
  bool _themeListenerAttached = false;
  String? _lastSyncedUid;
  String? _preferredBaseUrl;
  Timer? _debounceTimer;
  VoidCallback? onSyncCompleted;

  void configure({
    required AuthController authController,
    VoidCallback? onSyncCompleted,
  }) {
    if (_authController != authController) {
      _authController?.removeListener(_onAuthChanged);
      _authController = authController;
      _authController?.addListener(_onAuthChanged);
    }
    if (onSyncCompleted != null) {
      this.onSyncCompleted = onSyncCompleted;
    }
    if (!_themeListenerAttached) {
      _themeListenerAttached = true;
      AppThemeController.shared.addListener(_onThemeChanged);
    }
    // Eğer oturum configure anında zaten hazırsa hemen senkronize et.
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final auth = _authController;
    if (auth == null || !auth.isAuthenticated) {
      _lastSyncedUid = null;
      return;
    }
    final uid = auth.user?.uid;
    if (uid != null && uid.isNotEmpty && uid != _lastSyncedUid) {
      _lastSyncedUid = uid;
      unawaited(syncNow());
    }
  }

  void _onThemeChanged() {
    if (_isApplyingRemoteTheme) return;
    // Sistem tarafından zorlanan (updateTimestamp: false) fallback değişikliklerini
    // buluta kullanıcı seçimi gibi göndermiyoruz.
    if (AppThemeController.shared.themeUpdatedAtIso == null) return;
    scheduleSync();
  }

  /// Yerel veriler (tema, kelimeler, ilerleme) değiştiğinde buluta
  /// yükleme işlemini kısa bir gecikmeyle (debounce) güvenle tetikler.
  void scheduleSync({Duration delay = const Duration(milliseconds: 900)}) {
    final auth = _authController;
    if (auth == null || !auth.isAuthenticated) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      unawaited(syncNow());
    });
  }

  List<String> _orderedBaseUrls() {
    final urls = <String>[];
    void addIfValid(String? raw) {
      final cleaned = (raw ?? '').trim().replaceFirst(RegExp(r'/+$'), '');
      if (cleaned.startsWith('http') && !urls.contains(cleaned)) {
        urls.add(cleaned);
      }
    }

    addIfValid(_preferredBaseUrl);
    // 1) Aynı origin / Cloudflare Pages /api proxy (Web'de CORS sorunsuz, mobilde operatör engeli yok)
    addIfValid(ApiConfig.browserAiFallbackEndpoint);
    // 2) Doğrudan Cloudflare Worker adresi
    addIfValid(ApiConfig.browserAiTranslateEndpoint);
    // 3) Netlify proxy yedeği
    addIfValid(ApiConfig.browserAiSecondaryFallbackEndpoint);
    return urls;
  }

  Future<({String baseUrl, http.Response response})?> _requestWithFallback({
    required String method,
    required String token,
    String? body,
  }) async {
    final urls = _orderedBaseUrls();
    for (final base in urls) {
      final uri = Uri.parse('$base/sync');
      try {
        final headers = <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json',
        };
        final res = method == 'GET'
            ? await _httpClient
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 10))
            : await _httpClient
                .post(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 10));

        // 401 ise token süresi dolmuş olabilir — üst katmana bildir
        if (res.statusCode == 401) {
          return (baseUrl: base, response: res);
        }

        // 200 ve geçerli JSON ise bu uç nokta sağlıklıdır
        if (res.statusCode == 200) {
          final trimmed = res.body.trimLeft();
          if (trimmed.startsWith('{')) {
            _preferredBaseUrl = base;
            return (baseUrl: base, response: res);
          }
        }
        debugPrint(
          '[CloudSyncService] $method $uri beklenmedik yanit: '
          'status=${res.statusCode}',
        );
      } catch (err) {
        debugPrint('[CloudSyncService] $method $uri erisim hatasi: $err');
      }
    }
    return null;
  }

  /// Kullanıcı oturum açtığında, uygulamaya girdiğinde veya veri değiştiğinde çağrılır.
  /// 1) Sunucudan güncel verileri çeker ve yerel veritabanına birleştirir.
  /// 2) Yerel güncel durumu paketleyip sunucuya yükler.
  Future<bool> syncNow({bool force = false}) async {
    final auth = _authController;
    if (auth == null || !auth.isAuthenticated) {
      return false;
    }
    if (_isSyncing) {
      _pendingSyncAfterCurrent = true;
      return false;
    }

    _isSyncing = true;
    try {
      // Yerel tema ve ilerleme durumu yüklenmeden senkronizasyona başlama
      await AppThemeController.shared.load();
      await ArticleReadingProgressController.shared.load();

      var token = await auth.getIdToken();
      if (token == null || token.isEmpty) {
        token = await auth.getIdToken(forceRefresh: true);
      }
      if (token == null || token.isEmpty) return false;

      // 1) Önce sunucudaki mevcut bulut kaydını çek
      var getResult = await _requestWithFallback(method: 'GET', token: token);
      if (getResult != null && getResult.response.statusCode == 401) {
        final refreshed = await auth.getIdToken(forceRefresh: true);
        if (refreshed != null && refreshed.isNotEmpty) {
          token = refreshed;
          getResult = await _requestWithFallback(method: 'GET', token: token);
        }
      }
      if (getResult == null || getResult.response.statusCode != 200) {
        return false;
      }

      Map<String, dynamic>? remoteData;
      try {
        final decoded = jsonDecode(getResult.response.body);
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          remoteData = decoded;
        }
      } catch (_) {}

      // Sunucudan gelen verileri yerel depoya birleştir (merge)
      if (remoteData != null && remoteData['exists'] == true) {
        await _applyRemoteToLocal(remoteData);
      }

      // 2) Yerel güncel durumu paketleyip sunucuya gönder
      final localPayload = await _buildLocalPayload();
      final postResult = await _requestWithFallback(
        method: 'POST',
        token: token,
        body: jsonEncode(localPayload),
      );

      final success =
          postResult != null && postResult.response.statusCode == 200;
      debugPrint(
        '[CloudSyncService] Sync tamamlandi: ok=$success '
        '(endpoint=${postResult?.baseUrl ?? getResult.baseUrl})',
      );
      return success;
    } catch (err) {
      debugPrint('[CloudSyncService] Senkronizasyon hatasi: $err');
      return false;
    } finally {
      _isSyncing = false;
      if (_pendingSyncAfterCurrent) {
        _pendingSyncAfterCurrent = false;
        unawaited(syncNow());
      }
    }
  }

  Future<void> _applyRemoteToLocal(Map<String, dynamic> remote) async {
    try {
      // A) Temayı senkronize et (zaman damgası karşılaştırmasıyla)
      final prefs = remote['preferences'];
      if (prefs is Map) {
        final themeKey = prefs['theme'] as String?;
        final remoteUpdatedAtStr = prefs['theme_updated_at'] as String?;
        if (themeKey != null && themeKey.isNotEmpty) {
          final preset = AppThemePreset.fromStorageKey(themeKey);
          if (preset != null) {
            final localUpdatedAtStr = AppThemeController.shared.themeUpdatedAtIso ??
                await _settingsRepository.getString('app_theme_updated_at');
            final localUpdatedAt = localUpdatedAtStr != null
                ? DateTime.tryParse(localUpdatedAtStr)
                : null;
            final remoteUpdatedAt = remoteUpdatedAtStr != null
                ? DateTime.tryParse(remoteUpdatedAtStr)
                : null;

            final shouldApply = localUpdatedAt == null ||
                (remoteUpdatedAt != null &&
                    remoteUpdatedAt.isAfter(localUpdatedAt));

            if (shouldApply) {
              _isApplyingRemoteTheme = true;
              try {
                await AppThemeController.shared.setPreset(
                  preset,
                  updateTimestamp: false,
                  overrideTimestampIso:
                      remoteUpdatedAtStr ?? DateTime.now().toUtc().toIso8601String(),
                );
              } finally {
                _isApplyingRemoteTheme = false;
              }
            }
          }
        }
      }

      // B) Okuma ilerlemesini senkronize et
      final readingProg = remote['reading_progress'];
      if (readingProg is Map) {
        final controller = ArticleReadingProgressController.shared;
        for (final entry in readingProg.entries) {
          final parsed = ArticleReadingProgress.fromJson(entry.value);
          if (parsed != null) {
            await controller.mergeFromRemote(parsed);
          }
        }
      }

      // C) Kelimeleri senkronize et
      final wordsList = remote['saved_words'];
      if (wordsList is List) {
        final defaultListId = await _wordRepository.getDefaultFavoritesListId();
        for (final item in wordsList) {
          if (item is Map) {
            final word = (item['word'] as String? ?? '').trim();
            final meaning = (item['meaning'] as String? ?? '').trim();
            if (word.isNotEmpty && meaning.isNotEmpty) {
              await _wordRepository.saveWord(
                listId: defaultListId,
                word: word,
                meaning: meaning,
                ipaUs: item['ipa_us'] as String?,
                ipaUk: item['ipa_uk'] as String?,
              );
            }
          }
        }
      }
      onSyncCompleted?.call();
    } catch (e) {
      debugPrint('[CloudSyncService] Remote merge hatasi: $e');
    }
  }

  Future<Map<String, dynamic>> _buildLocalPayload() async {
    // 1) Kelimeler (tüm listelerdeki kelimeleri topla)
    final allLists = await _wordRepository.getAllLists();
    final wordsJson = <Map<String, dynamic>>[];
    for (final list in allLists) {
      if (list.id != null) {
        final listWords = await _wordRepository.getWordsByList(list.id!);
        for (final w in listWords) {
          wordsJson.add(<String, dynamic>{
            'word': w.word,
            'meaning': w.meaning,
            'ipa_us': w.ipaUs,
            'ipa_uk': w.ipaUk,
            'created_at': w.createdAt.toIso8601String(),
          });
        }
      }
    }

    // 2) Kelime Listeleri
    final listsJson = allLists
        .map((l) => <String, dynamic>{
              'id': l.id,
              'name': l.name,
              'color_value': l.colorValue,
              'is_default': l.isDefault,
            })
        .toList(growable: false);

    // 3) Okuma ilerlemeleri
    final progressCtrl = ArticleReadingProgressController.shared;
    final progressMap = <String, dynamic>{};
    final lastProg = progressCtrl.lastProgress;
    if (lastProg != null) {
      progressMap[lastProg.articleId] = lastProg.toJson();
    }

    // 4) Tercihler (Tema vb.)
    // Yerel cihaz hiç tema seçmemişse sahte "şimdi" tarihi üretme;
    // null bırak ki diğer cihazın gerçek tema seçimi ezilmesin.
    final themeUpdatedAt = AppThemeController.shared.themeUpdatedAtIso ??
        await _settingsRepository.getString('app_theme_updated_at');
    final prefsMap = <String, dynamic>{
      'theme': AppThemeController.shared.preset.storageKey,
      if (themeUpdatedAt != null) 'theme_updated_at': themeUpdatedAt,
    };

    return <String, dynamic>{
      'saved_words': wordsJson,
      'word_lists': listsJson,
      'reading_progress': progressMap,
      'preferences': prefsMap,
    };
  }
}
