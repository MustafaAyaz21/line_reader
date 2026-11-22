import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_update_info.dart';
import '../services/app_update_service.dart';

/// Uygulama içi güncelleme durumunu, sürüm bilgisini ve canlı APK indirme
/// akışını yöneten denetleyici.
class AppUpdateController extends ChangeNotifier {
  AppUpdateController({AppUpdateService? service})
      : _service = service ?? AppUpdateService(),
        _ownsService = service == null;

  AppUpdateService? _service;
  bool? _ownsService;

  bool _isChecking = false;
  bool _hasCompletedInitialCheck = false;
  DateTime? _lastCheckedAt;
  String _currentVersion = '';
  int _currentBuildNumber = 0;
  AppUpdateInfo? _remoteInfo;
  String? _checkError;

  bool _isDownloading = false;
  double? _downloadProgress;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  File? _downloadedApk;
  String? _downloadStatusMessage;
  bool _isDownloadError = false;
  bool _isPermissionPending = false;
  bool _isDisposed = false;

  AppUpdateService _resolveService() {
    return _service ??= AppUpdateService();
  }

  bool get isChecking => _isChecking;
  bool get hasCompletedInitialCheck => _hasCompletedInitialCheck;
  String get currentVersion => _currentVersion;
  int get currentBuildNumber => _currentBuildNumber;
  AppUpdateInfo? get remoteInfo => _remoteInfo;
  String? get checkError => _checkError;

  bool get hasUpdate => AppUpdateService.isUpdateAvailable(
        currentVersion: _currentVersion,
        currentBuildNumber: _currentBuildNumber,
        remoteInfo: _remoteInfo,
      );

  /// Sunucudaki `min_version_code` kurulu build numarasından büyükse ve yeni
  /// sürüm mevcutsa uygulama açılışta zorunlu güncelleme ekranı gösterir.
  bool get requiresMandatoryUpdate {
    final info = _remoteInfo;
    if (info == null || !hasUpdate) return false;
    return info.minVersionCode > 0 &&
        _currentBuildNumber > 0 &&
        _currentBuildNumber < info.minVersionCode;
  }

  bool get isDownloading => _isDownloading;
  double? get downloadProgress => _downloadProgress;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  File? get downloadedApk => _downloadedApk;
  String? get downloadStatusMessage => _downloadStatusMessage;
  bool get isDownloadError => _isDownloadError;
  bool get isPermissionPending => _isPermissionPending;

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Uygulama açılışında veya arka plandan ön plana dönüldüğünde sessizce
  /// güncelleme kontrolü yapar (otomatik popup göstermez, yalnızca yeni sürüm
  /// varsa üst bardaki kırmızı göstergeyi yakar).
  Future<void> checkSilently({bool force = false}) async {
    if (_isChecking || _isDownloading) return;
    final last = _lastCheckedAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last).inSeconds < 20) {
      return;
    }
    await checkForUpdates(silent: true);
  }

  /// `version.json` ve GitHub Releases API'yi kontrol eder, sürüm bilgisini günceller.
  Future<void> checkForUpdates({bool silent = false}) async {
    if (_isChecking) return;

    _isChecking = true;
    if (!silent) {
      _checkError = null;
    }
    _safeNotify();

    try {
      final result = await _resolveService().checkUpdateStatus();
      _currentVersion = result.currentVersion;
      _currentBuildNumber = result.currentBuildNumber;
      _hasCompletedInitialCheck = true;
      _lastCheckedAt = DateTime.now();

      if (result.remoteInfo != null) {
        final previousUrl = _remoteInfo?.apkUrl;
        _remoteInfo = result.remoteInfo;
        _checkError = null;
        // Farklı bir sürüm gelmişse önceki indirilen APK referansını temizle.
        if (previousUrl != null && previousUrl != _remoteInfo?.apkUrl) {
          _downloadedApk = null;
          _downloadProgress = null;
          _downloadStatusMessage = null;
          _isDownloadError = false;
          _isPermissionPending = false;
        }
      } else if (!silent) {
        _checkError = result.errorMessage;
      }
    } catch (error) {
      debugPrint('[AppUpdateController] Kontrol hatasi: $error');
      if (!silent) {
        _checkError =
            'Güncelleme kontrolü sırasında bir hata oluştu. Lütfen tekrar deneyin.';
      }
    } finally {
      _isChecking = false;
      _safeNotify();
    }
  }

  /// En son APK'yı indirir, canlı yüzde/ilerleme bilgisini günceller ve
  /// %100 tamamlandığında Android paket yükleyicisini otomatik başlatır.
  Future<void> downloadAndInstall() async {
    if (_isDownloading) return;
    final info = _remoteInfo;
    if (info == null || !hasUpdate) return;

    // İzin ayarından geri dönüldüyse zaten inmiş olan APK'yı doğrudan kur.
    final existingApk = _downloadedApk;
    if (existingApk != null && await existingApk.exists()) {
      await _launchInstall(existingApk);
      return;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _receivedBytes = 0;
    _totalBytes = 0;
    _isDownloadError = false;
    _isPermissionPending = false;
    _downloadStatusMessage = 'İndiriliyor... %0';
    _safeNotify();

    try {
      final apkFile = await _resolveService().downloadApk(
        apkUrl: info.apkUrl,
        onProgress: (progress) {
          _downloadProgress = progress.fraction;
          _receivedBytes = progress.receivedBytes;
          _totalBytes = progress.totalBytes;

          if (progress.fraction != null) {
            final pct = (progress.fraction! * 100).round().clamp(0, 100);
            _downloadStatusMessage = 'İndiriliyor... %$pct';
          } else {
            _downloadStatusMessage = 'İndiriliyor...';
          }
          _safeNotify();
        },
      );

      _downloadedApk = apkFile;
      _isDownloading = false;
      _downloadProgress = 1.0;
      _isDownloadError = false;
      _downloadStatusMessage =
          'İndirme tamamlandı (%100). Kurulum ekranı açılıyor...';
      _safeNotify();

      await _launchInstall(apkFile);
    } catch (error) {
      debugPrint('[AppUpdateController] Indirme hatasi: $error');
      _isDownloading = false;
      _downloadProgress = null;
      _isDownloadError = true;
      _isPermissionPending = false;
      _downloadStatusMessage =
          'Güncelleme dosyası indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      _safeNotify();
    }
  }

  Future<void> _launchInstall(File apkFile) async {
    final result = await _resolveService().installApk(apkFile.path);

    switch (result) {
      case ApkInstallResult.launched:
        _isDownloadError = false;
        _isPermissionPending = false;
        _downloadStatusMessage =
            'Kurulum ekranı açıldı. İşlemi Android kurulum penceresinden tamamlayabilirsiniz.';
      case ApkInstallResult.permissionRequired:
        _isDownloadError = false;
        _isPermissionPending = true;
        _downloadStatusMessage =
            'Açılan ayarlardan "Bu kaynaktan izin ver" seçeneğini etkinleştirip geri dönün ve tekrar kurulumu başlatın.';
      case ApkInstallResult.failed:
        _isDownloadError = true;
        _isPermissionPending = false;
        _downloadStatusMessage =
            'Android kurulum ekranı açılamadı. Lütfen tekrar deneyin.';
    }
    _safeNotify();
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_ownsService ?? true) {
      _service?.dispose();
    }
    super.dispose();
  }
}
