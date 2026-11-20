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

/// Kurulu sürüm ve uzaktaki `version.json` kontrolünün birleşik sonucu.
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

  bool get hasUpdate {
    final remote = remoteInfo;
    if (remote == null) return false;
    return remote.versionCode > currentBuildNumber &&
        remote.apkUrl.startsWith('http');
  }
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

/// GitHub'daki `version.json` üzerinden yeni sürüm kontrolü yapan, APK'yı
/// indirip Android FileProvider üzerinden kurulum ekranını açan servis.
class AppUpdateService {
  AppUpdateService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/MustafaAyaz21/line_reader/main/version.json';

  static const MethodChannel _channel =
      MethodChannel('com.lineapps.linereader/app_updater');

  static const Duration _checkTimeout = Duration(seconds: 10);

  final http.Client _httpClient;
  final bool _ownsClient;

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

  /// Kurulu sürüm ile GitHub `version.json` verisini karşılaştırır.
  /// Hata durumunda istisna fırlatmak yerine `errorMessage` dolu bir sonuç döner.
  Future<AppUpdateCheckResult> checkUpdateStatus() async {
    final installed = await getCurrentAppVersion();

    try {
      final uri = Uri.parse(versionJsonUrl).replace(
        queryParameters: <String, String>{
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      final response = await _httpClient.get(uri).timeout(_checkTimeout);
      if (response.statusCode != 200) {
        return AppUpdateCheckResult(
          currentVersion: installed.version,
          currentBuildNumber: installed.buildNumber,
          errorMessage:
              'Güncelleme bilgisi alınamadı (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        return AppUpdateCheckResult(
          currentVersion: installed.version,
          currentBuildNumber: installed.buildNumber,
          errorMessage: 'Güncelleme bilgisi okunamadı.',
        );
      }

      final remoteInfo = AppUpdateInfo.fromJson(decoded);
      return AppUpdateCheckResult(
        currentVersion: installed.version,
        currentBuildNumber: installed.buildNumber,
        remoteInfo: remoteInfo,
      );
    } catch (error) {
      debugPrint('[AppUpdateService] Guncelleme kontrol hatasi: $error');
      return AppUpdateCheckResult(
        currentVersion: installed.version,
        currentBuildNumber: installed.buildNumber,
        errorMessage:
            'Güncelleme sunucusuna ulaşılamadı. İnternet bağlantınızı kontrol edin.',
      );
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

  /// Yeni sürüm APK dosyasını uygulama önbellek dizinine indirir ve canlı ilerlemeyi bildirir.
  Future<File> downloadApk({
    required String apkUrl,
    required void Function(ApkDownloadProgress progress) onProgress,
  }) async {
    final uri = Uri.parse(apkUrl);
    final request = http.Request('GET', uri);
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
