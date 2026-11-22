import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/api_key_controller.dart';
import '../../../core/settings/ipa_accent_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_backdrop.dart';
import '../../../core/theme/app_theme_controller.dart';
import '../../../core/theme/app_theme_preset.dart';
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
  void initState() {
    super.initState();
    IpaAccentController.shared.load();
    AppThemeController.shared.load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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
    final visuals = AppThemeVisuals.of(context);

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
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

          // 3) Telaffuz / IPA Aksanı Seçimi (Amerikan US / İngiliz UK)
          _SectionTitle(
            label: s.t('Telaffuz ve IPA Aksanı', 'Pronunciation & IPA Accent'),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: IpaAccentController.shared,
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
                            Icons.record_voice_over_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.t('IPA Okunuş Aksanı', 'IPA Accent'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<IpaAccent>(
                        key: const ValueKey<String>(
                          'settings_ipa_accent_selector',
                        ),
                        segments: <ButtonSegment<IpaAccent>>[
                          ButtonSegment<IpaAccent>(
                            value: IpaAccent.us,
                            label: Text(
                              s.t('Amerikan (US)', 'American (US)'),
                            ),
                          ),
                          ButtonSegment<IpaAccent>(
                            value: IpaAccent.uk,
                            label: Text(
                              s.t('İngiliz (UK)', 'British (UK)'),
                            ),
                          ),
                        ],
                        selected: <IpaAccent>{
                          IpaAccentController.shared.accent,
                        },
                        onSelectionChanged: (selected) {
                          IpaAccentController.shared.setAccent(selected.first);
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.t(
                          'Makalelerde, tarayıcıda, kelime aramada ve Line\'da Bak kartında gösterilen IPA okunuş aksanını belirler.',
                          'Sets the IPA pronunciation accent shown across articles, browser, word search, and quick lookup.',
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

          // 4) Uygulama Teması (Kod Tabanlı Gradyan Temalar + Varsayılan)
          _SectionTitle(
            label: s.t('Uygulama Teması', 'App Theme'),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: AppThemeController.shared,
            builder: (context, _) {
              return _buildThemeSelectorCard(context, theme, colorScheme, s);
            },
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildThemeSelectorCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final activePreset = AppThemeController.shared.preset;

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
                  Icons.palette_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.t('Renk Teması ve Atmosfer', 'Color Theme & Atmosphere'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.t(
                'Ana menü, kartlar, kelime listeleri, tarayıcı çevresi ve makale okuma alanına anında uygulanır.',
                'Applies instantly to Home, cards, word lists, browser chrome, and article reading areas.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                final itemWidth = (constraints.maxWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: AppThemePreset.values.map((preset) {
                    final isSelected = activePreset == preset;
                    final title = preset.titleForLocale(isEnglish: s.isEn);
                    final subtitle =
                        preset.subtitleForLocale(isEnglish: s.isEn);
                    final isFullWidth = preset == AppThemePreset.classic;

                    return SizedBox(
                      width: isFullWidth ? constraints.maxWidth : itemWidth,
                      child: Material(
                        color: isSelected
                            ? colorScheme.primaryContainer.withAlpha(185)
                            : colorScheme.surfaceContainerHighest.withAlpha(155),
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey<String>(
                            'settings_theme_${preset.storageKey}',
                          ),
                          onTap: () =>
                              AppThemeController.shared.setPreset(preset),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.outlineVariant,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: isFullWidth
                                ? Row(
                                    children: <Widget>[
                                      AppThemePreviewSwatch(
                                        preset: preset,
                                        width: 56,
                                        height: 40,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: isSelected
                                                    ? colorScheme
                                                        .onPrimaryContainer
                                                    : colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                fontSize: 11.5,
                                                color: isSelected
                                                    ? colorScheme
                                                        .onPrimaryContainer
                                                        .withAlpha(205)
                                                    : colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 20,
                                          color: colorScheme.primary,
                                        ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Stack(
                                        children: <Widget>[
                                          AppThemePreviewSwatch(
                                            preset: preset,
                                            width: double.infinity,
                                            height: 58,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          if (isSelected)
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withAlpha(140),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.check_rounded,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          fontSize: 11,
                                          height: 1.25,
                                          color: isSelected
                                              ? colorScheme.onPrimaryContainer
                                                  .withAlpha(205)
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                );
              },
            ),
          ],
        ),
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
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        colorScheme.primaryContainer,
                        colorScheme.tertiaryContainer.withAlpha(210),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.primary.withAlpha(100),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 22,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.t('Premium Üye', 'Premium Member'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        s.t(
                          'Sınırsız çeviri • Tarayıcı AI açık • Reklamsız',
                          'Unlimited translations • Browser AI on • Ad-free',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
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
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed:
                        auth.isBusy ? null : () => _handleSignOut(context),
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: Text(s.signOut),
                  ),
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed:
                      auth.isBusy ? null : () => _handleSignOut(context),
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: Text(s.signOut),
                ),
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
