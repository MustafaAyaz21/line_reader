import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_backdrop.dart';
import '../../../../core/tts/tts_service.dart';
import '../../models/saved_word.dart';
import '../../models/word_list.dart';

/// Kelime Kartları (Flashcards) Ekranı — Seçenek 2: Saf Renk Aurası & Deste Fiziği.
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({
    super.key,
    required this.wordList,
    required this.words,
    required this.ttsService,
  });

  final WordList wordList;
  final List<SavedWord> words;
  final TtsService ttsService;

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen>
    with TickerProviderStateMixin {
  late List<SavedWord> _shuffledWords;
  int _currentIndex = 0;
  final List<SavedWord> _knownWords = <SavedWord>[];
  final List<SavedWord> _repeatWords = <SavedWord>[];

  // 3D Flip controller
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _isBackVisible = false;

  // Swipe / Deste animasyon controller
  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _stackScaleAnimation;

  // Aura controller (Seçenek 2: Sağa fırlarken zümrüt yeşili, sola fırlarken mercan kırmızısı)
  late AnimationController _auraController;
  Color _activeAuraColor = Colors.transparent;

  bool _isAnimating = false;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _shuffledWords = List<SavedWord>.from(widget.words)..shuffle();

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
    _flipAnimation.addListener(() {
      if (_flipAnimation.value >= 0.5 && !_isBackVisible) {
        setState(() => _isBackVisible = true);
      } else if (_flipAnimation.value < 0.5 && _isBackVisible) {
        setState(() => _isBackVisible = false);
      }
    });

    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _swipeAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic));

    _rotationAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic),
    );

    _stackScaleAnimation = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic),
    );

    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    _swipeController.dispose();
    _auraController.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_isAnimating || _isFinished) return;
    if (_flipController.isCompleted) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
  }

  void _handleDecision({required bool know}) {
    if (_isAnimating || _isFinished || _currentIndex >= _shuffledWords.length) return;
    _isAnimating = true;

    final currentWord = _shuffledWords[_currentIndex];
    if (know) {
      _knownWords.add(currentWord);
      _activeAuraColor = const Color(0xFF10B981).withValues(alpha: 0.35); // Zümrüt Yeşili
    } else {
      _repeatWords.add(currentWord);
      _activeAuraColor = const Color(0xFFEF4444).withValues(alpha: 0.35); // Mercan Kırmızısı
    }

    // Seçenek 2: Renk Aurasını parlat
    _auraController.forward(from: 0.0);

    // Kartı sağa veya sola fırlat
    final screenWidth = MediaQuery.of(context).size.width;
    final endOffset = know
        ? Offset(screenWidth * 1.3, -20)
        : Offset(-screenWidth * 1.3, -20);
    final endAngle = know ? 0.32 : -0.32;

    _swipeAnimation = Tween<Offset>(begin: Offset.zero, end: endOffset).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic),
    );
    _rotationAnimation = Tween<double>(begin: 0, end: endAngle).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic),
    );

    _swipeController.forward(from: 0.0).then((_) {
      _flipController.reset();
      _isBackVisible = false;
      _swipeController.reset();
      _auraController.reverse();

      if (mounted) {
        setState(() {
          if (_currentIndex + 1 < _shuffledWords.length) {
            _currentIndex++;
            _isAnimating = false;
          } else {
            _isFinished = true;
            _isAnimating = false;
          }
        });
      }
    });
  }

  void _restartSession() {
    setState(() {
      _shuffledWords = List<SavedWord>.from(widget.words)..shuffle();
      _currentIndex = 0;
      _knownWords.clear();
      _repeatWords.clear();
      _isFinished = false;
      _isBackVisible = false;
    });
    _flipController.reset();
    _swipeController.reset();
    _auraController.reset();
  }

  void _practiceOnlyRepeats() {
    if (_repeatWords.isEmpty) return;
    setState(() {
      _shuffledWords = List<SavedWord>.from(_repeatWords)..shuffle();
      _currentIndex = 0;
      _knownWords.clear();
      _repeatWords.clear();
      _isFinished = false;
      _isBackVisible = false;
    });
    _flipController.reset();
    _swipeController.reset();
    _auraController.reset();
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
            'Kelime Kartları • ${widget.wordList.name}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: _restartSession,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Yeniden Başlat',
            ),
          ],
        ),
        body: SafeArea(
          child: _isFinished
              ? _buildSummaryView(context, theme, colorScheme)
              : _buildCardsView(context, theme, colorScheme, visuals),
        ),
      ),
    );
  }

  Widget _buildCardsView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppThemeVisuals visuals,
  ) {
    final total = _shuffledWords.length;
    final progress = (_currentIndex + 1) / total;
    final currentWord = _shuffledWords[_currentIndex];
    final nextWord = (_currentIndex + 1 < total) ? _shuffledWords[_currentIndex + 1] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          // Üst İlerleme ve İstatistik Çubuğu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_currentIndex + 1} / $total',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Öğrenildi: ${_knownWords.length}',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Tekrar: ${_repeatWords.length}',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
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
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.wordList.color,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // KART DESTESİ ALANI (Seçenek 2: Saf Renk Aurası & Deste Fiziği)
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 380),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // SEÇENEK 2: ARKA PLAN RENK AURASI (Zümrüt Yeşili / Mercan Kırmızısı)
                    AnimatedBuilder(
                      animation: _auraController,
                      builder: (context, _) {
                        final auraOpacity = _auraController.value;
                        if (auraOpacity <= 0.01) return const SizedBox.shrink();
                        return Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: _activeAuraColor.withValues(
                                  alpha: _activeAuraColor.a * auraOpacity,
                                ),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // 1. KATMAN: ALTTAN BEKLEYEN DESTE KARTI (TAM OPAK)
                    if (nextWord != null)
                      AnimatedBuilder(
                        animation: _stackScaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _stackScaleAnimation.value,
                            child: Transform.translate(
                              offset: Offset(0, (1 - _stackScaleAnimation.value) * 80),
                              child: child,
                            ),
                          );
                        },
                        child: _buildSolidCardFace(
                          context: context,
                          theme: theme,
                          colorScheme: colorScheme,
                          word: nextWord,
                          isBack: false,
                          isDeckPreview: true,
                        ),
                      ),

                    // 2. KATMAN: ÜSTTEKİ AKTİF KART (FLIP + SWIPE ANİMASYONLU)
                    AnimatedBuilder(
                      animation: _swipeController,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: _swipeAnimation.value,
                          child: Transform.rotate(
                            angle: _rotationAnimation.value,
                            child: child,
                          ),
                        );
                      },
                      child: GestureDetector(
                        onTap: _flipCard,
                        child: AnimatedBuilder(
                          animation: _flipAnimation,
                          builder: (context, child) {
                            final angle = _flipAnimation.value * math.pi;
                            final isUnder = angle > (math.pi / 2);
                            return Transform(
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0015)
                                ..rotateY(angle),
                              alignment: Alignment.center,
                              child: isUnder
                                  ? Transform(
                                      transform: Matrix4.identity()..rotateY(math.pi),
                                      alignment: Alignment.center,
                                      child: _buildSolidCardFace(
                                        context: context,
                                        theme: theme,
                                        colorScheme: colorScheme,
                                        word: currentWord,
                                        isBack: true,
                                      ),
                                    )
                                  : _buildSolidCardFace(
                                      context: context,
                                      theme: theme,
                                      colorScheme: colorScheme,
                                      word: currentWord,
                                      isBack: false,
                                    ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // AKSİYON BUTONLARI (HENÜZ ÖĞRENMEDİM / BİLİYORUM)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _isAnimating ? null : () => _handleDecision(know: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: BorderSide(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.06),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.close_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Henüz Öğrenmedim',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isAnimating ? null : () => _handleDecision(know: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 3,
                      shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Biliyorum',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Tam Opak Kart Yüzü (Ön veya Arka) — Arkayı Kesinlikle Göstermez.
  Widget _buildSolidCardFace({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required SavedWord word,
    required bool isBack,
    bool isDeckPreview = false,
  }) {
    // Proje renk temasıyla uyumlu, tamamen opak dolgu
    final surfaceColor = colorScheme.brightness == Brightness.dark
        ? const Color(0xFF171D28)
        : Colors.white;

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isBack
              ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: isBack
          ? _buildBackContent(context, theme, colorScheme, word)
          : _buildFrontContent(context, theme, colorScheme, word, isDeckPreview),
    );
  }

  Widget _buildFrontContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    SavedWord word,
    bool isDeckPreview,
  ) {
    final ipa = word.ipaUs ?? word.ipaUk;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Üst Bar: Etiket ve Ses Butonu
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                'İNGİLİZCE',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (!isDeckPreview)
              IconButton.filledTonal(
                onPressed: () {
                  widget.ttsService.toggleSpeak(
                    text: word.word,
                    target: TtsSpeakingTarget.word,
                  );
                },
                icon: const Icon(Icons.volume_up_rounded, size: 20),
                tooltip: 'Telaffuzu Dinle',
              ),
          ],
        ),

        // Orta Alan: Kelime ve IPA
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.word,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            if (ipa != null && ipa.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  ipa,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),

        // Alt İpucu
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 15,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              'Anlamını görmek için karta dokunun',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBackContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    SavedWord word,
  ) {
    final meanings = word.allMeanings;
    final posText = meanings.isNotEmpty && meanings.first.partOfSpeech != null
        ? meanings.first.partOfSpeech!.name
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Üst Bar: Türkçe Anlamı ve Tür Rozeti
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'TÜRKÇE ANLAMI',
                style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (posText != null && posText.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  posText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),

        // Orta Alan: Türkçe Anlam ve Eş/Zıt Anlamlılar
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.meaning,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFFF59E0B),
              ),
            ),
            if (word.synonyms.isNotEmpty || word.antonyms.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in word.synonyms.take(3))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '≈ $s',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  for (final a in word.antonyms.take(2))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '≠ $a',
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),

        // Alt İpucu
        Center(
          child: Text(
            'Tekrar çevirmek için dokunun',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  /// Tur Tamamlandığında Çıkan Özet Ekranı
  Widget _buildSummaryView(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final total = _shuffledWords.length;
    final successRate = total > 0 ? ((_knownWords.length / total) * 100).round() : 0;

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
                  Icons.emoji_events_rounded,
                  color: Color(0xFF10B981),
                  size: 40,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Kart Turu Tamamlandı!',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Başarı Oranı: %$successRate',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${_knownWords.length}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Öğrenildi',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${_repeatWords.length}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tekrar Edilecek',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (_repeatWords.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _practiceOnlyRepeats,
                    icon: const Icon(Icons.replay_rounded),
                    label: Text('Yalnızca Tekrarları Çalış (${_repeatWords.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _restartSession,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tüm Listeyi Yeniden Başlat'),
                  style: OutlinedButton.styleFrom(
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
