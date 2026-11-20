import 'package:flutter/material.dart';

import '../controllers/app_update_controller.dart';

/// Sağ üstteki güncelleme ikonuna tıklandığında `Navigator.push` ile açılan
/// bağımsız güncelleme sayfası. Mevcut/yeni sürüm, sürüm notları, canlı APK
/// indirme ilerleme çubuğu (%) ve otomatik Android kurulum akışını sunar.
class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({
    super.key,
    required this.controller,
  });

  final AppUpdateController controller;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Sayfa ilk kez açılırken henüz kontrol yapılmadıysa veya hata varsa tazele.
      if (!widget.controller.hasCompletedInitialCheck ||
          widget.controller.remoteInfo == null) {
        widget.controller.checkForUpdates();
      }
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Güncellemeler'),
        actions: [
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final busy =
                  widget.controller.isChecking || widget.controller.isDownloading;
              return IconButton(
                onPressed: busy ? null : () => widget.controller.checkForUpdates(),
                tooltip: 'Yeniden Kontrol Et',
                icon: const Icon(Icons.refresh_rounded),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final remote = controller.remoteInfo;
          final hasUpdate = controller.hasUpdate;
          final isChecking = controller.isChecking;
          final isDownloading = controller.isDownloading;
          final hasDownloadedApk = controller.downloadedApk != null;

          final installedLabel = controller.currentVersion.isNotEmpty
              ? 'v${controller.currentVersion} (Build ${controller.currentBuildNumber})'
              : 'Okunuyor...';
          final latestLabel = remote != null && remote.latestVersion.isNotEmpty
              ? 'v${remote.latestVersion} (Build ${remote.versionCode})'
              : '-';

          final progressFraction = controller.downloadProgress;
          final percentInt = progressFraction != null
              ? (progressFraction * 100).round().clamp(0, 100)
              : null;

          final String primaryButtonLabel;
          final IconData primaryButtonIcon;
          if (isDownloading) {
            primaryButtonLabel = percentInt != null
                ? 'İndiriliyor... %$percentInt'
                : 'İndiriliyor...';
            primaryButtonIcon = Icons.downloading_rounded;
          } else if (controller.isDownloadError) {
            primaryButtonLabel = 'Tekrar Dene';
            primaryButtonIcon = Icons.refresh_rounded;
          } else if (hasDownloadedApk) {
            primaryButtonLabel = 'Kurulumu Başlat';
            primaryButtonIcon = Icons.install_mobile_rounded;
          } else {
            primaryButtonLabel = 'En son gelen güncellemeyi indir';
            primaryButtonIcon = Icons.download_rounded;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              // Üst durum kartı
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: hasUpdate
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hasUpdate
                        ? colorScheme.primary.withAlpha(70)
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: hasUpdate
                            ? colorScheme.primary
                            : colorScheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isChecking
                            ? Icons.sync_rounded
                            : hasUpdate
                                ? Icons.system_update_alt_rounded
                                : Icons.check_circle_outline_rounded,
                        size: 28,
                        color: hasUpdate
                            ? colorScheme.onPrimary
                            : colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isChecking
                                ? 'Güncellemeler kontrol ediliyor...'
                                : hasUpdate
                                    ? 'Yeni güncelleme hazır'
                                    : 'Uygulamanız güncel',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: hasUpdate
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isChecking
                                ? 'GitHub üzerinden en son sürüm sorgulanıyor.'
                                : hasUpdate
                                    ? 'Line Reader v${remote!.latestVersion} indirilmeye hazır.'
                                    : 'Şu anda Line Reader\'ın en son sürümünü kullanıyorsunuz.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hasUpdate
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Mevcut ve yeni sürüm bilgileri
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    _VersionRow(
                      label: 'Mevcut Sürüm',
                      value: installedLabel,
                    ),
                    Divider(height: 20, color: colorScheme.outlineVariant),
                    _VersionRow(
                      label: 'En Son Sürüm',
                      value: latestLabel,
                      highlight: hasUpdate,
                    ),
                  ],
                ),
              ),

              // Sürüm notları (varsa)
              if (remote != null && remote.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sürüm Notları',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        remote.releaseNotes,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Kontrol hatası (varsa)
              if (controller.checkError != null && !isChecking) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          controller.checkError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Canlı indirme ilerleme alanı
              if (isDownloading ||
                  controller.downloadStatusMessage != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: controller.isDownloadError
                        ? colorScheme.errorContainer
                        : colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: controller.isDownloadError
                          ? colorScheme.error.withAlpha(90)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              controller.downloadStatusMessage ??
                                  'İndiriliyor...',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: controller.isDownloadError
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (isDownloading && percentInt != null)
                            Text(
                              '%$percentInt',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                      if (isDownloading || progressFraction == 1.0) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progressFraction,
                            minHeight: 8,
                          ),
                        ),
                        if (controller.receivedBytes > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            controller.totalBytes > 0
                                ? '${_formatBytes(controller.receivedBytes)} / ${_formatBytes(controller.totalBytes)}'
                                : '${_formatBytes(controller.receivedBytes)} indirildi',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Ana aksiyon butonu
              if (hasUpdate)
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed:
                        isDownloading ? null : controller.downloadAndInstall,
                    icon: Icon(primaryButtonIcon, size: 20),
                    label: Text(
                      primaryButtonLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 48,
                  child: FilledButton.tonalIcon(
                    onPressed:
                        isChecking ? null : () => controller.checkForUpdates(),
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    label: Text(
                      isChecking
                          ? 'Kontrol Ediliyor...'
                          : 'Güncellemeleri Kontrol Et',
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: highlight ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
