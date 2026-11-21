import 'package:flutter/material.dart';

import '../../core/settings/api_key_controller.dart';
import '../../core/tts/tts_service.dart';
import '../settings/widgets/api_key_dialog.dart';
import '../update/controllers/app_update_controller.dart';
import '../update/widgets/update_action_button.dart';
import 'controllers/words_controller.dart';
import 'list_words_screen.dart';
import 'models/word_list.dart';
import 'widgets/word_list_card.dart';
import 'widgets/word_list_editor_dialog.dart';

/// Kullanıcının varsayılan "Favoriler" listesini ve özel kelime listelerini
/// yönetebildiği "Kelimelerim" sekmesi.
class WordsScreen extends StatelessWidget {
  const WordsScreen({
    super.key,
    required this.controller,
    this.apiKeyController,
    this.updateController,
    this.ttsService,
    this.onClearCache,
  });

  final WordsController controller;
  final ApiKeyController? apiKeyController;
  final AppUpdateController? updateController;
  final TtsService? ttsService;
  final Future<void> Function()? onClearCache;

  Future<void> _handleCreateList(BuildContext context) async {
    final created = await WordListEditorDialog.show(
      context,
      onSubmit: (name, colorValue) {
        return controller.createList(name: name, colorValue: colorValue);
      },
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Yeni kelime listesi oluşturuldu.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  Future<void> _handleEditList(BuildContext context, WordList list) async {
    final updated = await WordListEditorDialog.show(
      context,
      existingList: list,
      onSubmit: (name, colorValue) {
        return controller.updateList(
          list: list,
          name: name,
          colorValue: colorValue,
        );
      },
    );
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Liste güncellendi.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  Future<void> _handleDeleteList(BuildContext context, WordList list) async {
    if (list.isDefault) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Listeyi Sil'),
        content: Text(
          '"${list.name}" listesini ve içindeki ${list.wordCount} kelimeyi silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await controller.deleteList(list.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('"${list.name}" listesi silindi.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  void _openList(BuildContext context, WordList list) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListWordsScreen(
          listId: list.id,
          controller: controller,
          apiKeyController: apiKeyController,
          ttsService: ttsService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelimelerim'),
        actions: [
          if (updateController != null)
            UpdateActionButton(controller: updateController!),
          if (apiKeyController != null) ...[
            ApiKeyActionButton(
              controller: apiKeyController!,
              onClearCache: onClearCache,
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _handleCreateList(context),
        tooltip: 'Yeni Liste Oluştur',
        child: const Icon(Icons.add_rounded),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final lists = controller.lists;

          if (controller.isLoading && lists.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (controller.errorMessage != null && lists.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      controller.errorMessage!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: controller.loadLists,
                      child: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: controller.loadLists,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
              itemCount: lists.length,
              itemBuilder: (context, index) {
                final list = lists[index];
                return WordListCard(
                  list: list,
                  onTap: () => _openList(context, list),
                  onEdit: () => _handleEditList(context, list),
                  onDelete: list.isDefault
                      ? null
                      : () => _handleDeleteList(context, list),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
