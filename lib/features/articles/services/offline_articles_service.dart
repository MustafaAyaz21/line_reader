import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../controllers/article_audio_controller.dart';
import '../models/article.dart';

/// Cihazda kalıcı olarak saklanan tek bir çevrimdışı makale paketinin yolları.
class OfflineArticleEntry {
  const OfflineArticleEntry({
    required this.articleId,
    required this.directoryPath,
    required this.articleJsonPath,
    this.audioPath,
    this.coverImagePath,
    required this.downloadedAt,
  });

  final String articleId;
  final String directoryPath;
  final String articleJsonPath;
  final String? audioPath;
  final String? coverImagePath;
  final DateTime downloadedAt;
}

/// Çevrimdışı indirme işleminin sonucu.
class OfflineDownloadResult {
  const OfflineDownloadResult({
    required this.ok,
    required this.message,
    this.entry,
  });

  final bool ok;
  final String message;
  final OfflineArticleEntry? entry;
}

/// Makaleleri (metin, gömülü kelime/çeviri sözlükleri, Podcast AI ses dosyası
/// ve kapak görseli dahil) uygulamanın kalıcı belge dizinine indirip yöneten
/// çevrimdışı depolama servisi.
///
/// Geçici önbellekten (`getTemporaryDirectory`) ayrı olarak
/// `getApplicationDocumentsDirectory()/offline_articles/<id>/` klasöründe
/// saklanır; böylece işletim sistemi tarafından silinmez ve kullanıcı isteyene
/// kadar cihazda kalır.
class OfflineArticlesService extends ChangeNotifier {
  OfflineArticlesService({
    http.Client? httpClient,
    Future<Directory> Function()? baseDirProvider,
    Future<Directory> Function()? tempDirProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _baseDirProvider = baseDirProvider,
        _tempDirProvider = tempDirProvider;

  static final OfflineArticlesService shared = OfflineArticlesService();

  static const String _rootFolderName = 'offline_articles';
  static const String _articleFileName = 'article.json';

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Future<Directory> Function()? _baseDirProvider;
  final Future<Directory> Function()? _tempDirProvider;

  final Map<String, OfflineArticleEntry> _entries =
      <String, OfflineArticleEntry>{};
  final Set<String> _downloadingIds = <String>{};

  bool _initialized = false;
  Future<void>? _initFuture;
  bool _disposed = false;

  bool get isSupported => !kIsWeb;
  bool get isInitialized => _initialized;

  List<OfflineArticleEntry> get entries =>
      List<OfflineArticleEntry>.unmodifiable(_entries.values);

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  static String safeIdFor(String articleId) {
    final cleaned = articleId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? 'article' : cleaned;
  }

  bool isDownloaded(String articleId) {
    final key = articleId.trim();
    if (key.isEmpty) return false;
    return _entries.containsKey(key);
  }

  bool isDownloading(String articleId) {
    final key = articleId.trim();
    if (key.isEmpty) return false;
    return _downloadingIds.contains(key);
  }

  String? localAudioPath(String articleId) {
    if (kIsWeb) return null;
    final path = _entries[articleId.trim()]?.audioPath;
    if (path == null || path.isEmpty) return null;
    return path;
  }

  String? localCoverPath(String articleId) {
    if (kIsWeb) return null;
    final path = _entries[articleId.trim()]?.coverImagePath;
    if (path == null || path.isEmpty) return null;
    return path;
  }

  Future<Directory> _resolveRootDir() async {
    final base = _baseDirProvider != null
        ? await _baseDirProvider()
        : await getApplicationDocumentsDirectory();
    final root = Directory(p.join(base.path, _rootFolderName));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory?> _resolveTempAudioDir() async {
    try {
      final temp = _tempDirProvider != null
          ? await _tempDirProvider()
          : await getTemporaryDirectory();
      return Directory(p.join(temp.path, 'article_audio'));
    } catch (_) {
      return null;
    }
  }

  /// Uygulama açılışında veya makale ekranına girildiğinde cihazdaki mevcut
  /// çevrimdışı makale paketlerini tarar.
  Future<void> ensureInitialized() {
    if (!isSupported) {
      _initialized = true;
      return Future<void>.value();
    }
    if (_initialized) return Future<void>.value();
    final existing = _initFuture;
    if (existing != null) return existing;

    final future = _scanExistingEntries();
    _initFuture = future;
    return future.whenComplete(() {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
    });
  }

  Future<void> _scanExistingEntries() async {
    try {
      final root = await _resolveRootDir();
      final scanned = <String, OfflineArticleEntry>{};

      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final entry = await _readEntryFromDirectory(entity);
        if (entry != null) {
          scanned[entry.articleId] = entry;
        }
      }

      _entries
        ..clear()
        ..addAll(scanned);
      _initialized = true;
      _safeNotify();
    } catch (error) {
      debugPrint('[OfflineArticlesService] Tarama hatasi: $error');
      _initialized = true;
    }
  }

  Future<OfflineArticleEntry?> _readEntryFromDirectory(Directory dir) async {
    try {
      final jsonFile = File(p.join(dir.path, _articleFileName));
      if (!await jsonFile.exists()) return null;

      final raw = await jsonFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final article = Article.tryFromJson(Map<String, Object?>.from(decoded));
      if (article == null || article.id.trim().isEmpty) return null;

      String? audioPath;
      String? coverPath;
      await for (final child in dir.list()) {
        if (child is! File) continue;
        final name = p.basename(child.path).toLowerCase();
        if (name.startsWith('audio.')) {
          if (await _isNonEmptyFile(child, minBytes: 1024)) {
            audioPath = child.path;
          }
        } else if (name.startsWith('cover.')) {
          if (await _isNonEmptyFile(child, minBytes: 128)) {
            coverPath = child.path;
          }
        }
      }

      final stat = await jsonFile.stat();
      return OfflineArticleEntry(
        articleId: article.id.trim(),
        directoryPath: dir.path,
        articleJsonPath: jsonFile.path,
        audioPath: audioPath,
        coverImagePath: coverPath,
        downloadedAt: stat.modified.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isNonEmptyFile(File file, {int minBytes = 1}) async {
    try {
      return await file.exists() && await file.length() >= minBytes;
    } catch (_) {
      return false;
    }
  }

  /// Cihazdaki çevrimdışı paketten makale nesnesini okur.
  Future<Article?> loadOfflineArticle(String articleId) async {
    if (!isSupported) return null;
    await ensureInitialized();
    final entry = _entries[articleId.trim()];
    if (entry == null) return null;
    try {
      final file = File(entry.articleJsonPath);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return Article.tryFromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// Makaleyi metin, gömülü sözlük/çeviri verileri, Podcast AI ses dosyası
  /// ve kapak görseliyle birlikte kalıcı cihaz klasörüne indirir.
  Future<OfflineDownloadResult> downloadArticle(Article article) async {
    if (!isSupported) {
      return const OfflineDownloadResult(
        ok: false,
        message: 'Çevrimdışı indirme yalnızca mobil ve masaüstü cihazlarda desteklenir.',
      );
    }

    final id = article.id.trim();
    if (id.isEmpty) {
      return const OfflineDownloadResult(
        ok: false,
        message: 'Geçersiz makale kimliği.',
      );
    }

    await ensureInitialized();
    if (_downloadingIds.contains(id)) {
      return const OfflineDownloadResult(
        ok: false,
        message: 'Makale zaten indiriliyor.',
      );
    }

    _downloadingIds.add(id);
    _safeNotify();

    Directory? targetDir;
    try {
      final root = await _resolveRootDir();
      final safeId = safeIdFor(id);
      targetDir = Directory(p.join(root.path, safeId));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // 1) Podcast AI ses dosyasını indir (makalede varsa zorunlu)
      String? savedAudioPath;
      final rawAudioUrl = article.audioUrl?.trim();
      if (rawAudioUrl != null && rawAudioUrl.isNotEmpty) {
        savedAudioPath = await _downloadOrReuseAudio(
          articleId: id,
          safeId: safeId,
          rawAudioUrl: rawAudioUrl,
          targetDir: targetDir,
        );
        if (savedAudioPath == null) {
          // Sesli makalede ses dosyası indirilemediyse yarım paket bırakma.
          if (!_entries.containsKey(id)) {
            await _deleteDirectorySilently(targetDir);
          }
          return const OfflineDownloadResult(
            ok: false,
            message:
                'Ses dosyası indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          );
        }
      }

      // 2) Kapak görselini indir (en iyi çaba - başarısız olursa metin ve ses korunur)
      final savedCoverPath = await _downloadCoverImage(
        imageUrl: article.displayImageUrl,
        targetDir: targetDir,
      );

      // 3) Tam makale JSON'unu (içerik, word_meanings, word_relations, çeviriler) kaydet
      final jsonFile = File(p.join(targetDir.path, _articleFileName));
      await jsonFile.writeAsString(
        jsonEncode(article.toJson()),
        flush: true,
      );

      final entry = OfflineArticleEntry(
        articleId: id,
        directoryPath: targetDir.path,
        articleJsonPath: jsonFile.path,
        audioPath: savedAudioPath,
        coverImagePath: savedCoverPath,
        downloadedAt: DateTime.now().toUtc(),
      );
      _entries[id] = entry;

      return OfflineDownloadResult(
        ok: true,
        message: savedAudioPath != null
            ? 'Makale ve Podcast sesi çevrimdışı için indirildi.'
            : 'Makale çevrimdışı okuma için indirildi.',
        entry: entry,
      );
    } catch (error) {
      debugPrint('[OfflineArticlesService] Indirme hatasi: $error');
      if (targetDir != null && !_entries.containsKey(id)) {
        await _deleteDirectorySilently(targetDir);
      }
      return const OfflineDownloadResult(
        ok: false,
        message: 'Makale indirilirken bir sorun oluştu.',
      );
    } finally {
      _downloadingIds.remove(id);
      _safeNotify();
    }
  }

  Future<String?> _downloadOrReuseAudio({
    required String articleId,
    required String safeId,
    required String rawAudioUrl,
    required Directory targetDir,
  }) async {
    final lowerUrl = rawAudioUrl.toLowerCase();
    final ext = lowerUrl.endsWith('.wav')
        ? '.wav'
        : (lowerUrl.endsWith('.mp3') ? '.mp3' : '.m4a');
    final targetFile = File(p.join(targetDir.path, 'audio$ext'));

    // Zaten kalıcı klasörde geçerli ses varsa tekrar indirme.
    if (await _isValidAudioFile(targetFile)) {
      return targetFile.path;
    }

    // Geçici önbellekte önceden dinlenip indirilmiş geçerli ses varsa kopyala.
    final tempAudioDir = await _resolveTempAudioDir();
    if (tempAudioDir != null) {
      final tempFile = File(p.join(tempAudioDir.path, '$safeId$ext'));
      if (await _isValidAudioFile(tempFile)) {
        try {
          await tempFile.copy(targetFile.path);
          if (await _isValidAudioFile(targetFile)) {
            return targetFile.path;
          }
        } catch (_) {}
      }
    }

    // Ağdan aday URL'leri sırayla indir ve bayt başlığını doğrula.
    for (final url in ArticleAudioController.candidateAudioUrls(rawAudioUrl)) {
      try {
        final response = await _httpClient
            .get(
              Uri.parse(url),
              headers: const <String, String>{'User-Agent': 'LineReaderApp'},
            )
            .timeout(const Duration(seconds: 30));
        final ct = response.headers['content-type'];
        if (response.statusCode == 200 &&
            ArticleAudioController.isValidAudioBytes(
              response.bodyBytes,
              contentType: ct,
            )) {
          await targetFile.writeAsBytes(response.bodyBytes, flush: true);
          return targetFile.path;
        }
      } catch (_) {
        // Sıradaki yedek URL'yi dene.
      }
    }
    return null;
  }

  Future<bool> _isValidAudioFile(File file) async {
    try {
      if (!await file.exists()) return false;
      if (await file.length() < 1024) return false;
      final raf = await file.open();
      try {
        final header = await raf.read(32);
        final padded = List<int>.filled(1024, 0);
        for (var i = 0; i < header.length && i < padded.length; i++) {
          padded[i] = header[i];
        }
        return ArticleAudioController.isValidAudioBytes(padded);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<String?> _downloadCoverImage({
    required String imageUrl,
    required Directory targetDir,
  }) async {
    final trimmed = imageUrl.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return null;
    }

    try {
      final response = await _httpClient
          .get(
            Uri.parse(trimmed),
            headers: const <String, String>{'User-Agent': 'LineReaderApp'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.length < 128) {
        return null;
      }

      final ct = (response.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('text/html') || ct.contains('application/json')) {
        return null;
      }

      final ext = ct.contains('png')
          ? '.png'
          : (ct.contains('webp') ? '.webp' : '.jpg');
      final coverFile = File(p.join(targetDir.path, 'cover$ext'));
      await coverFile.writeAsBytes(response.bodyBytes, flush: true);
      return coverFile.path;
    } catch (_) {
      return null;
    }
  }

  /// İndirilen makalenin kalıcı klasörünü ve varsa geçici ses önbelleğini
  /// cihazdan tamamen siler.
  Future<bool> deleteOfflineArticle(String articleId) async {
    if (!isSupported) return false;
    final id = articleId.trim();
    if (id.isEmpty) return false;

    await ensureInitialized();
    final safeId = safeIdFor(id);

    try {
      final root = await _resolveRootDir();
      final dir = Directory(p.join(root.path, safeId));
      await _deleteDirectorySilently(dir);

      // Geçici ses önbelleğindeki kopyayı da temizle.
      final tempAudioDir = await _resolveTempAudioDir();
      if (tempAudioDir != null && await tempAudioDir.exists()) {
        for (final ext in const <String>['.m4a', '.mp3', '.wav']) {
          final tempFile = File(p.join(tempAudioDir.path, '$safeId$ext'));
          try {
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (_) {}
        }
      }

      _entries.remove(id);
      _safeNotify();
      return true;
    } catch (error) {
      debugPrint('[OfflineArticlesService] Silme hatasi: $error');
      return false;
    }
  }

  Future<void> _deleteDirectorySilently(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }
}
