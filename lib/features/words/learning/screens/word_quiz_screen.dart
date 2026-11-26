import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_backdrop.dart';
import '../../../../core/tts/tts_service.dart';
import '../../models/saved_word.dart';
import '../services/word_learning_progress_service.dart';

/// 4 Şıklı Kelime Testi Ekranı — Seçenek 1: Sekmeli İnceleme Sonuç Ekranı.
class WordQuizScreen extends StatefulWidget {
  const WordQuizScreen({
    super.key,
    required this.title,
    required this.accentColor,
    required this.words,
    required this.allPoolWords,
    required this.ttsService,
  });

  final String title;
  final Color accentColor;
  final List<SavedWord> words;

  /// Çeldiricilerin üretileceği tüm kelime havuzu (az kelimeli tekrarlarda 4 şık kurabilmek için).
  final List<SavedWord> allPoolWords;
  final TtsService ttsService;

  @override
  State<WordQuizScreen> createState() => _WordQuizScreenState();
}

class _QuizQuestion {
  const _QuizQuestion({
    required this.targetWord,
    required this.options,
    required this.correctIndex,
  });

  final SavedWord targetWord;
  final List<String> options;
  final int correctIndex;
}

class _WordQuizScreenState extends State<WordQuizScreen> {
  late List<_QuizQuestion> _questions;
  int _currentIndex = 0;
  final List<SavedWord> _correctWords = <SavedWord>[];
  final List<SavedWord> _wrongWords = <SavedWord>[];

  int? _selectedOptionIndex;
  bool _isAnswered = false;
  bool _isFinished = false;
  bool _showWrongTab = true;

  @override
  void initState() {
    super.initState();
    _buildQuestions(widget.words);
  }

  void _buildQuestions(List<SavedWord> sourceWords) {
    final list = List<SavedWord>.from(sourceWords)..shuffle();
    final random = math.Random();
    final questions = <_QuizQuestion>[];
    final pool = widget.allPoolWords.length >= 4
        ? widget.allPoolWords
        : widget.words;

    for (int i = 0; i < list.length; i++) {
      final target = list[i];
      final correctAnswer = target.meaning;

      final wrongPool = pool
          .where((w) => w.word.toLowerCase() != target.word.toLowerCase())
          .map((w) => w.meaning)
          .toSet()
          .toList()
        ..shuffle();

      final options = <String>[correctAnswer];
      for (final wrong in wrongPool) {
        if (options.length >= 4) break;
        if (!options.contains(wrong)) {
          options.add(wrong);
        }
      }

      while (options.length < 4 && options.length < pool.length) {
        options.add('Seçenek ${options.length + 1}');
      }

      options.shuffle(random);
      final correctIdx = options.indexOf(correctAnswer);

      questions.add(
        _QuizQuestion(
          targetWord: target,
          options: options,
          correctIndex: correctIdx,
        ),
      );
    }

    setState(() {
      _questions = questions;
      _currentIndex = 0;
      _correctWords.clear();
      _wrongWords.clear();
      _selectedOptionIndex = null;
      _isAnswered = false;
      _isFinished = false;
      _showWrongTab = true;
    });
  }

  void _selectOption(int index) {
    if (_isAnswered || _isFinished) return;

    final q = _questions[_currentIndex];
    final isCorrect = index == q.correctIndex;

    if (isCorrect) {
      _correctWords.add(q.targetWord);
      WordLearningProgressService.instance.markWordLearned(q.targetWord);
    } else {
      _wrongWords.add(q.targetWord);
      WordLearningProgressService.instance.markWordUnlearned(q.targetWord);
    }

    setState(() {
      _selectedOptionIndex = index;
      _isAnswered = true;
    });

    Future<void>.delayed(const Duration(milliseconds: 1050), () {
      if (!mounted) return;
      if (_currentIndex + 1 < _questions.length) {
        setState(() {
          _currentIndex++;
          _selectedOptionIndex = null;
          _isAnswered = false;
        });
      } else {
        setState(() {
          _isFinished = true;
          _showWrongTab = _wrongWords.isNotEmpty;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visuals = AppThemeVisuals.of(context);

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
        appBar: AppBar(
          title: Text(
            'Kelime Testi • ${widget.title}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: () => _buildQuestions(widget.words),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Tümünü Tekrar Et',
            ),
          ],
        ),
        body: SafeArea(
          child: _isFinished
              ? _buildSummaryView(context, theme, colorScheme)
              : _buildQuizView(context, theme, colorScheme),
        ),
      ),
    );
  }

  Widget _buildQuizView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (_questions.isEmpty) {
      return const Center(child: Text('Test oluşturulamadı.'));
    }

    final total = _questions.length;
    final progress = (_currentIndex + 1) / total;
    final q = _questions[_currentIndex];
    final target = q.targetWord;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Soru ${_currentIndex + 1} / $total',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Doğru: ${_correctWords.length}',
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
                ),
              ),
              const SizedBox(height: 20),

              // Soru Kartı
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                decoration: BoxDecoration(
                  color: colorScheme.brightness == Brightness.dark
                      ? const Color(0xFF171D28)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DOĞRU KARŞILIĞI SEÇİN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () {
                            widget.ttsService.toggleSpeak(
                              text: target.word,
                              target: TtsSpeakingTarget.word,
                            );
                          },
                          icon: const Icon(Icons.volume_up_rounded, size: 20),
                          tooltip: 'Seslendir',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      target.word,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (target.ipaUs != null || target.ipaUk != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        target.ipaUs ?? target.ipaUk!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 4 Şık
              Expanded(
                child: ListView.separated(
                  itemCount: q.options.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final optionText = q.options[index];
                    final isSelected = _selectedOptionIndex == index;
                    final isCorrectOption = index == q.correctIndex;

                    Color borderColor =
                        colorScheme.outlineVariant.withValues(alpha: 0.5);
                    Color bgColor = colorScheme.brightness == Brightness.dark
                        ? const Color(0xFF171D28)
                        : Colors.white;
                    Color textColor = colorScheme.onSurface;

                    if (_isAnswered) {
                      if (isCorrectOption) {
                        borderColor = const Color(0xFF10B981);
                        bgColor =
                            const Color(0xFF10B981).withValues(alpha: 0.15);
                        textColor = const Color(0xFF10B981);
                      } else if (isSelected) {
                        borderColor = const Color(0xFFEF4444);
                        bgColor =
                            const Color(0xFFEF4444).withValues(alpha: 0.15);
                        textColor = const Color(0xFFEF4444);
                      }
                    }

                    final letter = String.fromCharCode(65 + index);

                    return InkWell(
                      onTap: _isAnswered ? null : () => _selectOption(index),
                      borderRadius: BorderRadius.circular(18),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                letter,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: textColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                optionText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ),
                            if (_isAnswered && isCorrectOption)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF10B981),
                                size: 20,
                              )
                            else if (_isAnswered && isSelected)
                              const Icon(
                                Icons.cancel_rounded,
                                color: Color(0xFFEF4444),
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Seçenek 1: Sekmeli İnceleme Sonuç Ekranı (Doğrular / Yanlışlar & 2 Aksiyon Butonu)
  Widget _buildSummaryView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final total = _questions.length;
    final rate = total > 0 ? ((_correctWords.length / total) * 100).round() : 0;
    final surfaceColor = colorScheme.brightness == Brightness.dark
        ? const Color(0xFF171D28)
        : Colors.white;
    final activeList = _showWrongTab ? _wrongWords : _correctWords;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Üst Skor Başlığı
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF10B981),
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Test Tamamlandı!',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '$total sorudan ${_correctWords.length} tanesini doğru bildiniz',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '%$rate',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Sekme Seçici (Yanlışlar / Doğrular)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showWrongTab = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _showWrongTab
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: _showWrongTab
                                  ? Border.all(
                                      color: const Color(0xFFEF4444)
                                          .withValues(alpha: 0.4),
                                    )
                                  : null,
                            ),
                            child: Text(
                              '✕ Yanlışlar (${_wrongWords.length})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _showWrongTab
                                    ? const Color(0xFFEF4444)
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showWrongTab = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: !_showWrongTab
                                  ? const Color(0xFF10B981).withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: !_showWrongTab
                                  ? Border.all(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.4),
                                    )
                                  : null,
                            ),
                            child: Text(
                              '✓ Doğrular (${_correctWords.length})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: !_showWrongTab
                                    ? const Color(0xFF10B981)
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Seçili Sekmedeki Kelime Listesi
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: activeList.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text(
                                _showWrongTab
                                    ? 'Harika! Yanlış bildiğiniz kelime yok.'
                                    : 'Henüz doğru bilinen kelime yok.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: activeList.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final w = activeList[index];
                              final accent = _showWrongTab
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF10B981);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                w.word,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                  color: accent,
                                                ),
                                              ),
                                              if (w.ipaUs != null ||
                                                  w.ipaUk != null) ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  w.ipaUs ?? w.ipaUk!,
                                                  style: TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 11,
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            w.meaning,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        widget.ttsService.toggleSpeak(
                                          text: w.word,
                                          target: TtsSpeakingTarget.word,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.volume_up_rounded,
                                        size: 18,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),

                const SizedBox(height: 18),

                // Alt 2 Buton: Öğrenmediklerimi Tekrar Et & Tümünü Tekrar Et
                if (_wrongWords.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _buildQuestions(List<SavedWord>.from(_wrongWords)),
                            icon: const Icon(Icons.replay_rounded, size: 18),
                            label: Text(
                              'Öğrenmediklerimi Tekrar Et (${_wrongWords.length})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () => _buildQuestions(widget.words),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              'Tümünü Tekrar Et (${widget.words.length})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _buildQuestions(widget.words),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text('Tümünü Tekrar Et (${widget.words.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
