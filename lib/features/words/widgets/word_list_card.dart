import 'package:flutter/material.dart';

import '../models/word_list.dart';

/// Sol kenarında belirgin dikey renk barı bulunan kelime listesi kartı.
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sol taraf dikey renk barı
              Container(
                width: 8,
                color: list.color,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (list.isDefault) ...[
                                  Icon(
                                    Icons.star_rounded,
                                    size: 18,
                                    color: list.color,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    list.name,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${list.wordCount} kelime',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onEdit,
                        icon: Icon(
                          Icons.palette_outlined,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: list.isDefault
                            ? 'Rengi Düzenle'
                            : 'Listeyi / Rengi Düzenle',
                        visualDensity: VisualDensity.compact,
                      ),
                      if (!list.isDefault && onDelete != null)
                        IconButton(
                          onPressed: onDelete,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          tooltip: 'Listeyi Sil',
                          visualDensity: VisualDensity.compact,
                        ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
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
  }
}
