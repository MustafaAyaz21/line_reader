import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/api_key_controller.dart';
import '../../auth/controllers/auth_controller.dart';
import '../screens/settings_screen.dart';

/// Üst barda güncelleme ikonunun yanında yer alan Ayarlar ikonu.
/// Dil seçimi, Gemini API ayarları ve hesap/misafir yönetimini açar.
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    required this.apiKeyController,
    required this.localeController,
    required this.authController,
    this.onClearCache,
  });

  final ApiKeyController apiKeyController;
  final AppLocaleController localeController;
  final AuthController authController;
  final Future<void> Function()? onClearCache;

  void _openSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          apiKeyController: apiKeyController,
          localeController: localeController,
          authController: authController,
          onClearCache: onClearCache,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey<String>('settings_action_button'),
      onPressed: () => _openSettings(context),
      tooltip: context.l10n.settingsTitle,
      icon: const Icon(Icons.settings_outlined),
    );
  }
}
