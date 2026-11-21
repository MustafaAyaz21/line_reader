import 'package:flutter/material.dart';

import '../../../core/tts/tts_service.dart';
import '../../translation/models/word_meaning.dart';
import '../models/saved_word.dart';

/// Kelimelerim listesinde tek bir kayıtlı kelimeyi gösteren genişletilebilir satır:
/// - Kapalı (varsayılan) durumda 1. anlamın yanında diğer anlamlar yan yana sıralanır.
/// - Kelimeye tıklandığında 4 anlam numaralı şekilde alt alta açılır.
/// - Sağdaki hoparlör butonuyla kelime çift modlu (Gemini Ses / flutter_tts) dinlenebilir.
class WordListTile extends StatefulWidget {
  const WordListTile({
    super.key,
    required this.item,
    required this.onDelete,
    this.ttsService,
  });

  final SavedWord item;
  final VoidCallback onDelete;
  final TtsService? ttsService;

  @override
  State<WordListTile> createState() => _WordListTileState();
}

class _WordListTileState extends State<WordListTile> {
  bool _isExpanded = false;

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  Future<void> _handleSpeak() async {
    final tts = widget.ttsService;
    if (tts == null) return;
    await tts.toggleSpeak(
      text: widget.item.word,
      target: TtsSpeakingTarget.word,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allMeanings = widget.item.allMeanings;
    final ttsService = widget.ttsService;

    return InkWell(
      onTap: _toggleExpanded,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.word,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_isExpanded) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.item.inlineMeaningsText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (ttsService != null)
                  ListenableBuilder(
                    listenable: ttsService,
                    builder: (context, _) {
                      return _buildSpeakerButton(colorScheme, ttsService);
                    },
                  ),
                IconButton(
                  onPressed: _toggleExpanded,
                  icon: Icon(
                    _isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  tooltip: _isExpanded ? 'Daralt' : 'Anlamları Göster',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Sil',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              alignment: Alignment.topLeft,
              child: _isExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10, right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < allMeanings.length; i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            _buildExpandedMeaningRow(
                              theme: theme,
                              colorScheme: colorScheme,
                              number: i + 1,
                              entry: allMeanings[i],
                              isPrimary: i == 0,
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakerButton(ColorScheme colorScheme, TtsService ttsService) {
    final isActive = ttsService.isSpeakingText(
      widget.item.word,
      target: TtsSpeakingTarget.word,
    );
    final isLoading = isActive && ttsService.isLoadingAudio;

    if (isActive) {
      return IconButton.filled(
        onPressed: _handleSpeak,
        icon: isLoading
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.stop_rounded, size: 18),
        tooltip: isLoading ? 'Hazırlanıyor • İptal' : 'Durdur',
        visualDensity: VisualDensity.compact,
      );
    }

    return IconButton(
      onPressed: _handleSpeak,
      icon: Icon(
        Icons.volume_up_rounded,
        size: 20,
        color: colorScheme.primary,
      ),
      tooltip: 'Oku',
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildExpandedMeaningRow({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required int number,
    required MeaningEntry entry,
    required bool isPrimary,
  }) {
    final badgeBg =
        isPrimary ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final badgeFg =
        isPrimary ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: badgeBg,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelSmall?.copyWith(
              color: badgeFg,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: entry.translation,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w400,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (entry.partOfSpeech != null)
                  TextSpan(
                    text: ' (${entry.partOfSpeech!.label})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isPrimary
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (entry.isContextual)
                  TextSpan(
                    text: ' ${MeaningEntry.contextualTag}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
