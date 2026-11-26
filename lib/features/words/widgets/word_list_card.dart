import 'package:flutter/material.dart';

import '../models/word_list.dart';

/// Modern, yuvarlatılmış köşeli ve zarif kelime listesi kartı.
class WordListCard extends StatelessWidget {
  const WordListCard({
    super.key,
    required this.list,
    required this.onTap,
    required this.onEdit,
    this.onDelete,
  });

  final WordList list;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: isDark ? const Color(0xFF141922) : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: list.color.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Liste İkon Rozeti (Dikey çizgi yerine modern yuvarlatılmış ikon kutusu)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: list.color.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: list.color.withAlpha(60),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: list.icon != null && list.icon!.isNotEmpty
                    ? Text(
                        list.icon!,
                        style: const TextStyle(fontSize: 22),
                      )
                    : Icon(
                        list.isDefault ? Icons.star_rounded : Icons.folder_rounded,
                        color: list.color,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 14),

              // Başlık ve Kelime Sayısı
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      list.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${list.wordCount} kelime',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Düzenle Butonu
              IconButton(
                onPressed: onEdit,
                icon: Icon(
                  Icons.palette_outlined,
                  size: 19,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: list.isDefault
                    ? 'Rengi Düzenle'
                    : 'Listeyi / Rengi Düzenle',
                visualDensity: VisualDensity.compact,
              ),

              // Sil Butonu
              if (!list.isDefault && onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Listeyi Sil',
                  visualDensity: VisualDensity.compact,
                ),

              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withAlpha(150),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
