import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/articles/controllers/article_reading_progress_controller.dart';
import '../../features/articles/models/article_reading_progress.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/words/data/word_repository.dart';
import '../../features/words/models/saved_word.dart';
import '../../features/words/models/word_list.dart';
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
  bool _isApplyingRemoteTheme = false;
  bool _listenersAttached = false;
  Timer? _debounceTimer;
  VoidCallback? onSyncCompleted;

  void configure({
    required AuthController authController,
    VoidCallback? onSyncCompleted,
  }) {
    _authController = authController;
    if (onSyncCompleted != null) {
      this.onSyncCompleted = onSyncCompleted;
    }
    if (!_listenersAttached) {
      _listenersAttached = true;
      AppThemeController.shared.addListener(_onThemeChanged);
    }
  }

  void _onThemeChanged() {
    if (_isApplyingRemoteTheme) return;
    scheduleSync();
  }

  /// Yerel veriler (tema, kelimeler, ilerleme) değiştiğinde buluta
  /// yükleme işlemini kısa bir gecikmeyle (debounce) güvenle tetikler.
  void scheduleSync({Duration delay = const Duration(milliseconds: 1200)}) {
    final auth = _authController;
    if (auth == null || !auth.isAuthenticated) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      syncNow();
    });
  }

  /// Kullanıcı oturum açtığında veya uygulamaya girdiğinde çağrılır.
  /// 1) Sunucudan güncel verileri çeker ve yerel veritabanına ekler.
  /// 2) Yerelde olup sunucuda olmayan yeni verileri sunucuya yükler.
  Future<bool> syncNow({bool force = false}) async {
    final auth = _authController;
    if (auth == null || !auth.isAuthenticated || _isSyncing) {
      return false;
    }

    _isSyncing = true;
    try {
      final token = await auth.getIdToken();
      if (token == null || token.isEmpty) return false;

      final syncUri = Uri.parse('${ApiConfig.browserAiTranslateEndpoint}/sync');

      // 1) Önce sunucudaki mevcut bulut kaydını çek
      final getRes = await _httpClient.get(
        syncUri,
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      Map<String, dynamic>? remoteData;
      if (getRes.statusCode == 200) {
        try {
          final decoded = jsonDecode(getRes.body);
          if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
            remoteData = decoded;
          }
        } catch (_) {}
      }

      // Sunucudan gelen verileri yerel depoya birleştir (merge)
      if (remoteData != null && remoteData['exists'] == true) {
        await _applyRemoteToLocal(remoteData);
      }

      // 2) Yerel güncel durumu paketleyip sunucuya gönder
      final localPayload = await _buildLocalPayload();
      final postRes = await _httpClient.post(
        syncUri,
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(localPayload),
      ).timeout(const Duration(seconds: 10));

      return postRes.statusCode == 200;
    } catch (err) {
      debugPrint('[CloudSyncService] Senkronizasyon hatasi: $err');
      return false;
    } finally {
      _isSyncing = false;
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
            final localUpdatedAtStr =
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

            if (shouldApply && AppThemeController.shared.preset != preset) {
              _isApplyingRemoteTheme = true;
              try {
                await AppThemeController.shared
                    .setPreset(preset, updateTimestamp: false);
                if (remoteUpdatedAtStr != null) {
                  await _settingsRepository.saveString(
                    'app_theme_updated_at',
                    remoteUpdatedAtStr,
                  );
                }
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
    final themeUpdatedAt =
        await _settingsRepository.getString('app_theme_updated_at') ??
            DateTime.now().toUtc().toIso8601String();
    final prefsMap = <String, dynamic>{
      'theme': AppThemeController.shared.preset.storageKey,
      'theme_updated_at': themeUpdatedAt,
    };

    return <String, dynamic>{
      'saved_words': wordsJson,
      'word_lists': listsJson,
      'reading_progress': progressMap,
      'preferences': prefsMap,
    };
  }
}
