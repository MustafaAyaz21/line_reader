import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_backdrop.dart';
import '../../../../core/tts/tts_service.dart';
import '../../models/saved_word.dart';

/// Anlam Eşleştirme Ekranı — Seçenek 1: İki Sütunlu Köprü.
/// Sol sütunda İngilizce kelimeler, sağ sütunda Türkçe karşılıkları yer alır.
/// Hem mobilde hem masaüstünde devasa kutular olmadan tek ekrana sığar.
class WordMatchScreen extends StatefulWidget {
  const WordMatchScreen({
    super.key,
    required this.title,
    required this.accentColor,
    required this.words,
    required this.ttsService,
  });

  final String title;
  final Color accentColor;
  final List<SavedWord> words;
  final TtsService ttsService;

  @override
  State<WordMatchScreen> createState() => _WordMatchScreenState();
}

class _MatchNode {
  _MatchNode({
    required this.pairId,
    required this.text,
  });

  final int pairId;
  final String text;
  bool isMatched = false;
}

class _WordMatchScreenState extends State<WordMatchScreen> {
  late List<_MatchNode> _leftColumn; // İngilizce kelimeler
  late List<_MatchNode> _rightColumn; // Türkçe anlamlar

  _MatchNode? _selectedLeft;
  _MatchNode? _selectedRight;
  bool _isLock = false;
  bool _isErrorFlash = false;
  int _moves = 0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _setupGame();
  }

  void _setupGame() {
    final pool = List<SavedWord>.from(widget.words)..shuffle();
    final selectedWords = pool.take(6).toList();

    final left = <_MatchNode>[];
    final right = <_MatchNode>[];

    for (int i = 0; i < selectedWords.length; i++) {
      final w = selectedWords[i];
      left.add(_MatchNode(pairId: i, text: w.word));
      right.add(_MatchNode(pairId: i, text: w.meaning));
    }

    left.shuffle();
    right.shuffle();

    setState(() {
      _leftColumn = left;
      _rightColumn = right;
      _selectedLeft = null;
      _selectedRight = null;
      _isLock = false;
      _isErrorFlash = false;
      _moves = 0;
      _isFinished = false;
    });
  }

  void _onTapLeft(_MatchNode node) {
    if (_isLock || node.isMatched) return;
    widget.ttsService.toggleSpeak(
      text: node.text,
      target: TtsSpeakingTarget.word,
    );
    setState(() {
      _selectedLeft = (_selectedLeft == node) ? null : node;
    });
    _checkPair();
  }

  void _onTapRight(_MatchNode node) {
    if (_isLock || node.isMatched) return;
    setState(() {
      _selectedRight = (_selectedRight == node) ? null : node;
    });
    _checkPair();
  }

  void _checkPair() {
    final left = _selectedLeft;
    final right = _selectedRight;
    if (left == null || right == null) return;

    setState(() {
      _isLock = true;
      _moves++;
    });

    if (left.pairId == right.pairId) {
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (!mounted) return;
        setState(() {
          left.isMatched = true;
          right.isMatched = true;
          _selectedLeft = null;
          _selectedRight = null;
          _isLock = false;
          _isFinished = _leftColumn.every((n) => n.isMatched);
        });
      });
    } else {
      setState(() => _isErrorFlash = true);
      Future<void>.delayed(const Duration(milliseconds: 550), () {
        if (!mounted) return;
        setState(() {
          _selectedLeft = null;
          _selectedRight = null;
          _isErrorFlash = false;
          _isLock = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visuals = AppThemeVisuals.of(context);

    final remaining = _leftColumn.where((t) => !t.isMatched).length;

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
        appBar: AppBar(
          title: Text(
            'Anlam Eşleştirme • ${widget.title}',
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
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Üst Bilgi Çubuğu
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
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

                          // Sütun Başlıkları
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'İNGİLİZCE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'TÜRKÇE KARŞILIĞI',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // İki Sütunlu Kompakt Eşleştirme Listesi
                          Expanded(
                            child: SingleChildScrollView(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Sol Sütun (İngilizce)
                                  Expanded(
                                    child: Column(
                                      children: _leftColumn.map((node) {
                                        final isSelected = _selectedLeft == node;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child: _buildColumnTile(
                                            context: context,
                                            colorScheme: colorScheme,
                                            node: node,
                                            isSelected: isSelected,
                                            isBold: true,
                                            onTap: () => _onTapLeft(node),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Sağ Sütun (Türkçe)
                                  Expanded(
                                    child: Column(
                                      children: _rightColumn.map((node) {
                                        final isSelected = _selectedRight == node;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child: _buildColumnTile(
                                            context: context,
                                            colorScheme: colorScheme,
                                            node: node,
                                            isSelected: isSelected,
                                            isBold: false,
                                            onTap: () => _onTapRight(node),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildColumnTile({
    required BuildContext context,
    required ColorScheme colorScheme,
    required _MatchNode node,
    required bool isSelected,
    required bool isBold,
    required VoidCallback onTap,
  }) {
    final baseSurface = colorScheme.brightness == Brightness.dark
        ? const Color(0xFF171D28)
        : Colors.white;

    Color borderColor = colorScheme.outlineVariant.withValues(alpha: 0.6);
    Color bgColor = baseSurface;
    Color textColor = colorScheme.onSurface;
    IconData trailingIcon = Icons.radio_button_unchecked_rounded;
    Color iconColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    if (node.isMatched) {
      borderColor = const Color(0xFF10B981).withValues(alpha: 0.5);
      bgColor = const Color(0xFF10B981).withValues(alpha: 0.14);
      textColor = const Color(0xFF10B981);
      trailingIcon = Icons.check_circle_rounded;
      iconColor = const Color(0xFF10B981);
    } else if (isSelected) {
      if (_isErrorFlash) {
        borderColor = const Color(0xFFEF4444);
        bgColor = const Color(0xFFEF4444).withValues(alpha: 0.15);
        textColor = const Color(0xFFEF4444);
        trailingIcon = Icons.cancel_rounded;
        iconColor = const Color(0xFFEF4444);
      } else {
        borderColor = const Color(0xFFF59E0B);
        bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.14);
        textColor = const Color(0xFFF59E0B);
        trailingIcon = Icons.circle;
        iconColor = const Color(0xFFF59E0B);
      }
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: node.isMatched ? 0.45 : 1.0,
      child: InkWell(
        onTap: node.isMatched ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  node.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isBold ? 14 : 12.5,
                    fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 16, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinishedView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final surfaceColor = colorScheme.brightness == Brightness.dark
        ? const Color(0xFF171D28)
        : Colors.white;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.celebration_rounded,
                    color: Color(0xFF10B981),
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tüm Çiftler Eşleşti!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_moves hamlede tüm eşleşmeleri tamamladınız.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _setupGame,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Yeni Tur Başlat'),
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
            ),
          ),
        ),
      ),
    );
  }
}
