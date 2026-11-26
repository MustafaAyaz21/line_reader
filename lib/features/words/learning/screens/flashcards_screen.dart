import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_backdrop.dart';
import '../../../../core/tts/tts_service.dart';
import '../../models/saved_word.dart';
import '../services/word_learning_progress_service.dart';

/// Kelime Kartları (Flashcards) Ekranı — Seçenek 2: Saf Renk Aurası.
/// Arkadaki sıradaki kart kesinlikle gizlidir; yalnızca aktif kart görünür.
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({
    super.key,
    required this.title,
    required this.accentColor,
    required this.words,
    required this.ttsService,
    this.initialPrefs = const FlashcardDisplayPrefs(),
  });

  final String title;
  final Color accentColor;
  final List<SavedWord> words;
  final TtsService ttsService;
  final FlashcardDisplayPrefs initialPrefs;

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen>
    with TickerProviderStateMixin {
  late List<SavedWord> _shuffledWords;
  int _currentIndex = 0;
  final List<SavedWord> _knownWords = <SavedWord>[];
  final List<SavedWord> _repeatWords = <SavedWord>[];

  late FlashcardDisplayPrefs _prefs;

  // 3D Flip controller
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _isBackVisible = false;

  // Swipe animasyon controller
  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;
  late Animation<double> _rotationAnimation;

  // Aura controller (Seçenek 2: Sağa fırlarken zümrüt yeşili, sola fırlarken mercan kırmızısı)
  late AnimationController _auraController;
  Color _activeAuraColor = Colors.transparent;

  bool _isAnimating = false;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
    _loadPrefs();
    _shuffledWords = List<SavedWord>.from(widget.words)..shuffle();

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
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
      duration: const Duration(milliseconds: 360),
    );
    _swipeAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic),
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic),
    );

    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
  }

  Future<void> _loadPrefs() async {
    final loaded = await WordLearningProgressService.instance.getDisplayPrefs();
    if (mounted) {
      setState(() => _prefs = loaded);
    }
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
    if (_isAnimating || _isFinished || _currentIndex >= _shuffledWords.length) {
      return;
    }
    _isAnimating = true;

    final currentWord = _shuffledWords[_currentIndex];
    if (know) {
      _knownWords.add(currentWord);
      _activeAuraColor = const Color(0xFF10B981).withValues(alpha: 0.35);
      WordLearningProgressService.instance.markWordLearned(currentWord);
    } else {
      _repeatWords.add(currentWord);
      _activeAuraColor = const Color(0xFFEF4444).withValues(alpha: 0.35);
      WordLearningProgressService.instance.markWordUnlearned(currentWord);
    }

    _auraController.forward(from: 0.0);

    final screenWidth = MediaQuery.of(context).size.width;
    final endOffset = know
        ? Offset(screenWidth * 1.25, -20)
        : Offset(-screenWidth * 1.25, -20);
    final endAngle = know ? 0.30 : -0.30;

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

  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void updatePref(FlashcardDisplayPrefs next) {
              setModalState(() {});
              setState(() => _prefs = next);
              WordLearningProgressService.instance.saveDisplayPrefs(next);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Kart Görünüm Ayarları',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kelime kartlarında hangi bilgilerin gösterileceğini seçin.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('IPA Telaffuz Göster'),
                      subtitle: const Text('Örn: /ɪˈfem.ər.əl/'),
                      value: _prefs.showIpa,
                      onChanged: (v) => updatePref(_prefs.copyWith(showIpa: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Eş Anlamlıları Göster (≈)'),
                      subtitle: const Text('Varsa kartın arka yüzünde görünür'),
                      value: _prefs.showSynonyms,
                      onChanged: (v) =>
                          updatePref(_prefs.copyWith(showSynonyms: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Zıt Anlamlıları Göster (≠)'),
                      subtitle: const Text('Varsa kartın arka yüzünde görünür'),
                      value: _prefs.showAntonyms,
                      onChanged: (v) =>
                          updatePref(_prefs.copyWith(showAntonyms: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Örnek Cümle / Detay Göster'),
                      subtitle: const Text('Varsa ek anlam bağlamını gösterir'),
                      value: _prefs.showExamples,
                      onChanged: (v) =>
                          updatePref(_prefs.copyWith(showExamples: v)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
            'Kelime Kartları • ${widget.title}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: _openSettingsSheet,
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Kart Görünüm Ayarları',
            ),
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
              : _buildCardsView(context, theme, colorScheme),
        ),
      ),
    );
  }

  Widget _buildCardsView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final total = _shuffledWords.length;
    final progress = (_currentIndex + 1) / total;
    final currentWord = _shuffledWords[_currentIndex];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                  valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
                ),
              ),
              const SizedBox(height: 24),

              // TEK KART ALANI — Arkadaki gelecek kart tamamen gizlenmiştir.
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 440,
                      maxHeight: 380,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // SEÇENEK 2: ARKA PLAN RENK AURASI
                        AnimatedBuilder(
                          animation: _auraController,
                          builder: (context, _) {
                            final auraOpacity = _auraController.value;
                            if (auraOpacity <= 0.01) {
                              return const SizedBox.shrink();
                            }
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
                                    blurRadius: 44,
                                    spreadRadius: 12,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // YALNIZCA AKTİF KART (Arkadaki kart gösterilmez)
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
                                          transform: Matrix4.identity()
                                            ..rotateY(math.pi),
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

              // AKSİYON BUTONLARI
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: OutlinedButton(
                        onPressed: _isAnimating
                            ? null
                            : () => _handleDecision(know: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: BorderSide(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          backgroundColor:
                              const Color(0xFFEF4444).withValues(alpha: 0.06),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close_rounded, size: 18),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Henüz Öğrenmedim',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isAnimating
                            ? null
                            : () => _handleDecision(know: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shadowColor:
                              const Color(0xFF10B981).withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Biliyorum',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
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
        ),
      ),
    );
  }

  Widget _buildSolidCardFace({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required SavedWord word,
    required bool isBack,
  }) {
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
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: isBack
          ? _buildBackContent(context, theme, colorScheme, word)
          : _buildFrontContent(context, theme, colorScheme, word),
    );
  }

  Widget _buildFrontContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    SavedWord word,
  ) {
    final ipa = word.ipaUs ?? word.ipaUk;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
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
            if (_prefs.showIpa && ipa != null && ipa.isNotEmpty) ...[
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
        ? meanings.first.partOfSpeech!.label
        : null;

    final showSyn = _prefs.showSynonyms && word.synonyms.isNotEmpty;
    final showAnt = _prefs.showAntonyms && word.antonyms.isNotEmpty;
    final extraMeanings = _prefs.showExamples && meanings.length > 1
        ? meanings.skip(1).map((m) => m.baseFormatted).join(' • ')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
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
        Flexible(
          child: SingleChildScrollView(
            child: Column(
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
                if (extraMeanings != null && extraMeanings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    extraMeanings,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (showSyn || showAnt) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (showSyn)
                        for (final s in word.synonyms.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.25),
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
                      if (showAnt)
                        for (final a in word.antonyms.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFEF4444)
                                    .withValues(alpha: 0.25),
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
          ),
        ),
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

  Widget _buildSummaryView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final total = _shuffledWords.length;
    final successRate = total > 0 ? ((_knownWords.length / total) * 100).round() : 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.brightness == Brightness.dark
                  ? const Color(0xFF171D28)
                  : Colors.white,
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
                    Icons.emoji_events_rounded,
                    color: Color(0xFF10B981),
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_knownWords.length}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Öğrenildi',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_repeatWords.length}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Tekrar Edilecek',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_repeatWords.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _practiceOnlyRepeats,
                      icon: const Icon(Icons.replay_rounded),
                      label: Text(
                        'Öğrenmediklerimi Tekrar Et (${_repeatWords.length})',
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
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _restartSession,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('Tümünü Tekrar Et (${widget.words.length})'),
                    style: OutlinedButton.styleFrom(
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
