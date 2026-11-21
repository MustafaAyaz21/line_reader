import 'package:flutter/material.dart';

import '../../core/settings/api_key_controller.dart';
import '../../core/tts/tts_service.dart';
import 'controllers/words_controller.dart';
import 'models/saved_word.dart';
import 'models/word_list.dart';
import 'screens/add_word_search_screen.dart';
import 'widgets/empty_words_view.dart';
import 'widgets/word_list_editor_dialog.dart';
import 'widgets/word_list_tile.dart';

/// Seçilen bir kelime listesinin içindeki kayıtlı kelimeleri gösteren ekran.
class ListWordsScreen extends StatefulWidget {
  const ListWordsScreen({
    super.key,
    required this.listId,
    required this.controller,
    this.apiKeyController,
    this.ttsService,
  });

  final int listId;
  final WordsController controller;
  final ApiKeyController? apiKeyController;
  final TtsService? ttsService;

  @override
  State<ListWordsScreen> createState() => _ListWordsScreenState();
}

class _ListWordsScreenState extends State<ListWordsScreen> {
  bool _isInitialLoading = true;
  TtsService? _ttsService;
  bool _ownsTtsService = false;

  TtsService _resolveTtsService() {
    final existing = _ttsService;
    if (existing != null) return existing;

    final provided = widget.ttsService;
    if (provided != null) {
      _ttsService = provided;
      _ownsTtsService = false;
      return provided;
    }

    final created = TtsService();
    _ttsService = created;
    _ownsTtsService = true;
    return created;
  }

  @override
  void initState() {
    super.initState();
    _resolveTtsService().clearError(notify: false);
    _load();
  }

  @override
  void dispose() {
    final tts = _ttsService;
    if (tts != null) {
      tts.stop(notify: false);
      tts.clearError(notify: false);
      if (_ownsTtsService) {
        tts.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    await widget.controller.loadWordsForList(widget.listId);
    if (mounted) {
      setState(() => _isInitialLoading = false);
    }
  }

  Future<void> _handleEditList(WordList list) async {
    await WordListEditorDialog.show(
      context,
      existingList: list,
      onSubmit: (name, colorValue) {
        return widget.controller.updateList(
          list: list,
          name: name,
          colorValue: colorValue,
        );
      },
    );
  }

  Future<void> _handleOpenAddWord(
    WordList? list, {
    SavedWord? editingWord,
  }) async {
    final resultMessage = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AddWordSearchScreen(
          listId: widget.listId,
          controller: widget.controller,
          wordList: list,
          initialWord: editingWord?.word,
          editingWord: editingWord,
          apiKeyController: widget.apiKeyController,
          ttsService: _resolveTtsService(),
        ),
      ),
    );
    if (resultMessage != null && resultMessage.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(resultMessage),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ttsService = _resolveTtsService();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final list = widget.controller.findListById(widget.listId);
        final words = widget.controller.wordsForList(widget.listId);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                if (list != null) ...[
                  Container(
                    width: 10,
                    height: 22,
                    decoration: BoxDecoration(
                      color: list.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    list?.name ?? 'Kelime Listesi',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              if (list != null)
                IconButton(
                  onPressed: () => _handleEditList(list),
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: list.isDefault
                      ? 'Rengi Düzenle'
                      : 'Listeyi / Rengi Düzenle',
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _handleOpenAddWord(list),
            tooltip: 'Kelime Ekle',
            child: const Icon(Icons.add_rounded),
          ),
          body: Column(
            children: [
              ListenableBuilder(
                listenable: ttsService,
                builder: (context, _) {
                  final ttsError = ttsService.errorMessage;
                  if (ttsError == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.volume_off_rounded,
                          size: 16,
                          color: colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ttsError,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: ttsService.clearError,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: colorScheme.onErrorContainer,
                          ),
                          tooltip: 'Kapat',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: _isInitialLoading && words.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : words.isEmpty
                        ? const EmptyWordsView()
                        : RefreshIndicator(
                            onRefresh: () => widget.controller
                                .loadWordsForList(widget.listId),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
                              itemCount: words.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = words[index];
                                return WordListTile(
                                  item: item,
                                  ttsService: ttsService,
                                  onEdit: () => _handleOpenAddWord(
                                    list,
                                    editingWord: item,
                                  ),
                                  onDelete: () =>
                                      widget.controller.removeWord(item),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
