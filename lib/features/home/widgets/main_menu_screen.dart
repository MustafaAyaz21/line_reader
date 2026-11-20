import 'package:flutter/material.dart';

import '../../../core/settings/api_key_controller.dart';
import '../../settings/widgets/api_key_dialog.dart';
import '../../update/controllers/app_update_controller.dart';
import '../../update/widgets/update_action_button.dart';

/// Uygulamanın sade Ana Menü ekranı.
/// Tam ortada belirgin "Tarayıcı" kartı, sağ üstte ise güncelleme ikonu ve
/// Gemini API anahtarı ayar ikonu yer alır.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({
    super.key,
    required this.onOpenBrowser,
    required this.apiKeyController,
    this.updateController,
    this.onClearCache,
  });

  final VoidCallback onOpenBrowser;
  final ApiKeyController apiKeyController;
  final AppUpdateController? updateController;
  final Future<void> Function()? onClearCache;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ana Menü'),
        actions: [
          if (updateController != null)
            UpdateActionButton(controller: updateController!),
          ApiKeyActionButton(
            controller: apiKeyController,
            onClearCache: onClearCache,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Material(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpenBrowser,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.public_rounded,
                          size: 38,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Tarayıcı',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Makale açın, kelimelere dokunarak bağlamına göre anlamını öğrenin.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onOpenBrowser,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text('Tarayıcıyı Aç'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
