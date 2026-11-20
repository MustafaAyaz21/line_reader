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

  /// Arka planda sessizce güncelleme kontrolü yapar.
  /// Yeni bir `version_code` varsa `AppUpdateInfo` döner, yoksa veya ağ
  /// erişilemiyorsa sessizce `null` döner.
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      final uri = Uri.parse(versionJsonUrl).replace(
        queryParameters: <String, String>{
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      final response = await _httpClient.get(uri).timeout(_checkTimeout);
      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        return null;
      }

      final remoteInfo = AppUpdateInfo.fromJson(decoded);
      if (remoteInfo.versionCode > currentBuild &&
          remoteInfo.apkUrl.startsWith('http')) {
        return remoteInfo;
      }
      return null;
    } catch (error) {
      debugPrint('[AppUpdateService] Sessiz guncelleme kontrolu atlandi: $error');
      return null;
    }
  }

  /// Yeni sürüm APK dosyasını uygulama önbellek dizinine indirir ve ilerlemeyi bildirir.
  Future<File> downloadApk({
    required String apkUrl,
    required void Function(double? progress) onProgress,
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

    try {
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress((downloadedBytes / totalBytes).clamp(0.0, 1.0));
        } else {
          onProgress(null);
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
    onProgress(1.0);
    return targetFile;
  }

  /// Android'de "Bilinmeyen uygulamaları yükle" iznini kontrol eder; izin yoksa
  /// ayarlar ekranını açar, izin varsa FileProvider üzerinden kurulumu başlatır.
  Future<ApkInstallResult> installApk(String filePath) async {
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
