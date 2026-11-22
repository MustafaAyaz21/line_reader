import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/api_key_controller.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/auth_user.dart';
import '../../auth/screens/auth_screen.dart';

/// Dil seçimi (Türkçe / İngilizce), çeviri önbelleği, hesap/yetki yönetimi
/// ("Kod Kullan" ile sınırsız yetki + 3 katmanlı kota gösterimi) sayfası.
/// Son kullanıcıdan manuel API anahtarı girmesi istenmez.
class SettingsScreen extends StatefulWidget {
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

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleClearCache(BuildContext context) async {
    final callback = widget.onClearCache;
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

  Future<void> _handleRedeemCode(BuildContext context) async {
    final rawCode = _codeController.text.trim();
    if (rawCode.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.t(
                'Lütfen bir aktivasyon kodu girin.',
                'Please enter an activation code.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }

    FocusScope.of(context).unfocus();
    final result = await widget.authController.redeemAccessCode(rawCode);
    if (!context.mounted) return;

    if (result.isSuccess) {
      _codeController.clear();
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _handleRefreshEntitlement(BuildContext context) async {
    await widget.authController.refreshEntitlement();
    if (!context.mounted) return;
    final s = context.l10n;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            widget.authController.isUnlimited
                ? s.t(
                    'Hesap yetkisi güncellendi: Sınırsız erişim aktif.',
                    'Account status refreshed: Unlimited access active.',
                  )
                : s.t(
                    'Hesap durumu güncellendi.',
                    'Account status refreshed.',
                  ),
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

    await widget.authController.signOut();
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
          // 1) Hesap / Yetki / Misafir Bölümü
          _SectionTitle(label: s.t('Hesap', 'Account')),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: widget.authController,
            builder: (context, _) {
              return _buildAccountCard(context, theme, colorScheme, s);
            },
          ),
          const SizedBox(height: 22),

          // 2) Dil Seçimi Bölümü (Sadece Arayüz: Türkçe / İngilizce)
          _SectionTitle(label: s.t('Dil Seçimi', 'Language')),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: widget.localeController,
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
                              s.t(
                                'Uygulama Arayüz Dili',
                                'App Interface Language',
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<AppLanguage>(
                        key: const ValueKey<String>(
                          'settings_language_selector',
                        ),
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
                        selected: <AppLanguage>{
                          widget.localeController.language,
                        },
                        onSelectionChanged: (selected) {
                          widget.localeController.setLanguage(selected.first);
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

          // 3) Çeviri ve Önbellek Bölümü (son kullanıcıdan manuel API anahtarı istenmez)
          _SectionTitle(
            label: s.t('Çeviri ve Önbellek', 'Translation & Cache'),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                ListTile(
                  key: const ValueKey<String>('settings_auto_translation_tile'),
                  leading: Icon(
                    Icons.auto_awesome_rounded,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    s.t(
                      'Otomatik Bağlamsal Çeviri',
                      'Automatic Contextual Translation',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    s.t(
                      'Yetkili (sınırsız) hesaplarda tarayıcıda cümle bağlamına göre yapay zeka çevirisi otomatik çalışır; manuel API anahtarı gerektirmez.',
                      'Contextual AI translation runs automatically in the browser for entitled unlimited accounts; no manual API key needed.',
                    ),
                  ),
                ),
                if (widget.onClearCache != null) ...<Widget>[
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withAlpha(120),
                  ),
                  ListTile(
                    key: const ValueKey<String>('settings_clear_cache_tile'),
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
    final auth = widget.authController;
    final user = auth.user;

    if (auth.isAuthenticated && user != null) {
      final providerLabel = user.provider == AuthProviderType.google
          ? 'Google (Gmail)'
          : s.t('E-posta', 'Email');

      if (auth.isUnlimited) {
        final codeUsed = auth.entitlementCodeUsed;
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
                        Icons.workspace_premium_rounded,
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
                Container(
                  key: const ValueKey<String>('settings_unlimited_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withAlpha(180),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.all_inclusive_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.unlimitedAccountBadge,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.t(
                          'Sınırsız çeviri • Tarayıcı AI açık • Reklamsız',
                          'Unlimited translations • Browser AI on • Ad-free',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      if (codeUsed != null && codeUsed.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          s.t(
                            'Aktif kod: $codeUsed',
                            'Active code: $codeUsed',
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: auth.isSyncingEntitlement
                          ? null
                          : () => _handleRefreshEntitlement(context),
                      icon: auth.isSyncingEntitlement
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded, size: 17),
                      label: Text(s.t('Yetkiyi Yenile', 'Refresh Status')),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: auth.isBusy
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

      // Kayıtlı Standart Hesap (günlük 80 kelime + "Kod Kullan" alanı)
      final limit = AuthController.standardUserDailyTranslationLimit;
      final remaining = auth.dailyRemainingToday;
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
                  Text(
                    s.standardAccountTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
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
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: usedFraction,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color:
                      remaining == 0 ? colorScheme.error : colorScheme.primary,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.vpn_key_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.redeemCodeTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.t(
                        'Aktivasyon kodunuz varsa aşağıya girerek sınırsız çeviri, tarayıcı AI ve reklamsız kullanımı hemen açabilirsiniz.',
                        'Enter your activation code below to unlock unlimited translations, Browser AI, and ad-free reading.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            key: const ValueKey<String>(
                              'settings_redeem_code_field',
                            ),
                            controller: _codeController,
                            enabled: !auth.isBusy,
                            textCapitalization: TextCapitalization.characters,
                            autocorrect: false,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => auth.isBusy
                                ? null
                                : _handleRedeemCode(context),
                            decoration: InputDecoration(
                              hintText: s.redeemCodeHint,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey<String>(
                            'settings_redeem_code_button',
                          ),
                          onPressed: auth.isBusy
                              ? null
                              : () => _handleRedeemCode(context),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: auth.isBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(s.redeemCodeApply),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: auth.isSyncingEntitlement
                        ? null
                        : () => _handleRefreshEntitlement(context),
                    icon: auth.isSyncingEntitlement
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 17),
                    label: Text(s.t('Yetkiyi Kontrol Et', 'Check Status')),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        auth.isBusy ? null : () => _handleSignOut(context),
                    child: Text(s.signOut),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Misafir Modu (günlük 40 kelime)
    final limit = AuthController.guestDailyTranslationLimit;
    final remaining = auth.guestRemainingToday;
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
                controller: auth,
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
