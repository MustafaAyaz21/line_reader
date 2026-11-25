import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/settings/display_preferences_controller.dart';
import '../../../core/settings/ipa_accent_controller.dart';
import '../../translation/models/word_lexicon_info.dart';

/// Amerikan (US) ve İngiliz (UK) doğrulanmış IPA okunuşlarını kullanıcının
/// seçtiği moda (`both`, `usOnly`, `ukOnly`, `off`) göre kompakt haplar halinde gösterir.
class WordIpaBadge extends StatelessWidget {
  const WordIpaBadge({
    super.key,
    required this.lexiconInfo,
    this.accentController,
    this.displayPreferences,
    this.modeOverride,
    this.compact = false,
  });

  final WordLexiconInfo? lexiconInfo;
  final IpaAccentController? accentController;
  final DisplayPreferencesController? displayPreferences;
  final IpaDisplayMode? modeOverride;
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
    final prefs = displayPreferences ?? DisplayPreferencesController.shared;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, prefs]),
      builder: (context, _) {
        final effectiveMode = modeOverride ??
            (!controller.isEnabled ? IpaDisplayMode.off : prefs.appIpaMode);
        if (!effectiveMode.isEnabled) {
          return const SizedBox.shrink();
        }

        // Eğer kullanıcı tek aksan (örn. Sadece US) seçtiyse ve kelimede yalnızca
        // diğer aksan varsa yanlış etiket basmadan mevcut aksanı gösterir.
        var showUsPill = hasUs && effectiveMode.showUs;
        var showUkPill = hasUk && effectiveMode.showUk;
        if (!showUsPill && !showUkPill) {
          if (hasUs) {
            showUsPill = true;
          } else if (hasUk) {
            showUkPill = true;
          }
        }
        if (!showUsPill && !showUkPill) {
          return const SizedBox.shrink();
        }

        return Wrap(
          key: const ValueKey<String>('word_ipa_badge'),
          spacing: compact ? 5 : 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (showUsPill)
              _IpaPill(
                key: const ValueKey<String>('word_ipa_badge_us'),
                accentLabel: IpaAccent.us.shortLabel,
                tooltip: context.l10n.t(
                  IpaAccent.us.turkishLabel,
                  IpaAccent.us.englishLabel,
                ),
                ipa: cleanUs!,
                labelColor: colorScheme.primary,
                compact: compact,
              ),
            if (showUkPill)
              _IpaPill(
                key: const ValueKey<String>('word_ipa_badge_uk'),
                accentLabel: IpaAccent.uk.shortLabel,
                tooltip: context.l10n.t(
                  IpaAccent.uk.turkishLabel,
                  IpaAccent.uk.englishLabel,
                ),
                ipa: cleanUk!,
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

  static const Color _greenActiveBorder = Color(0xFF10B981);
  static const Color _greenActiveBg = Color(0x1F10B981);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected ? _greenActiveBg : colorScheme.surfaceContainerHighest.withAlpha(120),
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
                  ? _greenActiveBorder
                  : colorScheme.outlineVariant.withAlpha(140),
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                const Icon(Icons.check_rounded, size: 14, color: _greenActiveBorder),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  decoration: null, // Asla uzeri cizili gosterme, normal kelime gibi goster
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

/// Kelimenin İngilizce editoryal tanımı ve gerçek kullanım örnek cümlelerini
/// şık ve minimalist bir editoryal kutuda sunan bileşen.
class WordDefinitionAndExamplesSection extends StatelessWidget {
  const WordDefinitionAndExamplesSection({
    super.key,
    required this.lexiconInfo,
  });

  final WordLexiconInfo? lexiconInfo;

  @override
  Widget build(BuildContext context) {
    final info = lexiconInfo;
    if (info == null) return const SizedBox.shrink();

    final hasDef = info.hasDefinition;
    final hasEx = info.hasExamples;
    if (!hasDef && !hasEx) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = context.l10n;

    return Container(
      key: const ValueKey<String>('word_definition_examples_section'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(140),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasDef) ...[
            Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 15,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  s.t('İngilizce Tanım', 'English Definition'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              info.definition!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ],
          if (hasDef && hasEx) const SizedBox(height: 10),
          if (hasEx) ...[
            Row(
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  size: 16,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  s.t('Örnek Cümleler', 'Usage Examples'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final ex in info.examples)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        color: colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        ex,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
