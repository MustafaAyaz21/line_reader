import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_backdrop.dart';
import '../../../../core/tts/tts_service.dart';
import '../../models/saved_word.dart';
import '../../models/word_list.dart';
import 'flashcards_screen.dart';
import 'word_match_screen.dart';
import 'word_quiz_screen.dart';

/// Öğrenme Alanı (Mod Seçimi / Oyun Merkezi) Ekranı.
class WordLearningHubScreen extends StatelessWidget {
  const WordLearningHubScreen({
    super.key,
    required this.wordList,
    required this.words,
    required this.ttsService,
  });

  final WordList wordList;
  final List<SavedWord> words;
  final TtsService ttsService;

  static const int minWordsRequired = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visuals = AppThemeVisuals.of(context);

    final canPlay = words.length >= minWordsRequired;

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 10,
                height: 22,
                decoration: BoxDecoration(
                  color: wordList.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${wordList.name} • Öğrenme Alanı',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Bilgi Vitrini Banner'ı
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.brightness == Brightness.dark
                        ? const Color(0xFF171D28)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFFF59E0B),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pekiştirmeye Hazır',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF59E0B),
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              wordList.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${words.length} kayıtlı kelime mevcut',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'ÇALIŞMA MODLARI',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),

                if (!canPlay)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: colorScheme.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Öğrenme modlarını başlatabilmek için listede en az $minWordsRequired kelime bulunmalıdır (Şu an ${words.length} kelime var).',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 1. Mod: Kelime Kartları
                _buildModeCard(
                  context: context,
                  theme: theme,
                  colorScheme: colorScheme,
                  emoji: '🃏',
                  title: 'Kelime Kartları',
                  accentColor: const Color(0xFF6366F1),
                  enabled: canPlay,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FlashcardsScreen(
                          wordList: wordList,
                          words: words,
                          ttsService: ttsService,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // 2. Mod: Kelime Testi
                _buildModeCard(
                  context: context,
                  theme: theme,
                  colorScheme: colorScheme,
                  emoji: '🎯',
                  title: 'Kelime Testi',
                  accentColor: const Color(0xFF10B981),
                  enabled: canPlay,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => WordQuizScreen(
                          wordList: wordList,
                          words: words,
                          ttsService: ttsService,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // 3. Mod: Anlam Eşleştirme
                _buildModeCard(
                  context: context,
                  theme: theme,
                  colorScheme: colorScheme,
                  emoji: '🧩',
                  title: 'Anlam Eşleştirme',
                  accentColor: const Color(0xFFF59E0B),
                  enabled: canPlay,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => WordMatchScreen(
                          wordList: wordList,
                          words: words,
                          ttsService: ttsService,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String emoji,
    required String title,
    required Color accentColor,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: colorScheme.brightness == Brightness.dark
                ? const Color(0xFF171D28)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
