import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_backdrop.dart';
import '../../../../core/tts/tts_service.dart';
import '../../controllers/words_controller.dart';
import '../../models/saved_word.dart';
import '../../models/word_list.dart';
import '../services/word_learning_progress_service.dart';
import 'flashcards_screen.dart';
import 'word_match_screen.dart';
import 'word_quiz_screen.dart';

enum _WordStatusFilter {
  all,
  unlearned,
  learned,
}

/// Öğrenme Alanı (Çoklu Klasör Seçimi + Durum Filtresi + Kart Ayarları + Mod Seçimi).
class WordLearningHubScreen extends StatefulWidget {
  const WordLearningHubScreen({
    super.key,
    required this.controller,
    required this.ttsService,
    this.initialListId,
  });

  final WordsController controller;
  final TtsService ttsService;

  /// Belirli bir liste içinden açıldıysa o listeyi başlangıçta seçili yapar.
  /// Null ise genel "Kelimeler" ekranından açılmıştır; tüm dolu listeler seçilir.
  final int? initialListId;

  static const int minWordsForQuizAndMatch = 4;

  @override
  State<WordLearningHubScreen> createState() => _WordLearningHubScreenState();
}

class _WordLearningHubScreenState extends State<WordLearningHubScreen> {
  final Set<int> _selectedListIds = <int>{};
  _WordStatusFilter _statusFilter = _WordStatusFilter.all;
  Set<String> _learnedKeys = <String>{};
  FlashcardDisplayPrefs _displayPrefs = const FlashcardDisplayPrefs();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (widget.controller.lists.isEmpty) {
      await widget.controller.loadLists();
    }

    final lists = widget.controller.lists;
    for (final list in lists) {
      await widget.controller.loadWordsForList(list.id);
    }

    final learned = await WordLearningProgressService.instance.getLearnedWordKeys();
    final prefs = await WordLearningProgressService.instance.getDisplayPrefs();

    if (!mounted) return;
    setState(() {
      _learnedKeys = learned;
      _displayPrefs = prefs;

      if (widget.initialListId != null) {
        _selectedListIds.add(widget.initialListId!);
      } else {
        for (final list in lists) {
          if (widget.controller.wordsForList(list.id).isNotEmpty) {
            _selectedListIds.add(list.id);
          }
        }
        if (_selectedListIds.isEmpty && lists.isNotEmpty) {
          _selectedListIds.add(lists.first.id);
        }
      }
      _isLoading = false;
    });
  }

  Future<void> _refreshProgress() async {
    final learned = await WordLearningProgressService.instance.getLearnedWordKeys();
    final prefs = await WordLearningProgressService.instance.getDisplayPrefs();
    if (mounted) {
      setState(() {
        _learnedKeys = learned;
        _displayPrefs = prefs;
      });
    }
  }

  List<SavedWord> _collectSelectedFolderWords() {
    final result = <SavedWord>[];
    final seen = <String>{};
    for (final listId in _selectedListIds) {
      for (final w in widget.controller.wordsForList(listId)) {
        final key = '${w.word.toLowerCase()}_${w.meaning.toLowerCase()}';
        if (seen.add(key)) {
          result.add(w);
        }
      }
    }
    return result;
  }

  List<SavedWord> _applyStatusFilter(List<SavedWord> allWords) {
    final progress = WordLearningProgressService.instance;
    return switch (_statusFilter) {
      _WordStatusFilter.all => allWords,
      _WordStatusFilter.unlearned =>
        allWords.where((w) => !progress.isWordLearned(w, _learnedKeys)).toList(),
      _WordStatusFilter.learned =>
        allWords.where((w) => progress.isWordLearned(w, _learnedKeys)).toList(),
    };
  }

  String _resolveSessionTitle(List<WordList> allLists) {
    if (_selectedListIds.isEmpty) return 'Öğrenme Alanı';
    if (_selectedListIds.length == 1) {
      final id = _selectedListIds.first;
      for (final l in allLists) {
        if (l.id == id) return l.name;
      }
    }
    return '${_selectedListIds.length} Klasör';
  }

  Color _resolveAccentColor(List<WordList> allLists) {
    if (_selectedListIds.length == 1) {
      final id = _selectedListIds.first;
      for (final l in allLists) {
        if (l.id == id) return l.color;
      }
    }
    return const Color(0xFFF59E0B);
  }

  Future<void> _openCardSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void updatePref(FlashcardDisplayPrefs next) {
              setModalState(() {});
              setState(() => _displayPrefs = next);
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
                      'Kelime Kartı Görünüm Ayarları',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kartlarda hangi detayların gösterileceğini seçebilirsiniz.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('IPA Telaffuz Göster'),
                      value: _displayPrefs.showIpa,
                      onChanged: (v) =>
                          updatePref(_displayPrefs.copyWith(showIpa: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Eş Anlamlıları Göster (≈)'),
                      value: _displayPrefs.showSynonyms,
                      onChanged: (v) =>
                          updatePref(_displayPrefs.copyWith(showSynonyms: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Zıt Anlamlıları Göster (≠)'),
                      value: _displayPrefs.showAntonyms,
                      onChanged: (v) =>
                          updatePref(_displayPrefs.copyWith(showAntonyms: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Örnek Cümle / Ek Anlam Göster'),
                      value: _displayPrefs.showExamples,
                      onChanged: (v) =>
                          updatePref(_displayPrefs.copyWith(showExamples: v)),
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
          title: const Text(
            'Öğrenme Alanı',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: _openCardSettingsSheet,
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Kart Görünüm Ayarları',
            ),
          ],
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final allLists = widget.controller.lists;
                    final folderWords = _collectSelectedFolderWords();
                    final progress = WordLearningProgressService.instance;
                    final unlearnedCount = folderWords
                        .where((w) => !progress.isWordLearned(w, _learnedKeys))
                        .length;
                    final learnedCount = folderWords.length - unlearnedCount;
                    final filteredWords = _applyStatusFilter(folderWords);

                    final canPlayCards = filteredWords.isNotEmpty;
                    final canPlayQuizAndMatch = filteredWords.length >=
                        WordLearningHubScreen.minWordsForQuizAndMatch;

                    final sessionTitle = _resolveSessionTitle(allLists);
                    final accentColor = _resolveAccentColor(allLists);

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. BÖLÜM: ÇOKLU KLASÖR SEÇİMİ
                              Text(
                                '1. ÇALIŞILACAK KLASÖRLERİ SEÇİN',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: allLists.map((list) {
                                  final count = widget.controller
                                      .wordsForList(list.id)
                                      .length;
                                  final isSelected =
                                      _selectedListIds.contains(list.id);
                                  return FilterChip(
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedListIds.add(list.id);
                                        } else {
                                          _selectedListIds.remove(list.id);
                                        }
                                      });
                                    },
                                    avatar: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: list.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    label: Text(
                                      '${list.name} ($count)',
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    selectedColor:
                                        list.color.withValues(alpha: 0.18),
                                    checkmarkColor: list.color,
                                    side: BorderSide(
                                      color: isSelected
                                          ? list.color
                                          : colorScheme.outlineVariant,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  );
                                }).toList(),
                              ),

                              const SizedBox(height: 22),

                              // 2. BÖLÜM: HANGİ KELİMELERLE ÇALIŞILSIN?
                              Text(
                                '2. HANGİ KELİMELERLE ÇALIŞILSIN?',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _buildFilterChip(
                                    context: context,
                                    colorScheme: colorScheme,
                                    label: 'Tümü (${folderWords.length})',
                                    isSelected:
                                        _statusFilter == _WordStatusFilter.all,
                                    onTap: () => setState(
                                      () => _statusFilter =
                                          _WordStatusFilter.all,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildFilterChip(
                                    context: context,
                                    colorScheme: colorScheme,
                                    label: 'Öğrenmediklerim ($unlearnedCount)',
                                    isSelected: _statusFilter ==
                                        _WordStatusFilter.unlearned,
                                    onTap: () => setState(
                                      () => _statusFilter =
                                          _WordStatusFilter.unlearned,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildFilterChip(
                                    context: context,
                                    colorScheme: colorScheme,
                                    label: 'Öğrendiklerim ($learnedCount)',
                                    isSelected: _statusFilter ==
                                        _WordStatusFilter.learned,
                                    onTap: () => setState(
                                      () => _statusFilter =
                                          _WordStatusFilter.learned,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // 3. BÖLÜM: ÇALIŞMA MODLARI
                              Text(
                                '3. ÇALIŞMA MODUNU SEÇİN',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),

                              if (filteredWords.isEmpty)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer
                                        .withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    'Seçtiğiniz klasör ve filtreye uygun kelime bulunamadı.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                )
                              else if (!canPlayQuizAndMatch)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFF59E0B)
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    'Kelime Testi ve Anlam Eşleştirme için en az 4 kelime gereklidir (Şu an ${filteredWords.length} kelime seçili). Kelime Kartları ile hemen çalışabilirsiniz!',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                              // Mod 1: Kelime Kartları
                              _buildModeCard(
                                context: context,
                                theme: theme,
                                colorScheme: colorScheme,
                                emoji: '🃏',
                                title: 'Kelime Kartları',
                                countLabel: '${filteredWords.length} kelime',
                                accentColor: const Color(0xFF6366F1),
                                enabled: canPlayCards,
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => FlashcardsScreen(
                                        title: sessionTitle,
                                        accentColor: accentColor,
                                        words: filteredWords,
                                        ttsService: widget.ttsService,
                                        initialPrefs: _displayPrefs,
                                      ),
                                    ),
                                  );
                                  _refreshProgress();
                                },
                              ),
                              const SizedBox(height: 12),

                              // Mod 2: Kelime Testi
                              _buildModeCard(
                                context: context,
                                theme: theme,
                                colorScheme: colorScheme,
                                emoji: '🎯',
                                title: 'Kelime Testi',
                                countLabel: '${filteredWords.length} kelime',
                                accentColor: const Color(0xFF10B981),
                                enabled: canPlayQuizAndMatch,
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => WordQuizScreen(
                                        title: sessionTitle,
                                        accentColor: accentColor,
                                        words: filteredWords,
                                        allPoolWords: folderWords,
                                        ttsService: widget.ttsService,
                                      ),
                                    ),
                                  );
                                  _refreshProgress();
                                },
                              ),
                              const SizedBox(height: 12),

                              // Mod 3: Anlam Eşleştirme
                              _buildModeCard(
                                context: context,
                                theme: theme,
                                colorScheme: colorScheme,
                                emoji: '🧩',
                                title: 'Anlam Eşleştirme',
                                countLabel: '${filteredWords.length} kelime',
                                accentColor: const Color(0xFFF59E0B),
                                enabled: canPlayQuizAndMatch,
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => WordMatchScreen(
                                        title: sessionTitle,
                                        accentColor: accentColor,
                                        words: filteredWords,
                                        ttsService: widget.ttsService,
                                      ),
                                    ),
                                  );
                                  _refreshProgress();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required ColorScheme colorScheme,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : (colorScheme.brightness == Brightness.dark
                    ? const Color(0xFF171D28)
                    : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFF59E0B)
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
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
    required String countLabel,
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      countLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
