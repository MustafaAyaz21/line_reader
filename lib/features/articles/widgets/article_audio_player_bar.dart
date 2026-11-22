import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../controllers/article_audio_controller.dart';
import '../models/article_reader_models.dart';

/// Makale okuma ekranının altına yerleşen, aktif okuma tonuna (`Beyaz`,
/// `Kağıt Tonu`, `Koyu`) uyumlu çift motorlu (Podcast AI + Cihaz Sesi)
/// cümle/paragraf kontrollü sesli okuma çubuğu.
class ArticleAudioPlayerBar extends StatelessWidget {
  const ArticleAudioPlayerBar({
    super.key,
    required this.controller,
    required this.tone,
  });

  final ArticleAudioController controller;
  final ArticleReaderTone tone;

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _formatSpeed(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toStringAsFixed(0)}x';
    }
    return '${speed}x';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final palette = tone.resolvePalette(context);
    final isPodcast = controller.mode == ArticleAudioMode.podcastAudio;
    final accent = palette.underlineColor;

    final paragraphNum = controller.currentParagraphIndex + 1;
    final totalParagraphs =
        controller.totalParagraphs > 0 ? controller.totalParagraphs : 1;
    final sentenceNum = controller.currentSentenceIndex + 1;
    final totalSentences =
        controller.totalSentences > 0 ? controller.totalSentences : 1;

    final showTime = isPodcast && controller.duration.inMilliseconds > 0;

    return Material(
      key: const ValueKey<String>('article_audio_player_bar'),
      color: palette.surfaceColor,
      elevation: 8,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: palette.dividerColor, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<Duration>(
                valueListenable: controller.positionNotifier,
                builder: (context, _, __) {
                  return LinearProgressIndicator(
                    value: controller.isLoading
                        ? null
                        : controller.progressFraction,
                    minHeight: 2.5,
                    color: accent,
                    backgroundColor: palette.dividerColor.withAlpha(110),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Üst satır: Mod etiketi + Cümle/Paragraf bilgisi + Kapat
                    Row(
                      children: <Widget>[
                        InkWell(
                          key: const ValueKey<String>(
                            'audio_mode_toggle_button',
                          ),
                          borderRadius: BorderRadius.circular(999),
                          onTap: controller.hasPodcastAudio
                              ? controller.toggleEngineMode
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isPodcast
                                  ? accent.withAlpha(34)
                                  : palette.dividerColor.withAlpha(120),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  isPodcast
                                      ? Icons.podcasts_rounded
                                      : Icons.record_voice_over_rounded,
                                  size: 14,
                                  color: isPodcast
                                      ? accent
                                      : palette.secondaryTextColor,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isPodcast
                                      ? s.podcastAiLabel
                                      : s.deviceVoiceLabel,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: isPodcast
                                        ? accent
                                        : palette.textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ValueListenableBuilder<Duration>(
                            valueListenable: controller.positionNotifier,
                            builder: (context, pos, _) {
                              return Text(
                                showTime
                                    ? '${_formatDuration(pos)} / ${_formatDuration(controller.duration)} • C$sentenceNum/$totalSentences'
                                    : s.audioPositionLabel(
                                        paragraphNum,
                                        totalParagraphs,
                                        sentenceNum,
                                        totalSentences,
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.secondaryTextColor,
                                ),
                              );
                            },
                          ),
                        ),
                        IconButton(
                          key: const ValueKey<String>('audio_close_button'),
                          onPressed: controller.closePlayer,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: palette.secondaryTextColor,
                          ),
                          tooltip: s.close,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),

                    if (controller.statusNotice != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          controller.statusNotice!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.secondaryTextColor,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 6),

                    // Alt satır: Hız + Paragraf/Cümle Geri + Oynat/Duraklat + Cümle/Paragraf İleri + Aksan
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        // Hız butonu (0.75x - 1.5x)
                        InkWell(
                          key: const ValueKey<String>('audio_speed_button'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: controller.cycleSpeed,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: palette.dividerColor),
                            ),
                            child: Text(
                              _formatSpeed(controller.playbackSpeed),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: palette.textColor,
                              ),
                            ),
                          ),
                        ),

                        // Önceki Paragraf
                        IconButton(
                          key: const ValueKey<String>(
                            'audio_prev_paragraph_button',
                          ),
                          onPressed: controller.previousParagraph,
                          tooltip: s.previousParagraphTooltip,
                          icon: Icon(
                            Icons.fast_rewind_rounded,
                            size: 22,
                            color: palette.textColor,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),

                        // Önceki Cümle
                        IconButton(
                          key: const ValueKey<String>(
                            'audio_prev_sentence_button',
                          ),
                          onPressed: controller.canGoPreviousSentence
                              ? controller.previousSentence
                              : null,
                          tooltip: s.previousSentenceTooltip,
                          icon: Icon(
                            Icons.skip_previous_rounded,
                            size: 26,
                            color: controller.canGoPreviousSentence
                                ? palette.textColor
                                : palette.secondaryTextColor.withAlpha(110),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),

                        // Oynat / Duraklat ana düğmesi
                        SizedBox(
                          width: 46,
                          height: 46,
                          child: FilledButton(
                            key: const ValueKey<String>(
                              'audio_play_pause_button',
                            ),
                            onPressed: controller.isLoading
                                ? null
                                : controller.togglePlayPause,
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                              backgroundColor: accent,
                              foregroundColor:
                                  palette.brightness == Brightness.dark
                                      ? const Color(0xFF0A1428)
                                      : Colors.white,
                            ),
                            child: controller.isLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color:
                                          palette.brightness == Brightness.dark
                                              ? const Color(0xFF0A1428)
                                              : Colors.white,
                                    ),
                                  )
                                : Icon(
                                    controller.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 26,
                                  ),
                          ),
                        ),

                        // Sonraki Cümle
                        IconButton(
                          key: const ValueKey<String>(
                            'audio_next_sentence_button',
                          ),
                          onPressed: controller.canGoNextSentence
                              ? controller.nextSentence
                              : null,
                          tooltip: s.nextSentenceTooltip,
                          icon: Icon(
                            Icons.skip_next_rounded,
                            size: 26,
                            color: controller.canGoNextSentence
                                ? palette.textColor
                                : palette.secondaryTextColor.withAlpha(110),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),

                        // Sonraki Paragraf
                        IconButton(
                          key: const ValueKey<String>(
                            'audio_next_paragraph_button',
                          ),
                          onPressed: controller.canGoNextParagraph
                              ? controller.nextParagraph
                              : null,
                          tooltip: s.nextParagraphTooltip,
                          icon: Icon(
                            Icons.fast_forward_rounded,
                            size: 22,
                            color: controller.canGoNextParagraph
                                ? palette.textColor
                                : palette.secondaryTextColor.withAlpha(110),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),

                        // Sağ uç: Cihaz TTS'te US/UK aksanı; Podcast'ta başa sar/durdur
                        if (!isPodcast)
                          InkWell(
                            key: const ValueKey<String>('audio_accent_button'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: controller.toggleAccent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: palette.dividerColor),
                              ),
                              child: Text(
                                controller.accent.shortLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                ),
                              ),
                            ),
                          )
                        else
                          IconButton(
                            key: const ValueKey<String>('audio_stop_button'),
                            onPressed: controller.stop,
                            tooltip: s.t('Başa Sar', 'Restart'),
                            icon: Icon(
                              Icons.replay_rounded,
                              size: 20,
                              color: palette.secondaryTextColor,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
