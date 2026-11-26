import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_backdrop.dart';
import '../../../../core/tts/tts_service.dart';
import '../../models/saved_word.dart';
import '../../models/word_list.dart';

/// 4 Şıklı Kelime Testi Ekranı.
class WordQuizScreen extends StatefulWidget {
  const WordQuizScreen({
    super.key,
    required this.wordList,
    required this.words,
    required this.ttsService,
  });

  final WordList wordList;
  final List<SavedWord> words;
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
  int _score = 0;
  int? _selectedOptionIndex;
  bool _isAnswered = false;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _buildQuestions();
  }

  void _buildQuestions() {
    final list = List<SavedWord>.from(widget.words)..shuffle();
    final random = math.Random();
    final questions = <_QuizQuestion>[];

    for (int i = 0; i < list.length; i++) {
      final target = list[i];
      final correctAnswer = target.meaning;

      // Çeldiricileri listedeki diğer kelimelerden seç
      final wrongPool = widget.words
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

      // 4 seçenek dolmadıysa yedek ekle
      while (options.length < 4 && options.length < widget.words.length) {
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
      _score = 0;
      _selectedOptionIndex = null;
      _isAnswered = false;
      _isFinished = false;
    });
  }

  void _selectOption(int index) {
    if (_isAnswered || _isFinished) return;

    final q = _questions[_currentIndex];
    final isCorrect = index == q.correctIndex;

    setState(() {
      _selectedOptionIndex = index;
      _isAnswered = true;
      if (isCorrect) {
        _score++;
      }
    });

    // 1.1 saniye sonra bir sonraki soruya geç
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
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
            'Kelime Testi • ${widget.wordList.name}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: _buildQuestions,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Yeniden Başlat',
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

  Widget _buildQuizView(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    if (_questions.isEmpty) {
      return const Center(child: Text('Test oluşturulamadı.'));
    }

    final total = _questions.length;
    final progress = (_currentIndex + 1) / total;
    final q = _questions[_currentIndex];
    final target = q.targetWord;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Soru Başlığı ve İlerleme
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Doğru: $_score',
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
              valueColor: AlwaysStoppedAnimation<Color>(widget.wordList.color),
            ),
          ),
          const SizedBox(height: 24),

          // Soru Kartı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
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
                const SizedBox(height: 12),
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

          const SizedBox(height: 20),

          // 4 Şık
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: q.options.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final optionText = q.options[index];
                final isSelected = _selectedOptionIndex == index;
                final isCorrectOption = index == q.correctIndex;

                Color borderColor = colorScheme.outlineVariant.withValues(alpha: 0.5);
                Color bgColor = colorScheme.brightness == Brightness.dark
                    ? const Color(0xFF171D28)
                    : Colors.white;
                Color textColor = colorScheme.onSurface;

                if (_isAnswered) {
                  if (isCorrectOption) {
                    borderColor = const Color(0xFF10B981);
                    bgColor = const Color(0xFF10B981).withValues(alpha: 0.15);
                    textColor = const Color(0xFF10B981);
                  } else if (isSelected) {
                    borderColor = const Color(0xFFEF4444);
                    bgColor = const Color(0xFFEF4444).withValues(alpha: 0.15);
                    textColor = const Color(0xFFEF4444);
                  }
                }

                final letter = String.fromCharCode(65 + index); // A, B, C, D

                return InkWell(
                  onTap: _isAnswered ? null : () => _selectOption(index),
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20)
                        else if (_isAnswered && isSelected)
                          const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryView(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final total = _questions.length;
    final rate = total > 0 ? ((_score / total) * 100).round() : 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  color: Color(0xFF10B981),
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Test Tamamlandı!',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$total sorudan $_score tanesini doğru bildiniz (%$rate)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _buildQuestions,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Testi Yeniden Başlat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.wordList.color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
