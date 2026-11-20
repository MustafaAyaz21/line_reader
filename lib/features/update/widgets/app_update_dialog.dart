import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_update_info.dart';
import '../services/app_update_service.dart';

/// Yeni bir uygulama sürümü bulunduğunda gösterilen güncelleme penceresi.
/// APK indirme ilerlemesini gösterir ve kurulum ekranını doğrudan başlatır.
class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
    required this.updateService,
  });

  final AppUpdateInfo updateInfo;
  final AppUpdateService updateService;

  static Future<void> show(
    BuildContext context, {
    required AppUpdateInfo updateInfo,
    required AppUpdateService updateService,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AppUpdateDialog(
        updateInfo: updateInfo,
        updateService: updateService,
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double? _downloadProgress;
  File? _downloadedApk;
  String? _statusMessage;
  bool _isError = false;

  Future<void> _handleUpdatePressed() async {
    if (_isDownloading) return;

    // APK zaten indirildiyse (ör. izin ayarından dönüldüyse) tekrar indirmeden kur.
    final existingApk = _downloadedApk;
    if (existingApk != null && await existingApk.exists()) {
      await _launchInstall(existingApk);
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'Güncelleme indiriliyor...';
      _isError = false;
    });

    try {
      final apkFile = await widget.updateService.downloadApk(
        apkUrl: widget.updateInfo.apkUrl,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) return;
      _downloadedApk = apkFile;
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
      });
      await _launchInstall(apkFile);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _isError = true;
        _statusMessage =
            'Güncelleme dosyası indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    }
  }

  Future<void> _launchInstall(File apkFile) async {
    final result = await widget.updateService.installApk(apkFile.path);
    if (!mounted) return;

    switch (result) {
      case ApkInstallResult.launched:
        Navigator.of(context).pop();
      case ApkInstallResult.permissionRequired:
        setState(() {
          _isError = false;
          _statusMessage =
              'Lütfen açılan ayarlardan "Bu kaynaktan izin ver" seçeneğini etkinleştirip tekrar "Kurulumu Başlat" butonuna basın.';
        });
      case ApkInstallResult.failed:
        setState(() {
          _isError = true;
          _statusMessage =
              'Kurulum ekranı açılamadı. Lütfen tekrar deneyin.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasDownloaded = _downloadedApk != null;
    final progressPercent = _downloadProgress != null
        ? '%${(_downloadProgress! * 100).round()}'
        : '';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Yeni Güncelleme'),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Line Reader v${widget.updateInfo.latestVersion} hazır',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              widget.updateInfo.releaseNotes,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _downloadProgress),
            const SizedBox(height: 6),
            Text(
              progressPercent.isNotEmpty
                  ? 'İndiriliyor... $progressPercent'
                  : 'İndiriliyor...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_statusMessage != null && !_isDownloading) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isError
                    ? colorScheme.errorContainer
                    : colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _statusMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _isError
                      ? colorScheme.onErrorContainer
                      : colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Sonra'),
        ),
        FilledButton.icon(
          onPressed: _isDownloading ? null : _handleUpdatePressed,
          icon: Icon(
            hasDownloaded
                ? Icons.install_mobile_rounded
                : Icons.download_rounded,
            size: 18,
          ),
          label: Text(
            hasDownloaded ? 'Kurulumu Başlat' : 'Güncelle',
          ),
        ),
      ],
    );
  }
}
