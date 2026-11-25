import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/articles/controllers/article_reading_progress_controller.dart';
import '../../features/articles/models/article_reading_progress.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/words/data/word_repository.dart';
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

  static const String _deletedWordsKey = 'sync_deleted_words_v1';
  static const String _deletedListsKey = 'sync_deleted_lists_v1';
  static const Duration _tombstoneRetention = Duration(days: 30);

  final http.Client _httpClient;
  AuthController? _authController;
  final WordRepository _wordRepository;
  final SettingsRepository _settingsRepository;

  bool _isSyncing = false;
  bool _pendingSyncAfterCurrent = false;
  bool _isApplyingRemoteTheme = false;
  bool _themeListenerAttached = false;
  bool _isAppActive = true;
  String? _lastSyncedUid;
  String? _preferredBaseUrl;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
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
    _ensurePeriodicTimer();
    _onAuthChanged();
  }

  /// Uygulama ön plandayken periyodik hızlı senkronizasyonu açık tutar,
  /// arka plana geçince durdurur.
  void setAppActive(bool active) {
    _isAppActive = active;
    if (active) {
      _ensurePeriodicTimer();
    } else {
      _periodicTimer?.cancel();
      _periodicTimer = null;
    }
  }

  void _ensurePeriodicTimer() {
    if (!_isAppActive) return;
    _periodicTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      final auth = _authController;
      if (_isAppActive && auth != null && auth.isAuthenticated && !_isSyncing) {
        unawaited(syncNow());
      }
    });
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
    if (AppThemeController.shared.themeUpdatedAtIso == null) return;
    scheduleSync(delay: const Duration(milliseconds: 300));
  }

  static String _norm(String raw) =>
      raw.trim().replaceAll('İ', 'i').toLowerCase();

  static String _wordTombstoneKey(String listName, String word) =>
      '${_norm(listName)}::${_norm(word)}';

  Future<Map<String, String>> _loadTombstones(String key) async {
    try {
      final raw = await _settingsRepository.getString(key);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      final cutoff = DateTime.now().toUtc().subtract(_tombstoneRetention);
      final out = <String, String>{};
      for (final entry in decoded.entries) {
        final k = entry.key.toString();
        final v = entry.value?.toString() ?? '';
        final dt = DateTime.tryParse(v);
        if (dt != null && dt.isAfter(cutoff)) {
          out[k] = v;
        }
      }
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _saveTombstones(String key, Map<String, String> map) async {
    try {
      await _settingsRepository.saveString(key, jsonEncode(map));
    } catch (_) {}
  }

  /// Yerel bir kelime silindiğinde diğer cihazların kelimeyi geri getirmesini
  /// önlemek ve diğer cihazlardan da silmek için silme kaydı (tombstone) tutar.
  Future<void> recordDeletedWord({
    required String listName,
    required String word,
  }) async {
    final w = _norm(word);
    if (w.isEmpty) return;
    final l = listName.trim().isEmpty ? 'Favoriler' : listName;
    final map = await _loadTombstones(_deletedWordsKey);
    map[_wordTombstoneKey(l, w)] = DateTime.now().toUtc().toIso8601String();
    await _saveTombstones(_deletedWordsKey, map);
  }

  Future<void> clearDeletedWord({
    required String listName,
    required String word,
  }) async {
    final w = _norm(word);
    if (w.isEmpty) return;
    final l = listName.trim().isEmpty ? 'Favoriler' : listName;
    final map = await _loadTombstones(_deletedWordsKey);
    if (map.remove(_wordTombstoneKey(l, w)) != null) {
      await _saveTombstones(_deletedWordsKey, map);
    }
  }

  Future<void> recordDeletedList(String listName) async {
    final l = _norm(listName);
    if (l.isEmpty) return;
    final map = await _loadTombstones(_deletedListsKey);
    map[l] = DateTime.now().toUtc().toIso8601String();
    await _saveTombstones(_deletedListsKey, map);
  }

  Future<void> clearDeletedList(String listName) async {
    final l = _norm(listName);
    if (l.isEmpty) return;
    final map = await _loadTombstones(_deletedListsKey);
    if (map.remove(l) != null) {
      await _saveTombstones(_deletedListsKey, map);
    }
  }

  /// Yerel veriler (tema, kelimeler, listeler, ilerleme) değiştiğinde buluta
  /// yükleme işlemini kısa bir gecikmeyle (debounce) güvenle tetikler.
  void scheduleSync({Duration delay = const Duration(milliseconds: 250)}) {
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
    addIfValid(ApiConfig.browserAiFallbackEndpoint);
    addIfValid(ApiConfig.browserAiTranslateEndpoint);
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

        if (res.statusCode == 401) {
          return (baseUrl: base, response: res);
        }

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
  /// 1) Sunucudan güncel verileri çeker ve silme kayıtlarını (tombstone) dikkate alarak birleştirir.
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

  Map<String, String> _mergeTombstoneMaps(
    Map<String, String> local,
    Object? remoteRaw,
  ) {
    final merged = Map<String, String>.from(local);
    if (remoteRaw is Map) {
      final cutoff = DateTime.now().toUtc().subtract(_tombstoneRetention);
      for (final entry in remoteRaw.entries) {
        final k = entry.key.toString();
        final v = entry.value?.toString() ?? '';
        final remoteDt = DateTime.tryParse(v);
        if (remoteDt == null || !remoteDt.isAfter(cutoff)) continue;
        final localDt = DateTime.tryParse(merged[k] ?? '');
        if (localDt == null || remoteDt.isAfter(localDt)) {
          merged[k] = v;
        }
      }
    }
    return merged;
  }

  Future<void> _applyRemoteToLocal(Map<String, dynamic> remote) async {
    try {
      final prefs = remote['preferences'];

      // 0) Silme kayıtlarını (tombstone) birleştir
      final localDeletedWords = await _loadTombstones(_deletedWordsKey);
      final localDeletedLists = await _loadTombstones(_deletedListsKey);
      final mergedDeletedWords = _mergeTombstoneMaps(
        localDeletedWords,
        prefs is Map ? prefs['deleted_words'] : null,
      );
      final mergedDeletedLists = _mergeTombstoneMaps(
        localDeletedLists,
        prefs is Map ? prefs['deleted_lists'] : null,
      );
      await _saveTombstones(_deletedWordsKey, mergedDeletedWords);
      await _saveTombstones(_deletedListsKey, mergedDeletedLists);

      // A) Temayı senkronize et (zaman damgası karşılaştırmasıyla)
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

      // C) Kelime listelerini senkronize et (oluşturma, renk ve silme)
      var localLists = await _wordRepository.getAllLists();
      for (final localList in localLists) {
        if (localList.isDefault) continue;
        final deletedIso = mergedDeletedLists[_norm(localList.name)];
        final deletedAt =
            deletedIso != null ? DateTime.tryParse(deletedIso) : null;
        if (deletedAt != null &&
            !localList.createdAt.toUtc().isAfter(deletedAt)) {
          await _wordRepository.deleteList(localList.id);
        }
      }

      final remoteLists = remote['word_lists'];
      if (remoteLists is List) {
        localLists = await _wordRepository.getAllLists();
        final byNormName = <String, WordList>{
          for (final l in localLists) _norm(l.name): l,
        };
        for (final item in remoteLists) {
          if (item is! Map) continue;
          final name = (item['name'] as String? ?? '').trim();
          if (name.isEmpty) continue;
          final isDefault = item['is_default'] == true;
          final colorValue =
              (item['color_value'] as num?)?.toInt() ?? WordListColors.palette.first;
          final createdIso = item['created_at'] as String?;
          final remoteCreated =
              createdIso != null ? DateTime.tryParse(createdIso) : null;

          if (!isDefault) {
            final deletedIso = mergedDeletedLists[_norm(name)];
            final deletedAt =
                deletedIso != null ? DateTime.tryParse(deletedIso) : null;
            if (deletedAt != null &&
                (remoteCreated == null || !remoteCreated.isAfter(deletedAt))) {
              continue;
            }
          }

          final existing = isDefault
              ? localLists.where((l) => l.isDefault).firstOrNull
              : byNormName[_norm(name)];
          if (existing == null && !isDefault) {
            try {
              final created = await _wordRepository.createList(
                name: name,
                colorValue: colorValue,
              );
              byNormName[_norm(created.name)] = created;
            } catch (_) {}
          } else if (existing != null && existing.colorValue != colorValue) {
            try {
              await _wordRepository.updateList(
                id: existing.id,
                name: existing.name,
                colorValue: colorValue,
                isDefault: existing.isDefault,
              );
            } catch (_) {}
          }
        }
      }

      // D) Kelimeleri senkronize et (tüm listeler + silinenleri geri getirmeme + diğer cihazdan silme)
      localLists = await _wordRepository.getAllLists();
      final defaultListId = await _wordRepository.getDefaultFavoritesListId();
      final listIdByNormName = <String, int>{
        for (final l in localLists) _norm(l.name): l.id,
      };
      final listNameById = <int, String>{
        for (final l in localLists) l.id: l.name,
      };

      // D.1) Silinmiş kelimeleri yerelden temizle
      for (final list in localLists) {
        final listWords = await _wordRepository.getWordsByList(list.id);
        for (final w in listWords) {
          final tKey = _wordTombstoneKey(list.name, w.word);
          final deletedIso = mergedDeletedWords[tKey];
          final deletedAt =
              deletedIso != null ? DateTime.tryParse(deletedIso) : null;
          if (deletedAt != null && !w.createdAt.toUtc().isAfter(deletedAt)) {
            if (w.id != null) {
              await _wordRepository.deleteWord(w.id!);
            }
          }
        }
      }

      // D.2) Sunucudan gelen kelimeleri ilgili listelere ekle
      final wordsList = remote['saved_words'];
      if (wordsList is List) {
        for (final item in wordsList) {
          if (item is! Map) continue;
          final word = (item['word'] as String? ?? '').trim();
          final meaning = (item['meaning'] as String? ?? '').trim();
          if (word.isEmpty || meaning.isEmpty) continue;

          final rawListName = (item['list_name'] as String? ?? '').trim();
          final isDefaultWord = item['is_default'] == true;
          final resolvedListId = isDefaultWord || rawListName.isEmpty
              ? defaultListId
              : (listIdByNormName[_norm(rawListName)] ?? defaultListId);
          final resolvedListName =
              listNameById[resolvedListId] ?? 'Favoriler';

          final tKey = _wordTombstoneKey(resolvedListName, word);
          final deletedIso = mergedDeletedWords[tKey];
          final deletedAt =
              deletedIso != null ? DateTime.tryParse(deletedIso) : null;
          final createdIso = item['created_at'] as String?;
          final remoteCreated =
              createdIso != null ? DateTime.tryParse(createdIso) : null;

          // Bu kelime bu listeden silindiyse ve silinme tarihi eklenme tarihinden
          // yeni/eşitse ASLA geri getirme!
          if (deletedAt != null &&
              (remoteCreated == null || !remoteCreated.isAfter(deletedAt))) {
            continue;
          }

          await _wordRepository.saveWord(
            listId: resolvedListId,
            word: word,
            meaning: meaning,
            ipaUs: item['ipa_us'] as String?,
            ipaUk: item['ipa_uk'] as String?,
          );
        }
      }

      onSyncCompleted?.call();
    } catch (e) {
      debugPrint('[CloudSyncService] Remote merge hatasi: $e');
    }
  }

  Future<Map<String, dynamic>> _buildLocalPayload() async {
    // 1) Kelime Listeleri ve Kelimeler (her kelimede list_name ile)
    final allLists = await _wordRepository.getAllLists();
    final wordsJson = <Map<String, dynamic>>[];
    for (final list in allLists) {
      final listWords = await _wordRepository.getWordsByList(list.id);
      for (final w in listWords) {
        wordsJson.add(<String, dynamic>{
          'word': w.word,
          'meaning': w.meaning,
          'ipa_us': w.ipaUs,
          'ipa_uk': w.ipaUk,
          'list_name': list.name,
          'is_default': list.isDefault,
          'created_at': w.createdAt.toUtc().toIso8601String(),
        });
      }
    }

    final listsJson = allLists
        .map((l) => <String, dynamic>{
              'id': l.id,
              'name': l.name,
              'color_value': l.colorValue,
              'is_default': l.isDefault,
              'created_at': l.createdAt.toUtc().toIso8601String(),
            })
        .toList(growable: false);

    // 2) Tüm makale okuma & podcast ilerlemeleri
    final progressCtrl = ArticleReadingProgressController.shared;
    final progressMap = <String, dynamic>{
      for (final entry in progressCtrl.allProgressItems.entries)
        entry.key: entry.value.toJson(),
    };

    // 3) Tercihler + Silme kayıtları (tombstones)
    final themeUpdatedAt = AppThemeController.shared.themeUpdatedAtIso ??
        await _settingsRepository.getString('app_theme_updated_at');
    final deletedWords = await _loadTombstones(_deletedWordsKey);
    final deletedLists = await _loadTombstones(_deletedListsKey);
    final prefsMap = <String, dynamic>{
      'theme': AppThemeController.shared.preset.storageKey,
      if (themeUpdatedAt != null) 'theme_updated_at': themeUpdatedAt,
      if (deletedWords.isNotEmpty) 'deleted_words': deletedWords,
      if (deletedLists.isNotEmpty) 'deleted_lists': deletedLists,
    };

    return <String, dynamic>{
      'saved_words': wordsJson,
      'word_lists': listsJson,
      'reading_progress': progressMap,
      'preferences': prefsMap,
    };
  }
}
