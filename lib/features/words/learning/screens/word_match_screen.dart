import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_backdrop.dart';
import '../../../../core/tts/tts_service.dart';
import '../../models/saved_word.dart';
import '../../models/word_list.dart';

/// Anlam Eşleştirme Ekranı.
class WordMatchScreen extends StatefulWidget {
  const WordMatchScreen({
    super.key,
    required this.wordList,
    required this.words,
    required this.ttsService,
  });

  final WordList wordList;
  final List<SavedWord> words;
  final TtsService ttsService;

  @override
  State<WordMatchScreen> createState() => _WordMatchScreenState();
}

class _MatchItem {
  _MatchItem({
    required this.id,
    required this.wordId,
    required this.text,
    required this.isEnglish,
  });

  final String id;
  final int wordId;
  final String text;
  final bool isEnglish;
  bool isMatched = false;
}

class _WordMatchScreenState extends State<WordMatchScreen> {
  late List<_MatchItem> _tiles;
  _MatchItem? _firstSelected;
  _MatchItem? _secondSelected;
  bool _isLock = false;
  int _moves = 0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _setupGame();
  }

  void _setupGame() {
    final pool = List<SavedWord>.from(widget.words)..shuffle();
    // En fazla 6 kelime çifti (12 kart) seç
    final selectedWords = pool.take(6).toList();

    final tiles = <_MatchItem>[];
    for (int i = 0; i < selectedWords.length; i++) {
      final w = selectedWords[i];
      final wordId = w.id ?? i;
      tiles.add(_MatchItem(id: 'en_$wordId', wordId: wordId, text: w.word, isEnglish: true));
      tiles.add(_MatchItem(id: 'tr_$wordId', wordId: wordId, text: w.meaning, isEnglish: false));
    }

    tiles.shuffle();

    setState(() {
      _tiles = tiles;
      _firstSelected = null;
      _secondSelected = null;
      _isLock = false;
      _moves = 0;
      _isFinished = false;
    });
  }

  void _onTileTap(_MatchItem item) {
    if (_isLock || item.isMatched || item == _firstSelected) return;

    if (_firstSelected == null) {
      setState(() {
        _firstSelected = item;
      });
      if (item.isEnglish) {
        widget.ttsService.toggleSpeak(text: item.text, target: TtsSpeakingTarget.word);
      }
    } else {
      setState(() {
        _secondSelected = item;
        _isLock = true;
        _moves++;
      });

      if (item.isEnglish) {
        widget.ttsService.toggleSpeak(text: item.text, target: TtsSpeakingTarget.word);
      }

      // Eşleşme kontrolü
      final isMatch = _firstSelected!.wordId == item.wordId &&
          _firstSelected!.isEnglish != item.isEnglish;

      if (isMatch) {
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          setState(() {
            _firstSelected!.isMatched = true;
            _secondSelected!.isMatched = true;
            _firstSelected = null;
            _secondSelected = null;
            _isLock = false;
            _isFinished = _tiles.every((t) => t.isMatched);
          });
        });
      } else {
        Future<void>.delayed(const Duration(milliseconds: 650), () {
          if (!mounted) return;
          setState(() {
            _firstSelected = null;
            _secondSelected = null;
            _isLock = false;
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visuals = AppThemeVisuals.of(context);

    final remaining = _tiles.where((t) => !t.isMatched).length ~/ 2;

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
        appBar: AppBar(
          title: Text(
            'Anlam Eşleştirme • ${widget.wordList.name}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: _setupGame,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Yeniden Dağıt',
            ),
          ],
        ),
        body: SafeArea(
          child: _isFinished
              ? _buildFinishedView(context, theme, colorScheme)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Kalan Çift: $remaining',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Hamle: $_moves',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 2.2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _tiles.length,
                          itemBuilder: (context, index) {
                            final item = _tiles[index];
                            if (item.isMatched) {
                              return const SizedBox.shrink();
                            }

                            final isFirst = _firstSelected == item;
                            final isSecond = _secondSelected == item;
                            final isSelected = isFirst || isSecond;

                            Color borderColor = colorScheme.outlineVariant.withValues(alpha: 0.6);
                            Color bgColor = colorScheme.brightness == Brightness.dark
                                ? const Color(0xFF171D28)
                                : Colors.white;

                            if (isSelected) {
                              if (_secondSelected != null) {
                                final match = _firstSelected!.wordId == _secondSelected!.wordId &&
                                    _firstSelected!.isEnglish != _secondSelected!.isEnglish;
                                if (match) {
                                  borderColor = const Color(0xFF10B981);
                                  bgColor = const Color(0xFF10B981).withValues(alpha: 0.2);
                                } else {
                                  borderColor = const Color(0xFFEF4444);
                                  bgColor = const Color(0xFFEF4444).withValues(alpha: 0.2);
                                }
                              } else {
                                borderColor = const Color(0xFFF59E0B);
                                bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.15);
                              }
                            }

                            return InkWell(
                              onTap: () => _onTileTap(item),
                              borderRadius: BorderRadius.circular(16),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor, width: 1.5),
                                  boxShadow: [
                                    if (isSelected)
                                      BoxShadow(
                                        color: borderColor.withValues(alpha: 0.3),
                                        blurRadius: 10,
                                      ),
                                  ],
                                ),
                                child: Text(
                                  item.text,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: item.isEnglish ? 14 : 12,
                                    fontWeight: item.isEnglish ? FontWeight.w800 : FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
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
      ),
    );
  }

  Widget _buildFinishedView(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
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
                  Icons.celebration_rounded,
                  color: Color(0xFF10B981),
                  size: 40,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Tüm Çiftler Eşleşti!',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_moves hamlede panoyu temizlediniz.',
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
                  onPressed: _setupGame,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Yeni Tur Başlat'),
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
