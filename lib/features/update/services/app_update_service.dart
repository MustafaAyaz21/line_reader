import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_update_info.dart';

/// APK kurulum başlatma sonucu.
enum ApkInstallResult {
  launched,
  permissionRequired,
  failed,
}

/// Kurulu sürüm ve uzaktaki sürüm kontrolünün birleşik sonucu.
class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.currentBuildNumber,
    this.remoteInfo,
    this.errorMessage,
  });

  final String currentVersion;
  final int currentBuildNumber;
  final AppUpdateInfo? remoteInfo;
  final String? errorMessage;

  bool get hasUpdate => AppUpdateService.isUpdateAvailable(
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        remoteInfo: remoteInfo,
      );
}

/// Canlı APK indirme ilerleme verisi.
class ApkDownloadProgress {
  const ApkDownloadProgress({
    required this.fraction,
    required this.receivedBytes,
    required this.totalBytes,
  });

  /// `0.0..1.0` arası yüzde değeri; sunucu boyut bildirmezse `null`.
  final double? fraction;
  final int receivedBytes;
  final int totalBytes;
}

/// GitHub'daki `version.json` ve anlık GitHub Releases API üzerinden yeni sürüm
/// kontrolü yapan, APK'yı indirip Android FileProvider üzerinden kurulum ekranını
/// açan servis.
class AppUpdateService {
  AppUpdateService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const String cloudflareVersionJsonUrl =
      'https://getlinereader.com/version.json';

  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/MustafaAyaz21/line_reader/main/version.json';

  /// `raw.githubusercontent.com` 5 dakikalık CDN önbelleği tutabildiği için
  /// yeni yayınlanan sürümleri saniyesinde yakalamak üzere kullanılan resmi API.
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/MustafaAyaz21/line_reader/releases/latest';

  /// Hem CDN önbelleğine hem de GitHub API saatlik limitine takılmayan
  /// doğrudan Release yönlendirme adresi.
  static const String latestReleaseRedirectUrl =
      'https://github.com/MustafaAyaz21/line_reader/releases/latest';

  static const MethodChannel _channel =
      MethodChannel('com.lineapps.linereader/app_updater');

  static const Duration _checkTimeout = Duration(seconds: 12);

  static const Map<String, String> _requestHeaders = <String, String>{
    'User-Agent': 'LineReaderApp',
    'Cache-Control': 'no-cache, no-store, must-revalidate',
    'Pragma': 'no-cache',
  };

  final http.Client _httpClient;
  final bool _ownsClient;

  /// `v0.1.3` ve `0.1.2` gibi semantik sürüm metinlerini karşılaştırır.
  /// `a > b` ise pozitif, eşitse `0`, küçükse negatif döner.
  static int compareVersions(String a, String b) {
    final partsA = _parseVersionParts(a);
    final partsB = _parseVersionParts(b);
    final maxLen =
        partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < maxLen; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static List<int> _parseVersionParts(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    if (cleaned.isEmpty) return const <int>[0];
    return cleaned
        .split('.')
        .map((segment) => int.tryParse(segment.trim()) ?? 0)
        .toList(growable: false);
  }

  /// Hem `version_code` hem de `latest_version` karşılaştırması yaparak yeni
  /// sürüm olup olmadığını kesin olarak belirler.
  static bool isUpdateAvailable({
    required String currentVersion,
    required int currentBuildNumber,
    required AppUpdateInfo? remoteInfo,
  }) {
    if (remoteInfo == null || !remoteInfo.apkUrl.startsWith('http')) {
      return false;
    }
    if (remoteInfo.versionCode > 0 &&
        remoteInfo.versionCode > currentBuildNumber) {
      return true;
    }
    if (remoteInfo.latestVersion.isNotEmpty &&
        currentVersion.isNotEmpty &&
        compareVersions(remoteInfo.latestVersion, currentVersion) > 0) {
      return true;
    }
    return false;
  }

  /// Kurulu uygulamanın sürüm ve build bilgisini okur.
  Future<({String version, int buildNumber})> getCurrentAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      return (version: info.version, buildNumber: build);
    } catch (_) {
      return (version: '0.0.0', buildNumber: 0);
    }
  }

  /// `version.json`, GitHub Releases API ve doğrudan `releases/latest`
  /// yönlendirmesini paralel sorgular; hangisi daha güncel sürümü bildiriyorsa
  /// onu döndürür (CDN gecikmesi veya API limiti yaşamaz).
  Future<AppUpdateCheckResult> checkUpdateStatus() async {
    final installed = await getCurrentAppVersion();

    final results = await Future.wait<AppUpdateInfo?>(<Future<AppUpdateInfo?>>[
      _fetchFromVersionJsonUrl(cloudflareVersionJsonUrl),
      _fetchFromVersionJsonUrl(versionJsonUrl),
      _fetchFromLatestReleaseApi(),
      _fetchFromGitHubReleaseRedirect(),
    ]);

    AppUpdateInfo? bestRemote;
    for (final candidate in results) {
      bestRemote = _pickFresherInfo(bestRemote, candidate);
    }

    if (bestRemote == null) {
      return AppUpdateCheckResult(
        currentVersion: installed.version,
        currentBuildNumber: installed.buildNumber,
        errorMessage:
            'Güncelleme sunucusuna ulaşılamadı. İnternet bağlantınızı kontrol edin.',
      );
    }

    return AppUpdateCheckResult(
      currentVersion: installed.version,
      currentBuildNumber: installed.buildNumber,
      remoteInfo: bestRemote,
    );
  }

  AppUpdateInfo? _pickFresherInfo(AppUpdateInfo? a, AppUpdateInfo? b) {
    if (a == null) return b;
    if (b == null) return a;

    final highestMinCode =
        a.minVersionCode >= b.minVersionCode ? a.minVersionCode : b.minVersionCode;

    final semverDiff = compareVersions(b.latestVersion, a.latestVersion);
    if (semverDiff > 0) {
      // Releases API daha yeni (raw.githubusercontent.com henüz CDN önbelleğinde).
      return AppUpdateInfo(
        latestVersion: b.latestVersion,
        versionCode: b.versionCode,
        apkUrl: b.apkUrl,
        releaseNotes: b.releaseNotes,
        minVersionCode: highestMinCode,
      );
    }
    if (semverDiff < 0) {
      return AppUpdateInfo(
        latestVersion: a.latestVersion,
        versionCode: a.versionCode,
        apkUrl: a.apkUrl,
        releaseNotes: a.releaseNotes,
        minVersionCode: highestMinCode,
      );
    }

    // Aynı sürümse version_code ve daha dolu release_notes içeren kaydı tercih et.
    if (a.versionCode >= b.versionCode) {
      return AppUpdateInfo(
        latestVersion: a.latestVersion.isNotEmpty
            ? a.latestVersion
            : b.latestVersion,
        versionCode: a.versionCode,
        apkUrl: a.apkUrl.startsWith('http') ? a.apkUrl : b.apkUrl,
        releaseNotes:
            a.releaseNotes.isNotEmpty ? a.releaseNotes : b.releaseNotes,
        minVersionCode: highestMinCode,
      );
    }
    return AppUpdateInfo(
      latestVersion: b.latestVersion,
      versionCode: b.versionCode,
      apkUrl: b.apkUrl.startsWith('http') ? b.apkUrl : a.apkUrl,
      releaseNotes:
          b.releaseNotes.isNotEmpty ? b.releaseNotes : a.releaseNotes,
      minVersionCode: highestMinCode,
    );
  }

  Future<AppUpdateInfo?> _fetchFromVersionJsonUrl(String targetUrl) async {
    try {
      final uri = Uri.parse(targetUrl).replace(
        queryParameters: <String, String>{
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final response = await _httpClient
          .get(uri, headers: _requestHeaders)
          .timeout(_checkTimeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;

      final info = AppUpdateInfo.fromJson(
        Map<String, Object?>.from(decoded),
      );
      return info.apkUrl.startsWith('http') ? info : null;
    } catch (error) {
      debugPrint('[AppUpdateService] version.json kontrol hatasi ($targetUrl): $error');
      return null;
    }
  }

  Future<AppUpdateInfo?> _fetchFromLatestReleaseApi() async {
    try {
      final uri = Uri.parse(latestReleaseApiUrl);
      final response = await _httpClient
          .get(
            uri,
            headers: <String, String>{
              ..._requestHeaders,
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(_checkTimeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;

      final rawTag = (decoded['tag_name'] as String? ?? '').trim();
      final cleanVersion = rawTag.replaceFirst(RegExp(r'^[vV]'), '').trim();
      if (cleanVersion.isEmpty) return null;

      String apkUrl = '';
      final assets = decoded['assets'];
      if (assets is List) {
        for (final item in assets) {
          if (item is Map) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            final downloadUrl =
                (item['browser_download_url'] as String? ?? '').trim();
            if (name.endsWith('.apk') && downloadUrl.startsWith('http')) {
              apkUrl = downloadUrl;
              break;
            }
          }
        }
      }
      if (apkUrl.isEmpty) {
        apkUrl =
            'https://github.com/MustafaAyaz21/line_reader/releases/download/$rawTag/app-release.apk';
      }

      final notes = (decoded['body'] as String? ?? '').trim();
      return AppUpdateInfo(
        latestVersion: cleanVersion,
        versionCode: 0,
        apkUrl: apkUrl,
        releaseNotes: notes,
      );
    } catch (error) {
      debugPrint('[AppUpdateService] GitHub Releases API hatasi: $error');
      return null;
    }
  }

  Future<AppUpdateInfo?> _fetchFromGitHubReleaseRedirect() async {
    try {
      final uri = Uri.parse(latestReleaseRedirectUrl);
      final request = http.Request('HEAD', uri)
        ..followRedirects = false
        ..headers.addAll(_requestHeaders);
      final response = await _httpClient.send(request).timeout(_checkTimeout);
      final location = response.headers['location'] ?? '';
      if (location.isEmpty) return null;

      final match = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(location);
      if (match == null) return null;

      final rawTag = Uri.decodeComponent(match.group(1) ?? '').trim();
      final cleanVersion = rawTag.replaceFirst(RegExp(r'^[vV]'), '').trim();
      if (cleanVersion.isEmpty) return null;

      return AppUpdateInfo(
        latestVersion: cleanVersion,
        versionCode: 0,
        apkUrl:
            'https://github.com/MustafaAyaz21/line_reader/releases/download/$rawTag/app-release.apk',
        releaseNotes: '',
      );
    } catch (error) {
      debugPrint('[AppUpdateService] GitHub redirect kontrol hatasi: $error');
      return null;
    }
  }

  /// Arka planda sessizce güncelleme kontrolü yapar; yeni sürüm varsa döner.
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    final result = await checkUpdateStatus();
    return result.hasUpdate ? result.remoteInfo : null;
  }

  /// Önceki uygulama içi güncellemeden kalan `linereader_update.apk` dosyasını
  /// açılışta temizleyerek telefon hafızasında boşuna yer kaplamasını önler.
  static Future<void> cleanupDownloadedUpdateApk() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final leftover = File(p.join(tempDir.path, 'linereader_update.apk'));
      if (await leftover.exists()) {
        await leftover.delete();
      }
    } catch (_) {}
  }

  /// Yeni sürüm APK dosyasını uygulama önbellek dizinine indirir ve canlı ilerlemeyi bildirir.
  Future<File> downloadApk({
    required String apkUrl,
    required void Function(ApkDownloadProgress progress) onProgress,
  }) async {
    final uri = Uri.parse(apkUrl);
    final request = http.Request('GET', uri)
      ..headers.addAll(<String, String>{
        'User-Agent': 'LineReaderApp',
        'Accept': 'application/octet-stream',
      });
    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw HttpException(
        'APK indirilemedi (HTTP ${streamedResponse.statusCode})',
        uri: uri,
      );
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    final tempDir = await getTemporaryDirectory();
    final targetFile = File(p.join(tempDir.path, 'linereader_update.apk'));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final sink = targetFile.openWrite();
    var downloadedBytes = 0;
    var lastReportedAt = DateTime.fromMillisecondsSinceEpoch(0);

    try {
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        final now = DateTime.now();
        // Arayüzü akıcı tutarken gereksiz rebuild yağmurunu önle (~80ms aralık)
        if (now.difference(lastReportedAt).inMilliseconds >= 80 ||
            (totalBytes > 0 && downloadedBytes >= totalBytes)) {
          lastReportedAt = now;
          onProgress(
            ApkDownloadProgress(
              fraction: totalBytes > 0
                  ? (downloadedBytes / totalBytes).clamp(0.0, 1.0)
                  : null,
              receivedBytes: downloadedBytes,
              totalBytes: totalBytes,
            ),
          );
        }
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      rethrow;
    }

    await sink.close();
    onProgress(
      ApkDownloadProgress(
        fraction: 1.0,
        receivedBytes: downloadedBytes,
        totalBytes: totalBytes > 0 ? totalBytes : downloadedBytes,
      ),
    );
    return targetFile;
  }

  /// Android'de "Bilinmeyen uygulamaları yükle" iznini kontrol eder; izin yoksa
  /// ayarlar ekranını açar, izin varsa FileProvider üzerinden kurulumu başlatır.
  Future<ApkInstallResult> installApk(String filePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return ApkInstallResult.failed;
    }

    try {
      final canInstall =
          await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
      if (!canInstall) {
        await _channel.invokeMethod<void>('openInstallPermissionSettings');
        return ApkInstallResult.permissionRequired;
      }

      await _channel.invokeMethod<bool>(
        'installApk',
        <String, Object>{'filePath': filePath},
      );
      return ApkInstallResult.launched;
    } catch (error) {
      debugPrint('[AppUpdateService] APK kurulum baslatma hatasi: $error');
      return ApkInstallResult.failed;
    }
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
