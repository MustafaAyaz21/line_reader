/// Bir makalede kullanıcının en son kaldığı okuma ilerlemesini temsil eder.
class ArticleReadingProgress {
  const ArticleReadingProgress({
    required this.articleId,
    required this.articleTitle,
    required this.articleLevel,
    required this.progress,
    this.scrollOffset = 0,
    this.audioPositionMs = 0,
    required this.updatedAt,
  });

  final String articleId;
  final String articleTitle;
  final String articleLevel;

  /// `0.0` ile `1.0` arasında tamamlanma oranı.
  final double progress;

  /// Son kaydedilen kaydırma ofseti (piksel cinsinden yedek değer).
  final double scrollOffset;

  /// Son kaydedilen ses/podcast çalma konumu (milisaniye cinsinden).
  final int audioPositionMs;

  final DateTime updatedAt;

  double get clampedProgress => progress.clamp(0.0, 1.0).toDouble();

  int get progressPercent => (clampedProgress * 100).round();

  bool get isCompleted => progressPercent >= 99;

  ArticleReadingProgress copyWith({
    String? articleTitle,
    String? articleLevel,
    double? progress,
    double? scrollOffset,
    int? audioPositionMs,
    DateTime? updatedAt,
  }) {
    return ArticleReadingProgress(
      articleId: articleId,
      articleTitle: articleTitle ?? this.articleTitle,
      articleLevel: articleLevel ?? this.articleLevel,
      progress: (progress ?? this.progress).clamp(0.0, 1.0).toDouble(),
      scrollOffset: (scrollOffset ?? this.scrollOffset) < 0
          ? 0
          : (scrollOffset ?? this.scrollOffset),
      audioPositionMs: (audioPositionMs ?? this.audioPositionMs) < 0
          ? 0
          : (audioPositionMs ?? this.audioPositionMs),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'articleId': articleId,
      'articleTitle': articleTitle,
      'articleLevel': articleLevel,
      'progress': clampedProgress,
      'scrollOffset': scrollOffset < 0 ? 0.0 : scrollOffset,
      'audioPositionMs': audioPositionMs < 0 ? 0 : audioPositionMs,
      'updatedAt': updatedAt.toUtc().millisecondsSinceEpoch,
    };
  }

  static ArticleReadingProgress? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final articleId = (raw['articleId'] as String? ?? '').trim();
    if (articleId.isEmpty) return null;

    final articleTitle = (raw['articleTitle'] as String? ?? '').trim();
    final articleLevel = (raw['articleLevel'] as String? ?? '').trim();
    final rawProgress = raw['progress'];
    final parsedProgress = rawProgress is num
        ? rawProgress.toDouble()
        : double.tryParse(rawProgress?.toString() ?? '') ?? 0.0;
    final rawOffset = raw['scrollOffset'];
    final parsedOffset = rawOffset is num
        ? rawOffset.toDouble()
        : double.tryParse(rawOffset?.toString() ?? '') ?? 0.0;
    final rawAudioPos = raw['audioPositionMs'];
    final parsedAudioPos = rawAudioPos is int
        ? rawAudioPos
        : int.tryParse(rawAudioPos?.toString() ?? '') ?? 0;
    final rawUpdated = raw['updatedAt'];
    final updatedMs = rawUpdated is int
        ? rawUpdated
        : int.tryParse(rawUpdated?.toString() ?? '');

    return ArticleReadingProgress(
      articleId: articleId,
      articleTitle: articleTitle,
      articleLevel: articleLevel,
      progress: parsedProgress.clamp(0.0, 1.0).toDouble(),
      scrollOffset: parsedOffset < 0 ? 0.0 : parsedOffset,
      audioPositionMs: parsedAudioPos < 0 ? 0 : parsedAudioPos,
      updatedAt: updatedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(updatedMs, isUtc: true)
          : DateTime.now().toUtc(),
    );
  }
}
