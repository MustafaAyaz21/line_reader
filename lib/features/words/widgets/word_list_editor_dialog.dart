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

  static const Map<String, List<String>> iconCategories = <String, List<String>>{
    'Genel': <String>[
      '📁', '⭐', '🏷️', '💡', '💬', '🏆', '🔥', '🚀',
      '🎯', '📌', '❤️', '💎', '🔑', '🔔', '✨', '⚡',
    ],
    'Öğrenme': <String>[
      '📚', '📖', '🎓', '🧠', '🇬🇧', '🇺🇸', '✍️', '📝',
      '🏫', '🔍', '📜', '📐', '🗣️', '🎧', '🇩🇪', '🇫🇷',
    ],
    'Yaşam': <String>[
      '💼', '💻', '✈️', '🌍', '🍔', '🎵', '🩺', '🎨',
      '☕', '🏖️', '🎬', '⚽', '🌿', '🌱', '🛍️', '🕹️',
    ],
  };

  static final List<String> presetIcons = <String>[
    for (final list in iconCategories.values) ...list,
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
  int _selectedCategoryIndex = 0;
  bool _isSaving = false;
  String? _errorText;

  bool get _isEditing => widget.existingList != null;
  bool get _isDefaultList => widget.existingList?.isDefault ?? false;

  final List<String> _categoryKeys = const <String>[
    'Genel',
    'Öğrenme',
    'Yaşam',
    'Özel',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingList?.name ?? '',
    );
    _selectedIcon = widget.existingList?.icon;
    final isCustom = _selectedIcon != null &&
        !WordListEditorDialog.presetIcons.contains(_selectedIcon);
    _customEmojiController = TextEditingController(
      text: isCustom ? _selectedIcon : '',
    );
    if (isCustom) {
      _selectedCategoryIndex = 3; // 'Özel' sekmesi
    } else if (_selectedIcon != null) {
      if (WordListEditorDialog.iconCategories['Öğrenme']!.contains(_selectedIcon)) {
        _selectedCategoryIndex = 1;
      } else if (WordListEditorDialog.iconCategories['Yaşam']!.contains(_selectedIcon)) {
        _selectedCategoryIndex = 2;
      } else {
        _selectedCategoryIndex = 0;
      }
    }
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
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Canlı Önizleme Kartı (Logo + Renk + İsim)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selectedColor.withOpacity(0.35),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selectedColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selectedColor.withOpacity(0.55),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: _selectedIcon != null && _selectedIcon!.isNotEmpty
                          ? Text(
                              _selectedIcon!,
                              style: const TextStyle(fontSize: 24),
                            )
                          : Icon(
                              _isDefaultList ? Icons.star_rounded : Icons.folder_rounded,
                              color: selectedColor,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _nameController,
                            builder: (context, value, _) {
                              final previewName = value.text.trim().isEmpty
                                  ? (_isDefaultList ? widget.existingList!.name : 'Örnek Liste')
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
                            _selectedIcon != null && _selectedIcon!.isNotEmpty
                                ? 'Logo: $_selectedIcon'
                                : (_isDefaultList ? 'Varsayılan Yıldız' : 'Varsayılan Klasör'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
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

              // Liste Logosu / İkonu Başlık & Sıfırlama
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
                  if (_selectedIcon != null && _selectedIcon!.isNotEmpty)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedIcon = null;
                          _customEmojiController.clear();
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close_rounded, size: 14, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Varsayılana Dön',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Kategori Seçim Hapları (Tabs / Chips)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildCategoryChip(
                      context,
                      label: '🎯 Genel',
                      index: 0,
                      selectedColor: selectedColor,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryChip(
                      context,
                      label: '📚 Öğrenme',
                      index: 1,
                      selectedColor: selectedColor,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryChip(
                      context,
                      label: '💼 Yaşam',
                      index: 2,
                      selectedColor: selectedColor,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryChip(
                      context,
                      label: '⌨️ Özel Simge',
                      index: 3,
                      selectedColor: selectedColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // İkon Palet Paneli
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: _selectedCategoryIndex == 3
                    ? _buildCustomEmojiSection(context, selectedColor)
                    : _buildPresetIconsGrid(context, selectedColor),
              ),
              const SizedBox(height: 20),

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

  Widget _buildCategoryChip(
    BuildContext context, {
    required String label,
    required int index,
    required Color selectedColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = _selectedCategoryIndex == index;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedCategoryIndex = index),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? selectedColor.withOpacity(0.18)
                : colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? selectedColor
                  : colorScheme.outlineVariant.withOpacity(0.35),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isSelected ? selectedColor : colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetIconsGrid(BuildContext context, Color selectedColor) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final categoryKey = _categoryKeys[_selectedCategoryIndex];
    final icons = WordListEditorDialog.iconCategories[categoryKey] ??
        WordListEditorDialog.iconCategories['Genel']!;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final emoji in icons)
          _buildEmojiTile(
            emoji: emoji,
            isSelected: _selectedIcon == emoji,
            selectedColor: selectedColor,
            colorScheme: colorScheme,
            onTap: () {
              setState(() {
                _selectedIcon = emoji;
                _customEmojiController.clear();
              });
            },
          ),
      ],
    );
  }

  Widget _buildEmojiTile({
    required String emoji,
    required bool isSelected,
    required Color selectedColor,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isSelected
                ? selectedColor.withOpacity(0.24)
                : colorScheme.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? selectedColor
                  : colorScheme.outlineVariant.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: selectedColor.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomEmojiSection(BuildContext context, Color selectedColor) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customEmojiController,
                maxLength: 4,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Klavyeden simge veya emoji yaz',
                  hintText: 'Örn: 🏆, 🏖️, 🎮, 🪐',
                  counterText: '',
                  isDense: true,
                  prefixIcon: const Icon(Icons.emoji_emotions_outlined, size: 20),
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
            ),
            const SizedBox(width: 10),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selectedColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selectedColor,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _customEmojiController.text.isNotEmpty
                    ? _customEmojiController.text
                    : '?',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Klavyenizin emoji menüsünden istediğiniz herhangi bir simgeyi yazabilirsiniz.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
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
