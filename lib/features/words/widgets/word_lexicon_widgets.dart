import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/settings/ipa_accent_controller.dart';
import '../../translation/models/word_lexicon_info.dart';

/// Amerikan (US) ve İngiliz (UK) doğrulanmış IPA okunuşlarını kullanıcının tek
/// bir aksan seçmesine gerek kalmadan yan yana kompakt haplar halinde gösterir.
class WordIpaBadge extends StatelessWidget {
  const WordIpaBadge({
    super.key,
    required this.lexiconInfo,
    this.accentController,
    this.compact = false,
  });

  final WordLexiconInfo? lexiconInfo;
  final IpaAccentController? accentController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final info = lexiconInfo;
    if (info == null || !info.hasAnyIpa) {
      return const SizedBox.shrink();
    }

    final cleanUs = info.ipaUs?.trim();
    final cleanUk = info.ipaUk?.trim();
    final hasUs = cleanUs != null && cleanUs.isNotEmpty;
    final hasUk = cleanUk != null && cleanUk.isNotEmpty;
    if (!hasUs && !hasUk) {
      return const SizedBox.shrink();
    }

    final controller = accentController ?? IpaAccentController.shared;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isEnabled) {
          return const SizedBox.shrink();
        }
        return Wrap(
          key: const ValueKey<String>('word_ipa_badge'),
          spacing: compact ? 5 : 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (hasUs)
              _IpaPill(
                key: const ValueKey<String>('word_ipa_badge_us'),
                accentLabel: IpaAccent.us.shortLabel,
                tooltip: context.l10n.t(
                  IpaAccent.us.turkishLabel,
                  IpaAccent.us.englishLabel,
                ),
                ipa: cleanUs,
                labelColor: colorScheme.primary,
                compact: compact,
              ),
            if (hasUk)
              _IpaPill(
                key: const ValueKey<String>('word_ipa_badge_uk'),
                accentLabel: IpaAccent.uk.shortLabel,
                tooltip: context.l10n.t(
                  IpaAccent.uk.turkishLabel,
                  IpaAccent.uk.englishLabel,
                ),
                ipa: cleanUk,
                labelColor: colorScheme.tertiary,
                compact: compact,
              ),
          ],
        );
      },
    );
  }
}

class _IpaPill extends StatelessWidget {
  const _IpaPill({
    super.key,
    required this.accentLabel,
    required this.tooltip,
    required this.ipa,
    required this.labelColor,
    required this.compact,
  });

  final String accentLabel;
  final String tooltip;
  final String ipa;
  final Color labelColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 2.5 : 4,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(180),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              accentLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: compact ? 9.5 : 10,
                color: labelColor,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              ipa,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Buton yığını oluşturmadan eş ve zıt anlamları tek dokunuşla seçip
/// çıkarılabilen sade etiketler halinde sunar.
class WordRelationsSection extends StatelessWidget {
  const WordRelationsSection({
    super.key,
    required this.synonyms,
    required this.antonyms,
    required this.selectedSynonyms,
    required this.selectedAntonyms,
    required this.onToggleSynonym,
    required this.onToggleAntonym,
    required this.onToggleAll,
  });

  final List<String> synonyms;
  final List<String> antonyms;
  final Set<String> selectedSynonyms;
  final Set<String> selectedAntonyms;
  final ValueChanged<String> onToggleSynonym;
  final ValueChanged<String> onToggleAntonym;
  final ValueChanged<bool> onToggleAll;

  @override
  Widget build(BuildContext context) {
    if (synonyms.isEmpty && antonyms.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = context.l10n;

    final totalCount = synonyms.length + antonyms.length;
    final selectedCount = selectedSynonyms.length + selectedAntonyms.length;
    final allSelected = selectedCount >= totalCount;

    return Container(
      key: const ValueKey<String>('word_relations_section'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(150),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                s.t('Eş & Zıt Anlamlar', 'Synonyms & Antonyms'),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '($selectedCount/$totalCount)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              InkWell(
                key: const ValueKey<String>('word_relations_toggle_all'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => onToggleAll(!allSelected),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    allSelected
                        ? s.t('Hiçbiri', 'None')
                        : s.t('Tümü', 'All'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (synonyms.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              s.t('Eş anlamlılar', 'Synonyms'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: synonyms.map((term) {
                final isSelected = selectedSynonyms.contains(term);
                return _SelectableRelationChip(
                  key: ValueKey<String>('syn_chip_$term'),
                  label: term,
                  selected: isSelected,
                  accentColor: colorScheme.primary,
                  selectedBg: colorScheme.primaryContainer.withAlpha(170),
                  selectedFg: colorScheme.onPrimaryContainer,
                  onTap: () => onToggleSynonym(term),
                );
              }).toList(growable: false),
            ),
          ],
          if (antonyms.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              s.t('Zıt anlamlılar', 'Antonyms'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: antonyms.map((term) {
                final isSelected = selectedAntonyms.contains(term);
                return _SelectableRelationChip(
                  key: ValueKey<String>('ant_chip_$term'),
                  label: term,
                  selected: isSelected,
                  accentColor: colorScheme.tertiary,
                  selectedBg: colorScheme.tertiaryContainer.withAlpha(170),
                  selectedFg: colorScheme.onTertiaryContainer,
                  onTap: () => onToggleAntonym(term),
                );
              }).toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectableRelationChip extends StatelessWidget {
  const _SelectableRelationChip({
    super.key,
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.selectedBg,
    required this.selectedFg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final Color selectedBg;
  final Color selectedFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected ? selectedBg : colorScheme.surfaceContainerHighest.withAlpha(110),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? accentColor.withAlpha(130)
                  : colorScheme.outlineVariant.withAlpha(130),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                Icon(Icons.check_rounded, size: 13, color: selectedFg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? selectedFg
                      : colorScheme.onSurfaceVariant.withAlpha(165),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  decoration: selected ? null : TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hatalı yazılmış kelimelerde Google mantığıyla "Bunu mu aratmak istediniz?"
/// kartını gösterir; öneriye tıklandığında doğru kelimeyi anında aratır.
class DidYouMeanCard extends StatelessWidget {
  const DidYouMeanCard({
    super.key,
    required this.misspelledWord,
    required this.suggestions,
    required this.onSelectSuggestion,
  });

  final String misspelledWord;
  final List<String> suggestions;
  final ValueChanged<String> onSelectSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = context.l10n;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          key: const ValueKey<String>('did_you_mean_card'),
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.spellcheck_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.t(
                        '"$misspelledWord" sözlükte bulunamadı',
                        '"$misspelledWord" was not found',
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (suggestions.isNotEmpty) ...<Widget>[
                Text(
                  s.t(
                    'Bunu mu aratmak istediniz?',
                    'Did you mean:',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: suggestions.map((candidate) {
                    return ActionChip(
                      key: ValueKey<String>('suggestion_chip_$candidate'),
                      avatar: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      label: Text(
                        candidate,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: colorScheme.primaryContainer,
                      side: BorderSide(color: colorScheme.primary.withAlpha(90)),
                      onPressed: () => onSelectSuggestion(candidate),
                    );
                  }).toList(growable: false),
                ),
              ] else ...<Widget>[
                Text(
                  s.t(
                    'Kelimenin yazılışını kontrol edip tekrar deneyin.',
                    'Please check the spelling and try again.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
