import 'package:flutter/material.dart';

import '../models/word_list.dart';

/// Yeni özel kelime listesi oluşturma veya mevcut listenin rengini/adını/logosunu
/// düzenleme penceresi.
class WordListEditorDialog extends StatefulWidget {
  const WordListEditorDialog({
    super.key,
    this.existingList,
    required this.onSubmit,
  });

  final WordList? existingList;
  final Future<String?> Function(String name, int colorValue, String? icon) onSubmit;

  static const List<String> presetIcons = <String>[
    '📁', '⭐', '📚', '💼', '✈️', '🎯', '🎓', '💡',
    '🎬', '🍔', '🔥', '🚀', '🧠', '🇬🇧', '🇺🇸', '📖',
    '🏆', '🎵', '🏷️', '💬', '🌍', '💻', '🩺', '🎨',
  ];

  static Future<bool?> show(
    BuildContext context, {
    WordList? existingList,
    required Future<String?> Function(String name, int colorValue, String? icon) onSubmit,
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
  late final TextEditingController _customEmojiController;
  late int _selectedColorValue;
  String? _selectedIcon;
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
    _selectedIcon = widget.existingList?.icon;
    _customEmojiController = TextEditingController(
      text: _selectedIcon != null && !WordListEditorDialog.presetIcons.contains(_selectedIcon)
          ? _selectedIcon
          : '',
    );
    _selectedColorValue = widget.existingList?.colorValue ??
        WordListColors.palette[1]; // Yeni listeler için varsayılan mavi
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customEmojiController.dispose();
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
      final error = await widget.onSubmit(name, _selectedColorValue, _selectedIcon);
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
            ? (_isDefaultList ? 'Liste Logosu ve Rengini Düzenle' : 'Listeyi Düzenle')
            : 'Yeni Kelime Listesi',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Canlı Önizleme Kartı (Logo + Renk + İsim)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selectedColor.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selectedColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: _selectedIcon != null && _selectedIcon!.isNotEmpty
                        ? Text(
                            _selectedIcon!,
                            style: const TextStyle(fontSize: 22),
                          )
                        : Icon(
                            _isDefaultList ? Icons.star_rounded : Icons.folder_rounded,
                            color: selectedColor,
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _nameController,
                          builder: (context, value, _) {
                            final previewName = value.text.trim().isEmpty
                                ? 'Örnek Liste'
                                : value.text.trim();
                            return Text(
                              previewName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedIcon != null
                              ? 'Özel Logo Seçili'
                              : (_isDefaultList ? 'Yıldız İkonu' : 'Klasör İkonu'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Liste Adı Alanı
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
                hintText: 'Örn: Seyahat, Sınav, İş İngilizcesi',
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
            const SizedBox(height: 18),

            // Liste Logosu / İkonu Seçimi
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Liste Logosu / İkonu',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_selectedIcon != null)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedIcon = null;
                        _customEmojiController.clear();
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'Varsayılana Dön',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Hazır İkonlar / Emojiler
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.3),
                ),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final emoji in WordListEditorDialog.presetIcons)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedIcon = emoji;
                          _customEmojiController.clear();
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _selectedIcon == emoji
                              ? selectedColor.withOpacity(0.25)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedIcon == emoji
                                ? selectedColor
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Özel Emoji Yazma Alanı (Klavyeden serbest emoji)
            TextField(
              controller: _customEmojiController,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: 'Veya klavyenden özel bir simge/emoji yaz',
                hintText: 'Örn: 🏆, 🏖️, 🎮',
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: _customEmojiController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          setState(() {
                            _customEmojiController.clear();
                            _selectedIcon = null;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (val) {
                final trimmed = val.trim();
                setState(() {
                  _selectedIcon = trimmed.isNotEmpty ? trimmed : null;
                });
              },
            ),
            const SizedBox(height: 18),

            // Liste Rengi
            Text(
              'Liste Rengi',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final colorValue in WordListColors.palette)
                  _ColorChoiceTile(
                    colorValue: colorValue,
                    isSelected: colorValue == _selectedColorValue,
                    onTap: () {
                      setState(() => _selectedColorValue = colorValue);
                    },
                  ),
              ],
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
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Kaydet' : 'Oluştur'),
        ),
      ],
    );
  }
}

class _ColorChoiceTile extends StatelessWidget {
  const _ColorChoiceTile({
    required this.colorValue,
    required this.isSelected,
    required this.onTap,
  });

  final int colorValue;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 3,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 20,
              )
            : null,
      ),
    );
  }
}
