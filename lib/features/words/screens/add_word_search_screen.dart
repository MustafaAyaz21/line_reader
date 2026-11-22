import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/settings/api_key_controller.dart';
import '../../../core/tts/tts_service.dart';
import '../../translation/models/word_meaning.dart';
import '../../translation/services/word_translation_service.dart';
import '../controllers/words_controller.dart';
import '../models/saved_word.dart';
import '../models/word_list.dart';
import '../models/word_search_detail.dart';
import '../services/word_dictionary_search_service.dart';

enum _ExistingWordSaveAction {
  overwrite,
  addAsNew,
}

/// Kelime listesi içindeki `+` veya karttaki düzenleme (`Icons.edit_outlined`)
/// butonundan açılan manuel kelime arama, 10–15 anlam arasından çoklu seçim
/// (tik ✓), 3 kısa örnek cümle ve "Üstüne ekle / Yeni kelime olarak ekle" ekranı.
class AddWordSearchScreen extends StatefulWidget {
  const AddWordSearchScreen({
    super.key,
    required this.listId,
    required this.controller,
    this.wordList,
    this.initialWord,
    this.editingWord,
    this.apiKeyController,
    this.ttsService,
  });

  final int listId;
  final WordsController controller;
  final WordList? wordList;
  final String? initialWord;
  final SavedWord? editingWord;
  final ApiKeyController? apiKeyController;
  final TtsService? ttsService;

  @override
  State<AddWordSearchScreen> createState() => _AddWordSearchScreenState();
}

class _AddWordSearchScreenState extends State<AddWordSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final WordDictionarySearchService _searchService;
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  WordSearchDetail? _detail;
  SavedWord? _matchedExistingWord;
  final Set<int> _selectedIndices = <int>{};

  bool get _hasInitialWord =>
      widget.initialWord != null && widget.initialWord!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Kelime listesine ekleme akışında gereksiz AI çağrısı yapılmaz;
    // doğrudan ücretsiz çoklu sözlük + hafif yerel sözlük/kök çözümleyici kullanılır.
    _searchService = WordDictionarySearchService(
      geminiApiKeyProvider: null,
      shouldAttemptGeminiProvider: () => false,
    );

    if (_hasInitialWord) {
      final initial = widget.initialWord!.trim();
      _searchController.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _performSearch(initial, dismissKeyboard: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchService.dispose();
    super.dispose();
  }

  String _normalizeKey(String raw) {
    return raw.trim().replaceAll('İ', 'i').toLowerCase();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounceTimer?.cancel();

    final trimmed = value.trim();
    if (trimmed.length < 2) return;

    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_searchController.text.trim() == trimmed &&
          _detail?.word != _normalizeKey(trimmed)) {
        _performSearch(trimmed, dismissKeyboard: false);
      }
    });
  }

  Future<void> _performSearch(
    String rawQuery, {
    bool dismissKeyboard = true,
  }) async {
    _debounceTimer?.cancel();
    final query = rawQuery.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Lütfen aramak istediğiniz İngilizce kelimeyi yazın.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    if (dismissKeyboard) {
      _searchFocusNode.unfocus();
    }

    final myGen = ++_searchGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _detail = null;
      _matchedExistingWord = null;
      _selectedIndices.clear();
    });

    try {
      // Sözlük araması ile bu kelimenin listede zaten kayıtlı olup olmadığını paralel kontrol et.
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _searchService.searchWord(query),
        widget.controller.findExistingWordsInList(
          listId: widget.listId,
          word: query,
        ),
      ]);
      if (!mounted || myGen != _searchGeneration) return;

      final detail = results[0] as WordSearchDetail;
      final existingList = results[1] as List<SavedWord>;

      // Düzenleme ikonundan gelindiyse ve aranan kelime aynıysa o spesifik kaydı seç;
      // aksi halde aynı listedeki en güncel mevcut kaydı eşleştir.
      SavedWord? matched;
      final editing = widget.editingWord;
      if (editing != null &&
          _normalizeKey(editing.word) == _normalizeKey(detail.word)) {
        matched = editing;
        for (final item in existingList) {
          if (item.id == editing.id) {
            matched = item;
            break;
          }
        }
      } else if (existingList.isNotEmpty) {
        matched = existingList.first;
      }

      final mergedMeanings = List<MeaningEntry>.from(detail.meanings);
      final preselected = <int>{};

      if (matched != null) {
        final savedMeanings = matched.allMeanings;
        final savedKeys = <String>{};
        for (final savedEntry in savedMeanings) {
          final key = _normalizeKey(savedEntry.translation);
          if (key.isEmpty ||
              savedEntry.translation == SavedWord.defaultPlaceholderMeaning) {
            continue;
          }
          savedKeys.add(key);
        }

        // Daha önce kayıtlı olup sözlük sonuçlarında olmayan anlam varsa en başa ekle.
        final missingFromFetched = <MeaningEntry>[];
        final fetchedKeys =
            mergedMeanings.map((e) => _normalizeKey(e.translation)).toSet();
        for (final savedEntry in savedMeanings) {
          final key = _normalizeKey(savedEntry.translation);
          if (key.isEmpty ||
              savedEntry.translation == SavedWord.defaultPlaceholderMeaning) {
            continue;
          }
          if (!fetchedKeys.contains(key)) {
            missingFromFetched.add(savedEntry);
            fetchedKeys.add(key);
          }
        }
        if (missingFromFetched.isNotEmpty) {
          mergedMeanings.insertAll(0, missingFromFetched);
        }

        // Mevcut kayıtlı tüm anlamları otomatik olarak tikli (checked = true) getir.
        for (var i = 0; i < mergedMeanings.length; i++) {
          if (savedKeys.contains(_normalizeKey(mergedMeanings[i].translation))) {
            preselected.add(i);
          }
        }
      }

      setState(() {
        _detail = WordSearchDetail(
          word: detail.word,
          meanings: List<MeaningEntry>.unmodifiable(mergedMeanings),
          examples: detail.examples,
        );
        _matchedExistingWord = matched;
        _selectedIndices
          ..clear()
          ..addAll(preselected);
        _isLoading = false;
      });
    } on TranslationException catch (error) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _errorMessage =
            'Kelime aranırken bir sorun oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.';
        _isLoading = false;
      });
    }
  }

  void _toggleMeaningSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _clearAllSelections() {
    if (_selectedIndices.isEmpty) return;
    setState(() => _selectedIndices.clear());
  }

  Future<void> _showAddCustomMeaningDialog() async {
    final currentDetail = _detail;
    if (currentDetail == null) return;

    final defaultPos = currentDetail.meanings.isNotEmpty
        ? (currentDetail.meanings.first.partOfSpeech ?? WordPartOfSpeech.verb)
        : WordPartOfSpeech.noun;

    final addedEntry = await showDialog<MeaningEntry>(
      context: context,
      builder: (dialogContext) => _CustomMeaningDialog(
        word: currentDetail.word,
        initialPartOfSpeech: defaultPos,
      ),
    );

    if (addedEntry == null || !mounted) return;

    final addedKey = _normalizeKey(addedEntry.translation);
    final existingIndex = currentDetail.meanings.indexWhere(
      (entry) =>
          _normalizeKey(entry.translation) == addedKey &&
          entry.partOfSpeech == addedEntry.partOfSpeech,
    );

    if (existingIndex >= 0) {
      setState(() {
        _selectedIndices.add(existingIndex);
      });
      _showSnack('"${addedEntry.baseFormatted}" seçili anlamlara eklendi.');
      return;
    }

    final updatedMeanings = <MeaningEntry>[
      addedEntry.copyWith(isContextual: false),
      ...currentDetail.meanings,
    ];
    final shiftedSelections = <int>{
      0,
      for (final idx in _selectedIndices) idx + 1,
    };

    setState(() {
      _detail = WordSearchDetail(
        word: currentDetail.word,
        meanings: List<MeaningEntry>.unmodifiable(updatedMeanings),
        examples: currentDetail.examples,
      );
      _selectedIndices
        ..clear()
        ..addAll(shiftedSelections);
    });
    _showSnack('"${addedEntry.baseFormatted}" eklendi ve tiklendi.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<_ExistingWordSaveAction?> _askExistingWordAction(
    String word,
    int selectedCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showModalBottomSheet<_ExistingWordSaveAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '"$word" listede zaten kayıtlı',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Seçtiğiniz anlamları mevcut kaydın üzerine güncelleyebilir veya ayrı bir yeni kart olarak ekleyebilirsiniz.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // Seçenek 1: Üstüne ekle
              Material(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_ExistingWordSaveAction.overwrite),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.playlist_add_check_rounded,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Üstüne ekle',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selectedCount == 0
                                    ? 'Hiç anlam seçili olmadığı için mevcut kayıt listeden kaldırılır.'
                                    : 'Mevcut kaydın anlamlarını seçili $selectedCount anlamla senkronize eder.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer
                                      .withAlpha(210),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Seçenek 2: Yeni kelime olarak ekle
              Material(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_ExistingWordSaveAction.addAsNew),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Yeni kelime olarak ekle',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Aynı kelimeden seçili anlamlarla bağımsız yeni bir kart oluşturur.',
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSaveSelected() async {
    if (_isSaving) return;

    final detail = _detail;
    if (detail == null) {
      _showSnack('Önce bir kelime arayıp anlam seçin.');
      return;
    }

    final existing = _matchedExistingWord;
    final sortedIndices = _selectedIndices.toList()..sort();
    final selectedMeanings = <MeaningEntry>[
      for (final idx in sortedIndices)
        detail.meanings[idx].copyWith(isContextual: false),
    ];

    // Kelime listede henüz yoksa doğrudan yeni kayıt olarak ekle.
    if (existing == null) {
      if (selectedMeanings.isEmpty) {
        _showSnack('Lütfen kaydetmek için en az bir anlam seçin.');
        return;
      }

      setState(() => _isSaving = true);
      try {
        final status = await widget.controller.addWord(
          word: detail.word,
          meaning: selectedMeanings.first.baseFormatted,
          meanings: selectedMeanings,
          listId: widget.listId,
          allowDuplicate: true,
        );
        if (!mounted) return;
        if (status == SaveWordStatus.saved) {
          Navigator.of(context).pop('"${detail.word}" listeye eklendi.');
          return;
        }
        setState(() => _isSaving = false);
        _showSnack('Kelime kaydedilirken bir sorun oluştu.');
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        _showSnack('Kelime kaydedilirken beklenmeyen bir sorun oluştu.');
      }
      return;
    }

    // Kelime zaten kayıtlıysa kullanıcıya iki net seçenek sun:
    // "Üstüne ekle" veya "Yeni kelime olarak ekle".
    final chosenAction = await _askExistingWordAction(
      detail.word,
      selectedMeanings.length,
    );
    if (chosenAction == null || !mounted) return;

    if (chosenAction == _ExistingWordSaveAction.addAsNew) {
      if (selectedMeanings.isEmpty) {
        _showSnack('Yeni kelime olarak eklemek için en az bir anlam seçin.');
        return;
      }
      setState(() => _isSaving = true);
      try {
        final status = await widget.controller.addWord(
          word: detail.word,
          meaning: selectedMeanings.first.baseFormatted,
          meanings: selectedMeanings,
          listId: widget.listId,
          allowDuplicate: true,
        );
        if (!mounted) return;
        if (status == SaveWordStatus.saved) {
          Navigator.of(context)
              .pop('"${detail.word}" yeni kayıt olarak eklendi.');
          return;
        }
        setState(() => _isSaving = false);
        _showSnack('Yeni kayıt eklenirken bir sorun oluştu.');
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        _showSnack('Yeni kayıt eklenirken beklenmeyen bir sorun oluştu.');
      }
      return;
    }

    // "Üstüne ekle": mevcut kaydı seçili anlamlarla güncelle/senkronize et.
    setState(() => _isSaving = true);
    try {
      final status = await widget.controller.updateWordMeanings(
        existingWord: existing,
        meanings: selectedMeanings,
      );
      if (!mounted) return;
      if (status == SaveWordStatus.saved) {
        final msg = selectedMeanings.isEmpty
            ? '"${detail.word}" tüm anlamları kaldırıldığı için listeden çıkarıldı.'
            : '"${detail.word}" anlamları güncellendi.';
        Navigator.of(context).pop(msg);
        return;
      }
      setState(() => _isSaving = false);
      _showSnack('Kelime güncellenirken bir sorun oluştu.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack('Kelime güncellenirken beklenmeyen bir sorun oluştu.');
    }
  }

  Future<void> _handleSpeak(String text, TtsSpeakingTarget target) async {
    final tts = widget.ttsService;
    if (tts == null || text.trim().isEmpty) return;
    await tts.toggleSpeak(text: text, target: target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final list = widget.wordList ?? widget.controller.findListById(widget.listId);
    final selectedCount = _selectedIndices.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (list != null) ...[
              Container(
                width: 8,
                height: 20,
                decoration: BoxDecoration(
                  color: list.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                list != null ? 'Kelime Ekle • ${list.name}' : 'Kelime Ekle',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSaving ? null : _handleSaveSelected,
        tooltip: 'Seçilen Anlamlarla Kaydet',
        child: _isSaving
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colorScheme.onPrimaryContainer,
                ),
              )
            : Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.add_rounded, size: 28),
                  if (selectedCount > 0)
                    Positioned(
                      right: -12,
                      top: -12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '$selectedCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst Arama Çubuğu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: !_hasInitialWord,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    autocorrect: true,
                    enableSuggestions: true,
                    onChanged: _onSearchChanged,
                    onSubmitted: (value) => _performSearch(value),
                    decoration: InputDecoration(
                      hintText: 'İngilizce kelime yazın (örn. make, run)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _debounceTimer?.cancel();
                                _searchController.clear();
                                setState(() {
                                  _detail = null;
                                  _matchedExistingWord = null;
                                  _errorMessage = null;
                                  _selectedIndices.clear();
                                });
                                _searchFocusNode.requestFocus();
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: 'Temizle',
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isLoading
                      ? null
                      : () => _performSearch(_searchController.text),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Ara'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          // İçerik Alanı: Yükleniyor / Hata / Boş / İkiye Bölünmüş Düzen
          Expanded(
            child: _buildBody(theme, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              'Anlamlar ve örnek cümleler getiriliyor...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 40,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => _performSearch(_searchController.text),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.translate_rounded,
                size: 44,
                color: colorScheme.primary.withAlpha(170),
              ),
              const SizedBox(height: 14),
              Text(
                'İngilizce kelime arayın',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Üstteki arama çubuğuna bir kelime yazın; 10–15 farklı anlam arasından istediklerinizi tikleyip sağ alttaki + butonuyla listenize kaydedin.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isExisting = _matchedExistingWord != null;

    // İkiye Bölünmüş Düzen:
    // - Üst Bölüm (flex: 6): 10–15 Anlam Seçimi (mevcutlar otomatik tikli)
    // - Alt Bölüm (flex: 4): 3 Kısa Örnek Cümle
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ÜST BÖLÜM: Anlam Seçimi
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
                color: colorScheme.surfaceContainerLowest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          detail.word,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                        if (widget.ttsService != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => _handleSpeak(
                              detail.word,
                              TtsSpeakingTarget.word,
                            ),
                            icon: Icon(
                              Icons.volume_up_rounded,
                              size: 19,
                              color: colorScheme.primary,
                            ),
                            tooltip: 'Kelimeyi Dinle',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (_selectedIndices.isNotEmpty)
                          TextButton(
                            onPressed: _clearAllSelections,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Temizle'),
                          ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedIndices.isNotEmpty
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_selectedIndices.length}/${detail.meanings.length} seçili',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _selectedIndices.isNotEmpty
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isExisting) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer.withAlpha(140),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 15,
                              color: colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Listede kayıtlı • mevcut anlamlar tikli getirildi (+ ile Üstüne ekle / Yeni ekle)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _showAddCustomMeaningDialog,
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Kendi Anlamını Ekle'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: detail.meanings.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 52,
                    color: colorScheme.outlineVariant.withAlpha(140),
                  ),
                  itemBuilder: (context, index) {
                    final entry = detail.meanings[index];
                    final isChecked = _selectedIndices.contains(index);

                    return Material(
                      color: isChecked
                          ? colorScheme.primaryContainer.withAlpha(110)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => _toggleMeaningSelection(index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: isChecked
                                        ? colorScheme.primary
                                        : colorScheme.outline,
                                    width: 1.8,
                                  ),
                                ),
                                child: isChecked
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: colorScheme.onPrimary,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: entry.translation,
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: isChecked
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      if (entry.partOfSpeech != null)
                                        TextSpan(
                                          text:
                                              '  (${entry.partOfSpeech!.label})',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: isChecked
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
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
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // İki bölüm arasındaki belirgin ayırıcı
        Divider(
          height: 2,
          thickness: 2,
          color: colorScheme.outlineVariant,
        ),
        // ALT BÖLÜM: 3 Kısa Örnek Cümle
        Expanded(
          flex: 4,
          child: Container(
            color: colorScheme.surfaceContainerLowest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.format_quote_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Örnek Cümleler',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 84),
                    itemCount: detail.examples.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final example = detail.examples[index];
                      return Container(
                        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withAlpha(160),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${index + 1}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSecondaryContainer,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _HighlightedSentenceText(
                                    sentence: example.english,
                                    highlightWord: detail.word,
                                    baseStyle:
                                        theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface,
                                      height: 1.35,
                                    ),
                                    highlightColor: colorScheme.primary,
                                  ),
                                  if (example.turkish != null &&
                                      example.turkish!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      example.turkish!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (widget.ttsService != null)
                              IconButton(
                                onPressed: () => _handleSpeak(
                                  example.english,
                                  TtsSpeakingTarget.sentence,
                                ),
                                icon: Icon(
                                  Icons.volume_up_outlined,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                tooltip: 'Cümleyi Dinle',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 30,
                                  minHeight: 30,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Örnek cümle içinde aranan İngilizce kelimeyi kalın ve vurgulu gösterir.
class _HighlightedSentenceText extends StatelessWidget {
  const _HighlightedSentenceText({
    required this.sentence,
    required this.highlightWord,
    required this.baseStyle,
    required this.highlightColor,
  });

  final String sentence;
  final String highlightWord;
  final TextStyle? baseStyle;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    final escaped = RegExp.escape(highlightWord.trim());
    if (escaped.isEmpty) {
      return Text(sentence, style: baseStyle);
    }

    final regex = RegExp(escaped, caseSensitive: false);
    final matches = regex.allMatches(sentence).toList();
    if (matches.isEmpty) {
      return Text(sentence, style: baseStyle);
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: sentence.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: sentence.substring(match.start, match.end),
          style: baseStyle?.copyWith(
            fontWeight: FontWeight.w700,
            color: highlightColor,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(cursor)));
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}

/// Kullanıcının aranan kelime için kendi özel anlamını ve türünü
/// (noun, verb, adjective, adverb, phrase vb.) seçerek ekleyebildiği pencere.
class _CustomMeaningDialog extends StatefulWidget {
  const _CustomMeaningDialog({
    required this.word,
    required this.initialPartOfSpeech,
  });

  final String word;
  final WordPartOfSpeech? initialPartOfSpeech;

  @override
  State<_CustomMeaningDialog> createState() => _CustomMeaningDialogState();
}

class _CustomMeaningDialogState extends State<_CustomMeaningDialog> {
  final TextEditingController _meaningController = TextEditingController();
  WordPartOfSpeech? _selectedPos;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedPos = widget.initialPartOfSpeech;
  }

  @override
  void dispose() {
    _meaningController.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _meaningController.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorText = 'Lütfen bir anlam yazın.');
      return;
    }

    Navigator.of(context).pop(
      MeaningEntry(
        translation: trimmed,
        partOfSpeech: _selectedPos,
        isContextual: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentText = _meaningController.text.trim();
    final preview = currentText.isNotEmpty
        ? MeaningEntry(
            translation: currentText,
            partOfSpeech: _selectedPos,
          ).baseFormatted
        : null;

    return AlertDialog(
      title: Text(
        '"${widget.word}" için anlam ekle',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _meaningController,
              autofocus: true,
              autocorrect: true,
              enableSuggestions: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                setState(() {
                  if (_errorText != null) _errorText = null;
                });
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Anlam',
                hintText: 'Örn: koşmak, çalıştırmak, yürütmek',
                errorText: _errorText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Kelime Türü',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: WordPartOfSpeech.values.map((pos) {
                final isSelected = _selectedPos == pos;
                return ChoiceChip(
                  label: Text(pos.label),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedPos = selected ? pos : null;
                    });
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            if (preview != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(150),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        preview,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
