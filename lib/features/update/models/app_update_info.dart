/// GitHub'daki `version.json` dosyasından okunan yeni sürüm bilgileri.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseNotes,
  });

  final String latestVersion;
  final int versionCode;
  final String apkUrl;
  final String releaseNotes;

  factory AppUpdateInfo.fromJson(Map<String, Object?> json) {
    final rawCode = json['version_code'];
    final parsedCode = rawCode is int
        ? rawCode
        : int.tryParse(rawCode?.toString() ?? '') ?? 0;

    return AppUpdateInfo(
      latestVersion: (json['latest_version'] as String? ?? '').trim(),
      versionCode: parsedCode,
      apkUrl: (json['apk_url'] as String? ?? '').trim(),
      releaseNotes: (json['release_notes'] as String? ?? '').trim(),
    );
  }
}
