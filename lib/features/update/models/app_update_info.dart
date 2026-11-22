/// GitHub'daki `version.json` dosyasından okunan yeni sürüm bilgileri.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseNotes,
    this.minVersionCode = 0,
  });

  final String latestVersion;
  final int versionCode;
  final String apkUrl;
  final String releaseNotes;

  /// Zorunlu minimum `version_code` eşiği (`0` ise güncelleme zorunlu değildir).
  final int minVersionCode;

  factory AppUpdateInfo.fromJson(Map<String, Object?> json) {
    final rawCode = json['version_code'];
    final parsedCode = rawCode is int
        ? rawCode
        : int.tryParse(rawCode?.toString() ?? '') ?? 0;

    final rawMinCode = json['min_version_code'];
    final parsedMinCode = rawMinCode is int
        ? rawMinCode
        : int.tryParse(rawMinCode?.toString() ?? '') ?? 0;

    return AppUpdateInfo(
      latestVersion: (json['latest_version'] as String? ?? '').trim(),
      versionCode: parsedCode,
      apkUrl: (json['apk_url'] as String? ?? '').trim(),
      releaseNotes: (json['release_notes'] as String? ?? '').trim(),
      minVersionCode: parsedMinCode < 0 ? 0 : parsedMinCode,
    );
  }
}
