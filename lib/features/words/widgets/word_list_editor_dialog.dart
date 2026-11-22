import 'package:flutter/material.dart';

import '../models/word_list.dart';

/// Yeni özel kelime listesi oluşturma veya mevcut listenin rengini/adını
/// düzenleme penceresi.
class WordListEditorDialog extends StatefulWidget {
  const WordListEditorDialog({
    super.key,
    this.existingList,
    required this.onSubmit,
  });

  final WordList? existingList;
  final Future<String?> Function(String name, int colorValue) onSubmit;

  static Future<bool?> show(
    BuildContext context, {
    WordList? existingList,
    required Future<String?> Function(String name, int colorValue) onSubmit,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => WordListEditorDialog(
        existingList: existingList,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<WordListEditorDialog> createState() => _WordListEditorDialogState();
}

class _WordListEditorDialogState extends State<WordListEditorDialog> {
  late final TextEditingController _nameController;
  late int _selectedColorValue;
  bool _isSaving = false;
  String? _errorText;

  bool get _isEditing => widget.existingList != null;
  bool get _isDefaultList => widget.existingList?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingList?.name ?? '',
    );
    _selectedColorValue = widget.existingList?.colorValue ??
        WordListColors.palette[1]; // Yeni listeler için varsayılan mavi
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _isDefaultList
        ? widget.existingList!.name
        : _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorText = 'Lütfen bir liste adı girin.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final error = await widget.onSubmit(name, _selectedColorValue);
      if (!mounted) return;
      if (error != null) {
        setState(() => _errorText = error);
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedColor = Color(_selectedColorValue);

    return AlertDialog(
      title: Text(
        _isEditing
            ? (_isDefaultList ? 'Liste Rengini Düzenle' : 'Listeyi Düzenle')
            : 'Yeni Kelime Listesi',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sol kenar renk çubuğu canlı önizlemesi
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 8, color: selectedColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _nameController,
                          builder: (context, value, _) {
                            final previewName = value.text.trim().isEmpty
                                ? 'Örnek Liste'
                                : value.text.trim();
                            return Text(
                              previewName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey<String>('word_list_name_field'),
              controller: _nameController,
              enabled: !_isDefaultList && !_isSaving,
              autofocus: !_isEditing,
              autocorrect: true,
              enableSuggestions: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: (_) => _isSaving ? null : _handleSave(),
              decoration: InputDecoration(
                labelText: 'Liste Adı',
                hintText: 'Örn: Eğitim, Ulaşım, Hukuk',
                helperText: _isDefaultList
                    ? 'Varsayılan Favoriler listesinin adı korunur.'
                    : null,
                errorText: _errorText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sol Şerit Rengi',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: WordListColors.palette.map((colorValue) {
                final isSelected = colorValue == _selectedColorValue;
                final swatchColor = Color(colorValue);

                return GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () => setState(() => _selectedColorValue = colorValue),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: swatchColor,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: colorScheme.onSurface,
                              width: 2.5,
                            )
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('İptal'),
        ),
        FilledButton(
          key: const ValueKey<String>('word_list_save_button'),
          onPressed: _isSaving ? null : _handleSave,
          child: Text(_isEditing ? 'Kaydet' : 'Oluştur'),
        ),
      ],
    );
  }
}
