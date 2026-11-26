import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/tts/tts_service.dart';
import '../../translation/models/word_meaning.dart';
import '../models/saved_word.dart';
import 'word_lexicon_widgets.dart';

/// Kelimelerim listesinde tek bir kayıtlı kelimeyi gösteren modern cam kart:
/// - Buzlu cam dokusu, tema rengine duyarlı çerçeve ve gölge.
/// - Kapalı durumda anlamlar rozetler (pills) halinde derli toplu gösterilir.
/// - Kelimeye tıklandığında akıcı animasyonla 4 anlam numaralı şekilde açılır.
/// - Sağ üstteki ergonomik butonlarla telaffuz dinleme, düzenleme ve silme.
class WordListTile extends StatefulWidget {
  const WordListTile({
    super.key,
    required this.item,
    required this.onDelete,
    this.onEdit,
    this.ttsService,
    this.accentColor,
  });

  final SavedWord item;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final TtsService? ttsService;
  final Color? accentColor;

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
    final isDark = theme.brightness == Brightness.dark;
    final visuals = AppThemeVisuals.of(context);
    final hasBackdrop = visuals.hasBackdrop;
    final allMeanings = widget.item.allMeanings;
    final ttsService = widget.ttsService;

    // Tema ve arka plan efektlerine göre cam kart renklerini dinamik hesapla
    final cardBg = isDark
        ? (hasBackdrop
            ? colorScheme.surfaceContainerHighest.withOpacity(0.55)
            : colorScheme.surfaceContainer.withOpacity(0.85))
        : (hasBackdrop
            ? colorScheme.surface.withOpacity(0.88)
            : colorScheme.surface);

    final borderColor = isDark
        ? (hasBackdrop
            ? (widget.accentColor?.withOpacity(0.35) ??
                colorScheme.primary.withOpacity(0.22))
            : colorScheme.outlineVariant.withOpacity(0.40))
        : colorScheme.outlineVariant.withOpacity(0.60);

    final cardShadow = isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(hasBackdrop ? 0.35 : 0.20),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isExpanded
              ? (widget.accentColor ?? colorScheme.primary).withOpacity(0.55)
              : borderColor,
          width: _isExpanded ? 1.5 : 1.0,
        ),
        boxShadow: cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _toggleExpanded,
          splashColor:
              (widget.accentColor ?? colorScheme.primary).withOpacity(0.08),
          highlightColor:
              (widget.accentColor ?? colorScheme.primary).withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Üst Başlık Satırı: Kelime, IPA rozeti ve Aksiyon Butonları
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            widget.item.word,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (widget.item.lexiconInfo != null)
                            WordIpaBadge(
                              lexiconInfo: widget.item.lexiconInfo,
                              compact: true,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Aksiyon Butonları Grubu
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (ttsService != null)
                          ListenableBuilder(
                            listenable: ttsService,
                            builder: (context, _) {
                              return _buildSpeakerButton(colorScheme, ttsService);
                            },
                          ),
                        if (widget.onEdit != null)
                          IconButton(
                            onPressed: widget.onEdit,
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Anlamları Düzenle',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        IconButton(
                          onPressed: widget.onDelete,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: colorScheme.error.withOpacity(0.85),
                          ),
                          tooltip: 'Sil',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          onPressed: _toggleExpanded,
                          icon: AnimatedRotation(
                            turns: _isExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          tooltip: _isExpanded ? 'Daralt' : 'Detayları Göster',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ],
                ),

                // Kapalı Durumda: Anlam Hapları (Pills)
                if (!_isExpanded) ...[
                  const SizedBox(height: 8),
                  if (allMeanings.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry in allMeanings)
                          _buildMeaningPill(theme, colorScheme, entry),
                      ],
                    )
                  else
                    Text(
                      widget.item.meaning,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],

                // Açık Durumda: Numaralı Anlamlar ve Detaylar
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topLeft,
                  child: _isExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: colorScheme.outlineVariant.withOpacity(0.25),
                              ),
                              const SizedBox(height: 10),
                              for (var i = 0; i < allMeanings.length; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                _buildExpandedMeaningRow(
                                  theme: theme,
                                  colorScheme: colorScheme,
                                  number: i + 1,
                                  entry: allMeanings[i],
                                  isPrimary: i == 0,
                                ),
                              ],
                              if (widget.item.synonyms.isNotEmpty ||
                                  widget.item.antonyms.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildSavedRelationsBlock(theme, colorScheme),
                              ],
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMeaningPill(
    ThemeData theme,
    ColorScheme colorScheme,
    MeaningEntry entry,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withOpacity(0.85),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.28),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.partOfSpeech != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: (widget.accentColor ?? colorScheme.primary).withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.partOfSpeech!.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: widget.accentColor ?? colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              entry.translation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 12.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
      return Container(
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: (widget.accentColor ?? colorScheme.primary).withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          onPressed: _handleSpeak,
          icon: isLoading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.accentColor ?? colorScheme.primary,
                  ),
                )
              : Icon(
                  Icons.stop_rounded,
                  size: 18,
                  color: widget.accentColor ?? colorScheme.primary,
                ),
          tooltip: isLoading ? 'Hazırlanıyor • İptal' : 'Durdur',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: (widget.accentColor ?? colorScheme.primary).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        onPressed: _handleSpeak,
        icon: Icon(
          Icons.volume_up_rounded,
          size: 18,
          color: widget.accentColor ?? colorScheme.primary,
        ),
        tooltip: 'Telaffuzu Dinle',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildExpandedMeaningRow({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required int number,
    required MeaningEntry entry,
    required bool isPrimary,
  }) {
    final badgeBg = isPrimary
        ? (widget.accentColor ?? colorScheme.primary)
        : colorScheme.surfaceContainerHighest;
    final badgeFg = isPrimary
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(top: 2),
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
        const SizedBox(width: 10),
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
                          ? (widget.accentColor ?? colorScheme.primary)
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

  Widget _buildSavedRelationsBlock(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.25),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.item.synonyms.isNotEmpty)
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'Eş anlamlar: ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: widget.accentColor ?? colorScheme.primary,
                    ),
                  ),
                  TextSpan(
                    text: widget.item.synonyms.join(', '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.item.synonyms.isNotEmpty &&
              widget.item.antonyms.isNotEmpty)
            const SizedBox(height: 4),
          if (widget.item.antonyms.isNotEmpty)
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'Zıt anlamlar: ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.tertiary,
                    ),
                  ),
                  TextSpan(
                    text: widget.item.antonyms.join(', '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
