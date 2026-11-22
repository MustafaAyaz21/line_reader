import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/api_key_controller.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/auth_user.dart';
import '../../auth/screens/auth_screen.dart';
import '../widgets/api_key_dialog.dart';

/// Dil seçimi (Türkçe / İngilizce), Gemini API ayarları, çeviri önbelleği ve
/// hesap/misafir kotası yönetimini tek ekranda toplayan Ayarlar sayfası.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
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

  Future<void> _handleClearCache(BuildContext context) async {
    final callback = onClearCache;
    if (callback == null) return;
    await callback();
    if (!context.mounted) return;
    final s = context.l10n;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            s.t('Çeviri önbelleği temizlendi.', 'Translation cache cleared.'),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final s = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.signOut),
        content: Text(
          s.t(
            'Hesabınızdan çıkış yapmak istediğinize emin misiniz? Misafir moduna (günlük 40 kelime hakkı) geçilecektir.',
            'Are you sure you want to sign out? You will switch to Guest Mode (40 words/day limit).',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.signOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await authController.signOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            s.t('Hesaptan çıkış yapıldı.', 'Signed out successfully.'),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          // 1) Hesap / Misafir Bölümü
          _SectionTitle(label: s.t('Hesap', 'Account')),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: authController,
            builder: (context, _) {
              return _buildAccountCard(context, theme, colorScheme, s);
            },
          ),
          const SizedBox(height: 22),

          // 2) Dil Seçimi Bölümü (Sadece Arayüz: Türkçe / İngilizce)
          _SectionTitle(label: s.t('Dil Seçimi', 'Language')),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: localeController,
            builder: (context, _) {
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.translate_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.t('Uygulama Arayüz Dili', 'App Interface Language'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<AppLanguage>(
                        key: const ValueKey<String>('settings_language_selector'),
                        segments: const <ButtonSegment<AppLanguage>>[
                          ButtonSegment<AppLanguage>(
                            value: AppLanguage.tr,
                            label: Text('Türkçe'),
                          ),
                          ButtonSegment<AppLanguage>(
                            value: AppLanguage.en,
                            label: Text('English'),
                          ),
                        ],
                        selected: <AppLanguage>{localeController.language},
                        onSelectionChanged: (selected) {
                          localeController.setLanguage(selected.first);
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.t(
                          'Yalnızca uygulama arayüzü değişir; kelime çevirileri Türkçe, makaleler orijinal dilinde kalır.',
                          'Only the app interface changes; word translations remain in Turkish and articles stay in their original language.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),

          // 3) API Ayarları ve Önbellek Bölümü
          _SectionTitle(label: s.t('API Ayarları', 'API Settings')),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: apiKeyController,
            builder: (context, _) {
              final status = apiKeyController.status;
              final (String statusLabel, Color badgeBg, Color badgeFg) =
                  switch (status) {
                ApiKeyStatus.valid => (
                    s.t('Doğrulandı (Gemini aktif)', 'Verified (Gemini active)'),
                    colorScheme.primaryContainer,
                    colorScheme.onPrimaryContainer,
                  ),
                ApiKeyStatus.invalid => (
                    s.t('Geçersiz anahtar', 'Invalid key'),
                    colorScheme.errorContainer,
                    colorScheme.onErrorContainer,
                  ),
                ApiKeyStatus.unverified => (
                    s.t('Doğrulanmadı', 'Unverified'),
                    colorScheme.secondaryContainer,
                    colorScheme.onSecondaryContainer,
                  ),
                ApiKeyStatus.none => (
                    s.t('Ücretsiz varsayılan servis', 'Free default service'),
                    colorScheme.surfaceContainerHighest,
                    colorScheme.onSurfaceVariant,
                  ),
              };

              return Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: <Widget>[
                    ListTile(
                      key: const ValueKey<String>('settings_api_key_tile'),
                      leading: Icon(
                        Icons.key_rounded,
                        color: status == ApiKeyStatus.valid
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        s.t('Gemini API Anahtarı', 'Gemini API Key'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: badgeFg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => ApiKeyDialog.show(
                        context,
                        controller: apiKeyController,
                        onClearCache: onClearCache,
                      ),
                    ),
                    if (onClearCache != null) ...<Widget>[
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colorScheme.outlineVariant.withAlpha(120),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.cleaning_services_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          s.t(
                            'Çeviri Önbelleğini Temizle',
                            'Clear Translation Cache',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          s.t(
                            'Yerel SQLite kelime çeviri önbelleğini sıfırlar.',
                            'Resets the local SQLite word translation cache.',
                          ),
                        ),
                        onTap: () => _handleClearCache(context),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final user = authController.user;
    if (authController.isAuthenticated && user != null) {
      final providerLabel =
          user.provider == AuthProviderType.google ? 'Google (Gmail)' : s.t('E-posta', 'Email');
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_rounded,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user.effectiveName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (user.email.isNotEmpty)
                          Text(
                            user.email,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      providerLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.all_inclusive_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.t(
                        'Sınırsız günlük kelime çevirisi aktif',
                        'Unlimited daily word translations active',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: authController.isBusy
                        ? null
                        : () => _handleSignOut(context),
                    child: Text(s.signOut),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final limit = AuthController.guestDailyTranslationLimit;
    final remaining = authController.guestRemainingToday;
    final usedFraction = ((limit - remaining) / limit).clamp(0.0, 1.0);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.guestModeTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.guestQuotaRemaining(remaining, limit),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: remaining == 0
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: usedFraction,
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: remaining == 0 ? colorScheme.error : colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              s.guestLimitNotice(limit),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('settings_sign_in_button'),
              onPressed: () => AuthScreen.show(
                context,
                controller: authController,
                initialSignUpTab: true,
              ),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(
                s.t('Giriş Yap / Kayıt Ol', 'Sign In / Sign Up'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
