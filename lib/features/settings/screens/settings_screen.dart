import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/api_key_controller.dart';
import '../../../core/settings/display_preferences_controller.dart';
import '../../../core/settings/ipa_accent_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_backdrop.dart';
import '../../../core/theme/app_theme_controller.dart';
import '../../../core/theme/app_theme_preset.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/auth_user.dart';
import '../../auth/screens/auth_screen.dart';
import 'developer_panel_screen.dart';
import 'how_to_use_screen.dart';

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
    DisplayPreferencesController.shared.load();
    AppThemeController.shared.load();
    if (widget.authController.isAuthenticated) {
      widget.authController.refreshEntitlement();
    }
    if (widget.authController.isAuthenticated) {
      widget.authController.refreshEntitlement();
    }
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

  void _openSubPage({
    required BuildContext context,
    required String Function(AppStrings s) titleBuilder,
    required Widget Function(
      BuildContext ctx,
      ThemeData theme,
      ColorScheme colorScheme,
      AppStrings s,
    ) bodyBuilder,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsCategorySubPage(
          listenable: Listenable.merge(<Listenable>[
            widget.authController,
            widget.localeController,
            AppThemeController.shared,
            IpaAccentController.shared,
            DisplayPreferencesController.shared,
          ]),
          titleBuilder: titleBuilder,
          bodyBuilder: bodyBuilder,
        ),
      ),
    );
  }

  String _profileSummary(AppStrings s) {
    final auth = widget.authController;
    if (auth.isAuthenticated) {
      if (auth.isAuthorizedStaff) {
        return s.t('Geliştirici • Sınırsız', 'Developer • Unlimited');
      }
      if (auth.isUnlimited) {
        return s.t('Premium Üye • Sınırsız', 'Premium Member • Unlimited');
      }
      return s.t(
        'Standart Hesap • ${auth.dailyRemainingToday} / ${auth.dailyTranslationLimit}',
        'Standard Account • ${auth.dailyRemainingToday} / ${auth.dailyTranslationLimit}',
      );
    }
    return s.t(
      'Misafir Modu • ${auth.guestRemainingToday} / ${AuthController.guestDailyTranslationLimit}',
      'Guest Mode • ${auth.guestRemainingToday} / ${AuthController.guestDailyTranslationLimit}',
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
        body: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            widget.authController,
            widget.localeController,
            AppThemeController.shared,
            IpaAccentController.shared,
            DisplayPreferencesController.shared,
          ]),
          builder: (context, _) {
            final isEn = s.isEn;
            final activeTheme = AppThemeController.shared.preset
                .titleForLocale(isEnglish: isEn);
            final langLabel = widget.localeController.language == AppLanguage.en
                ? 'English'
                : 'Türkçe';
            final prefs = DisplayPreferencesController.shared;
            final auth = widget.authController;

            final cards = <Widget>[
              _SettingsCategoryCard(
                key: const ValueKey<String>('settings_cat_profile'),
                expandFill: true,
                icon: auth.isAuthorizedStaff
                    ? Icons.code_rounded
                    : Icons.person_outline_rounded,
                iconBg: colorScheme.primaryContainer,
                iconColor: colorScheme.onPrimaryContainer,
                title: s.t('Profil ve Hesap', 'Profile & Account'),
                subtitle: _profileSummary(s),
                onTap: () => _openSubPage(
                  context: context,
                  titleBuilder: (ls) =>
                      ls.t('Profil ve Hesap', 'Profile & Account'),
                  bodyBuilder: (ctx, th, cs, ls) => RefreshIndicator(
                    onRefresh: () async {
                      if (widget.authController.isAuthenticated) {
                        await widget.authController
                            .refreshEntitlement(forceTokenRefresh: true);
                      }
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                      children: <Widget>[
                        _buildAccountCard(ctx, th, cs, ls),
                      ],
                    ),
                  ),
                ),
              ),
              _SettingsCategoryCard(
                key: const ValueKey<String>('settings_cat_appearance'),
                expandFill: true,
                icon: Icons.palette_outlined,
                iconBg: colorScheme.secondaryContainer,
                iconColor: colorScheme.onSecondaryContainer,
                title: s.t('Görünüm ve Temalar', 'Appearance & Themes'),
                subtitle: '$langLabel • $activeTheme',
                onTap: () => _openSubPage(
                  context: context,
                  titleBuilder: (ls) =>
                      ls.t('Görünüm ve Temalar', 'Appearance & Themes'),
                  bodyBuilder: (ctx, th, cs, ls) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    children: <Widget>[
                      _SectionTitle(label: ls.t('Dil Seçimi', 'Language')),
                      const SizedBox(height: 8),
                      _buildLanguageCard(th, cs, ls),
                      const SizedBox(height: 22),
                      _SectionTitle(
                        label: ls.t('Uygulama Teması', 'App Theme'),
                      ),
                      const SizedBox(height: 8),
                      _buildThemeSelectorCard(ctx, th, cs, ls),
                    ],
                  ),
                ),
              ),
              _SettingsCategoryCard(
                key: const ValueKey<String>('settings_cat_features'),
                expandFill: true,
                icon: Icons.tune_rounded,
                iconBg: colorScheme.tertiaryContainer,
                iconColor: colorScheme.onTertiaryContainer,
                title: s.t('Özellikler', 'Features'),
                subtitle:
                    'IPA: ${prefs.appIpaMode.label(isEnglish: isEn)} • ${s.t('Eş & Zıt Anlam', 'Synonyms & Antonyms')}',
                onTap: () => _openSubPage(
                  context: context,
                  titleBuilder: (ls) => ls.t('Özellikler', 'Features'),
                  bodyBuilder: (ctx, th, cs, ls) =>
                      _buildFeaturesBody(th, cs, ls),
                ),
              ),
              _SettingsCategoryCard(
                key: const ValueKey<String>('settings_cat_quick_lookup'),
                expandFill: true,
                icon: Icons.manage_search_rounded,
                iconBg: colorScheme.primaryContainer.withAlpha(200),
                iconColor: colorScheme.primary,
                title: s.t("Line'da Bak", 'Quick Lookup'),
                subtitle:
                    'IPA: ${prefs.overlayIpaMode.label(isEnglish: isEn)} • ${s.t('Mini kart', 'Mini card')}',
                onTap: () => _openSubPage(
                  context: context,
                  titleBuilder: (ls) =>
                      ls.t("Line'da Bak Ayarları", 'Quick Lookup Settings'),
                  bodyBuilder: (ctx, th, cs, ls) =>
                      _buildQuickLookupBody(th, cs, ls),
                ),
              ),
              _SettingsCategoryCard(
                key: const ValueKey<String>('settings_cat_how_to_use'),
                expandFill: true,
                icon: Icons.help_outline_rounded,
                iconBg: colorScheme.secondaryContainer.withAlpha(210),
                iconColor: colorScheme.onSecondaryContainer,
                title: s.t('Nasıl Kullanılır?', 'How to Use'),
                subtitle: s.t(
                  'Tüm özelliklerin adım adım hızlı rehberi',
                  'Step-by-step quick guide to every feature',
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HowToUseScreen(),
                    ),
                  );
                },
              ),
            ];

            return LayoutBuilder(
              builder: (context, constraints) {
                const verticalPadding = 32.0; // top 14 + bottom 18
                const cardSpacing = 12.0;
                const minCardHeight = 88.0;
                final minContentHeight = (cards.length * minCardHeight) +
                    ((cards.length - 1) * cardSpacing) +
                    verticalPadding;
                final totalHeight = constraints.maxHeight > minContentHeight
                    ? constraints.maxHeight
                    : minContentHeight;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: SizedBox(
                    height: totalHeight - verticalPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (var i = 0; i < cards.length; i++) ...<Widget>[
                          Expanded(child: cards[i]),
                          if (i < cards.length - 1)
                            const SizedBox(height: cardSpacing),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLanguageCard(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
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
              selected: <AppLanguage>{widget.localeController.language},
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
  }

  Widget _buildFeaturesBody(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final prefs = DisplayPreferencesController.shared;
    final isEn = s.isEn;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: <Widget>[
        _SectionTitle(
          label: s.t('Telaffuz ve IPA Gösterimi', 'Pronunciation & IPA'),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  s.t('Uygulama İçi IPA Modu', 'In-App IPA Display'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.t(
                    'Makalelerde, tarayıcıda ve kelime listelerinde hangi IPA okunuşlarının görüneceğini seçin.',
                    'Choose which IPA pronunciations appear across articles, browser, and word lists.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: IpaDisplayMode.values.map((mode) {
                    return ChoiceChip(
                      key: ValueKey<String>(
                        'settings_app_ipa_${mode.storageValue}',
                      ),
                      label: Text(mode.label(isEnglish: isEn)),
                      selected: prefs.appIpaMode == mode,
                      onSelected: (_) {
                        prefs.setAppIpaMode(mode);
                        IpaAccentController.shared.setEnabled(mode.isEnabled);
                      },
                    );
                  }).toList(growable: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(
          label: s.t('Kelime Kartı İçeriği', 'Word Card Content'),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              SwitchListTile(
                key: const ValueKey<String>('settings_app_synonyms_switch'),
                title: Text(s.t('Eş Anlamlıları Göster', 'Show Synonyms')),
                subtitle: Text(
                  s.t(
                    'Kelime önizleme kartında eş anlamlıları listeler.',
                    'Lists synonyms inside the word preview card.',
                  ),
                ),
                value: prefs.appShowSynonyms,
                onChanged: prefs.setAppShowSynonyms,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey<String>('settings_app_antonyms_switch'),
                title: Text(s.t('Zıt Anlamlıları Göster', 'Show Antonyms')),
                subtitle: Text(
                  s.t(
                    'Kelime önizleme kartında zıt anlamlıları listeler.',
                    'Lists antonyms inside the word preview card.',
                  ),
                ),
                value: prefs.appShowAntonyms,
                onChanged: prefs.setAppShowAntonyms,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickLookupBody(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final prefs = DisplayPreferencesController.shared;
    final isEn = s.isEn;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: <Widget>[
        _SectionTitle(
          label: s.t("Line'da Bak Mini Kartı", 'Quick Lookup Mini Card'),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  s.t('Mini Kartta IPA Gösterimi', 'IPA in Mini Card'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.t(
                    'Başka bir uygulamada kelime seçip "Line\'da Bak" açtığında kaç IPA aksanı görüneceğini seçin.',
                    'Choose which IPA accents appear when using Quick Lookup from other apps.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: IpaDisplayMode.values.map((mode) {
                    return ChoiceChip(
                      key: ValueKey<String>(
                        'overlay_ipa_mode_${mode.storageValue}',
                      ),
                      label: Text(mode.label(isEnglish: isEn)),
                      selected: prefs.overlayIpaMode == mode,
                      onSelected: (_) => prefs.setOverlayIpaMode(mode),
                    );
                  }).toList(growable: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              SwitchListTile(
                key: const ValueKey<String>('overlay_show_synonyms_switch'),
                title: Text(s.t('Eş Anlamlılar', 'Synonyms')),
                subtitle: Text(
                  s.t(
                    'Mini kartta eş anlamlı kelimeleri göster.',
                    'Show synonyms in the mini card.',
                  ),
                ),
                value: prefs.overlayShowSynonyms,
                onChanged: prefs.setOverlayShowSynonyms,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey<String>('overlay_show_antonyms_switch'),
                title: Text(s.t('Zıt Anlamlılar', 'Antonyms')),
                subtitle: Text(
                  s.t(
                    'Mini kartta zıt anlamlı kelimeleri göster.',
                    'Show antonyms in the mini card.',
                  ),
                ),
                value: prefs.overlayShowAntonyms,
                onChanged: prefs.setOverlayShowAntonyms,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey<String>('overlay_show_tts_switch'),
                title: Text(
                  s.t('Sesli Dinleme Butonu', 'Pronunciation Button'),
                ),
                subtitle: Text(
                  s.t(
                    'Üst çubukta kelimeyi sesli dinleme ikonunu göster.',
                    'Show the speaker icon in the top bar.',
                  ),
                ),
                value: prefs.overlayShowTts,
                onChanged: prefs.setOverlayShowTts,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey<String>('overlay_show_save_bar_switch'),
                title: Text(
                  s.t('Liste Seç & Kaydet Çubuğu', 'List & Save Bar'),
                ),
                subtitle: Text(
                  s.t(
                    'Kapatırsan mini kart sadece hızlı anlam gösterimi için sadeleşir.',
                    'Turn off for an ultra-compact meaning-only mini card.',
                  ),
                ),
                value: prefs.overlayShowSaveBar,
                onChanged: prefs.setOverlayShowSaveBar,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemeSelectorCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final auth = widget.authController;
    final isAuthenticated = auth.isAuthenticated;
    final isPremium = auth.isUnlimited;
    final activePreset = AppThemeController.shared.preset;
    final canSeeSpecialThemes = auth.hasSpecialThemes;
    final activeTitle = activePreset.titleForLocale(isEnglish: s.isEn);

    final staticSubtitle = !isAuthenticated
        ? s.t('Üye olup temayı kullanabilirsiniz', 'Sign up to use themes')
        : (!activePreset.isAnimatedTheme && !activePreset.isSpecialTheme
            ? '${s.t('Seçili', 'Active')}: $activeTitle'
            : s.t(
                'Varsayılan ve 4 hareketsiz renk teması',
                'Classic & 4 static color themes',
              ));

    final animatedSubtitle = !isPremium
        ? s.t("Premium'a özel", 'Premium only')
        : (activePreset.isAnimatedTheme && !activePreset.isSpecialTheme
            ? '${s.t('Seçili', 'Active')}: $activeTitle'
            : s.t(
                '4 sakin hareketli vektör tema',
                '4 calm animated vector themes',
              ));

    final specialSubtitle = activePreset.isSpecialTheme
        ? '${s.t('Seçili', 'Active')}: $activeTitle'
        : s.t('Size özel tanımlı temalar', 'Exclusive themes unlocked for you');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!isAuthenticated) ...<Widget>[
          _buildGuestThemeLockBanner(
            context: context,
            theme: theme,
            colorScheme: colorScheme,
            s: s,
            bannerKey: const ValueKey<String>('settings_theme_guest_banner'),
            buttonKey: const ValueKey<String>('settings_theme_guest_signup_btn'),
          ),
          const SizedBox(height: 10),
        ],
        _SettingsCategoryCard(
          key: const ValueKey<String>('settings_theme_cat_static'),
          icon: isAuthenticated
              ? Icons.layers_outlined
              : Icons.lock_outline_rounded,
          iconBg: colorScheme.primaryContainer,
          iconColor: colorScheme.onPrimaryContainer,
          title: s.t('Hareketsiz Temalar', 'Static Themes'),
          subtitle: staticSubtitle,
          onTap: () => _openSubPage(
            context: context,
            titleBuilder: (ls) => ls.t('Hareketsiz Temalar', 'Static Themes'),
            bodyBuilder: (ctx, th, cs, ls) => _buildThemeCategoryPage(
              context: ctx,
              presets: AppThemePreset.staticPresets,
              description: ls.t(
                'Ana menü, kartlar, kelime listeleri, tarayıcı çevresi ve makale okuma alanına anında uygulanır.',
                'Applies instantly to Home, cards, word lists, browser chrome, and article reading areas.',
              ),
              showAnimationControls: false,
              requiresPremium: false,
              theme: th,
              colorScheme: cs,
              s: ls,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SettingsCategoryCard(
          key: const ValueKey<String>('settings_theme_cat_animated'),
          icon: isPremium
              ? Icons.auto_awesome_rounded
              : Icons.workspace_premium_rounded,
          iconBg: colorScheme.secondaryContainer,
          iconColor: colorScheme.onSecondaryContainer,
          title: s.t('Hareketli Temalar', 'Animated Themes'),
          subtitle: animatedSubtitle,
          onTap: () => _openSubPage(
            context: context,
            titleBuilder: (ls) => ls.t('Hareketli Temalar', 'Animated Themes'),
            bodyBuilder: (ctx, th, cs, ls) => _buildThemeCategoryPage(
              context: ctx,
              presets: AppThemePreset.animatedPresets,
              description: ls.t(
                'Göz yormayan, sakin vektör animasyonlu temalar. Uygulama küçültülünce otomatik duraklayıp pil tasarrufu sağlar.',
                'Calm, eye-friendly vector animated themes. Auto-pauses when minimized to save battery.',
              ),
              showAnimationControls: true,
              requiresPremium: true,
              theme: th,
              colorScheme: cs,
              s: ls,
            ),
          ),
        ),
        if (canSeeSpecialThemes &&
            AppThemePreset.specialPresets.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _SettingsCategoryCard(
            key: const ValueKey<String>('settings_theme_cat_special'),
            icon: Icons.workspace_premium_rounded,
            iconBg: colorScheme.tertiaryContainer,
            iconColor: colorScheme.onTertiaryContainer,
            title: s.t('Özel Temalar', 'Special Themes'),
            subtitle: specialSubtitle,
            onTap: () => _openSubPage(
              context: context,
              titleBuilder: (ls) => ls.t('Özel Temalar', 'Special Themes'),
              bodyBuilder: (ctx, th, cs, ls) => _buildThemeCategoryPage(
                context: ctx,
                presets: AppThemePreset.specialPresets,
                description: ls.t(
                  'Hesabınıza özel tanımlanmış koleksiyon temaları.',
                  'Exclusive collection themes unlocked for your account.',
                ),
                showAnimationControls: true,
                requiresPremium: false,
                theme: th,
                colorScheme: cs,
                s: ls,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGuestThemeLockBanner({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required AppStrings s,
    Key? bannerKey,
    Key? buttonKey,
  }) {
    return Card(
      key: bannerKey,
      margin: EdgeInsets.zero,
      color: colorScheme.primaryContainer.withAlpha(115),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withAlpha(32),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.t(
                          'Kayıt olmayan kullanıcılar tema kullanamaz',
                          'Unregistered users cannot use themes',
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.t(
                          'Üye olup temayı kullanabilirsiniz.',
                          'Sign up to unlock and use themes.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: buttonKey,
              onPressed: () {
                AuthScreen.show(
                  context,
                  controller: widget.authController,
                  initialSignUpTab: true,
                );
              },
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text(s.t('Kayıt Ol', 'Sign Up')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumThemeBanner({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required AppStrings s,
  }) {
    return Container(
      key: const ValueKey<String>('settings_theme_animated_premium_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withAlpha(155),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.secondary.withAlpha(95)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.workspace_premium_rounded,
            size: 22,
            color: colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.t("Premium'a özel", 'Premium only'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCategoryPage({
    required BuildContext context,
    required List<AppThemePreset> presets,
    required String description,
    required bool showAnimationControls,
    required bool requiresPremium,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required AppStrings s,
  }) {
    final auth = widget.authController;
    final isAuthenticated = auth.isAuthenticated;
    final isPremium = auth.isUnlimited;
    final isLockedForGuest = !isAuthenticated;
    final isLockedForPremium = requiresPremium && !isPremium;
    final isLocked = isLockedForGuest || isLockedForPremium;

    final activePreset = AppThemeController.shared.preset;
    final isAnimationPaused = AppThemeController.shared.isAnimationPaused;
    final isEcoAnimation = AppThemeController.shared.isEcoAnimation;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: <Widget>[
        if (isLockedForGuest) ...<Widget>[
          _buildGuestThemeLockBanner(
            context: context,
            theme: theme,
            colorScheme: colorScheme,
            s: s,
            bannerKey: const ValueKey<String>(
              'settings_theme_subpage_guest_banner',
            ),
            buttonKey: const ValueKey<String>(
              'settings_theme_subpage_guest_signup_btn',
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (isLockedForPremium) ...<Widget>[
          _buildPremiumThemeBanner(
            theme: theme,
            colorScheme: colorScheme,
            s: s,
          ),
          const SizedBox(height: 12),
        ],
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                _buildThemePresetGrid(
                  presets: presets,
                  activePreset: activePreset,
                  isLocked: isLocked,
                  theme: theme,
                  colorScheme: colorScheme,
                  s: s,
                ),
                if (showAnimationControls && !isLocked) ...<Widget>[
                  const SizedBox(height: 14),
                  Material(
                    color: colorScheme.surfaceContainerHighest.withAlpha(135),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      key: const ValueKey<String>(
                        'settings_theme_pause_animation_switch',
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      dense: true,
                      secondary: Icon(
                        isAnimationPaused
                            ? Icons.pause_circle_outline_rounded
                            : Icons.motion_photos_on_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      title: Text(
                        s.t('Animasyonu Duraklat', 'Pause Animation'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        s.t(
                          'Arka plan animasyonunu sabitler (uygulama küçültülünce otomatik durur).',
                          'Freezes background motion (auto-pauses when minimized).',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      value: isAnimationPaused,
                      onChanged: (value) =>
                          AppThemeController.shared.setAnimationPaused(value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: colorScheme.surfaceContainerHighest.withAlpha(135),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      key: const ValueKey<String>(
                        'settings_theme_eco_animation_switch',
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      dense: true,
                      secondary: Icon(
                        Icons.battery_saver_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      title: Text(
                        s.t('Pil Dostu Animasyon', 'Battery-Saver Motion'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        s.t(
                          'Daha az yaprak ve daha sakin hızla sıfır kasma sağlar.',
                          'Fewer particles and gentler speed for zero lag.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      value: isEcoAnimation,
                      onChanged: isAnimationPaused
                          ? null
                          : (value) =>
                              AppThemeController.shared.setEcoAnimation(value),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThemePresetGrid({
    required List<AppThemePreset> presets,
    required AppThemePreset activePreset,
    required bool isLocked,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required AppStrings s,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: presets.map((preset) {
            final isSelected = activePreset == preset;
            final title = preset.titleForLocale(isEnglish: s.isEn);
            final subtitle = preset.subtitleForLocale(isEnglish: s.isEn);
            final isFullWidth = preset == AppThemePreset.classic;

            return SizedBox(
              width: isFullWidth ? constraints.maxWidth : itemWidth,
              child: Opacity(
                opacity: isLocked && !isSelected ? 0.65 : 1.0,
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
                    onTap: isLocked
                        ? null
                        : () => AppThemeController.shared.setPreset(preset),
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
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontSize: 11.5,
                                          color: isSelected
                                              ? colorScheme.onPrimaryContainer
                                                  .withAlpha(205)
                                              : colorScheme.onSurfaceVariant,
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
                                  )
                                else if (isLocked)
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Stack(
                                  children: <Widget>[
                                    AppThemePreviewSwatch(
                                      preset: preset,
                                      width: double.infinity,
                                      height: 58,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    if (isSelected)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(140),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    else if (isLocked)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(140),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.lock_outline_rounded,
                                            size: 13,
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
                                  style: theme.textTheme.labelLarge?.copyWith(
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
                                  style: theme.textTheme.bodySmall?.copyWith(
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
              ),
            );
          }).toList(growable: false),
        );
      },
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
        final isStaff = auth.isAuthorizedStaff;
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
                        isStaff
                            ? Icons.verified_user_rounded
                            : Icons.workspace_premium_rounded,
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
                            isStaff
                                ? Icons.code_rounded
                                : Icons.workspace_premium_rounded,
                            size: 22,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isStaff
                                  ? s.t('Geliştirici', 'Developer')
                                  : s.t('Premium Üye', 'Premium Member'),
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
                      if (isStaff) ...<Widget>[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey<String>(
                              'settings_developer_panel_button',
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DeveloperPanelScreen(
                                    authController: auth,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                              size: 18,
                            ),
                            label: Text(
                              s.t('Geliştirici Paneli', 'Developer Panel'),
                            ),
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

class _SettingsCategoryCard extends StatelessWidget {
  const _SettingsCategoryCard({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.expandFill = false,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool expandFill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconBoxSize = expandFill ? 52.0 : 44.0;
    final iconSize = expandFill ? 26.0 : 22.0;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expandFill ? 18 : 16,
              vertical: expandFill ? 14 : 16,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(expandFill ? 16 : 14),
                  ),
                  child: Icon(icon, color: iconColor, size: iconSize),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: expandFill ? 17 : null,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: expandFill ? 13 : null,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: expandFill ? 24 : 22,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCategorySubPage extends StatelessWidget {
  const _SettingsCategorySubPage({
    required this.listenable,
    required this.titleBuilder,
    required this.bodyBuilder,
  });

  final Listenable listenable;
  final String Function(AppStrings s) titleBuilder;
  final Widget Function(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) bodyBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final s = context.l10n;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final visuals = AppThemeVisuals.of(context);

        return AppThemeBackdrop(
          child: Scaffold(
            backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
            appBar: AppBar(
              title: Text(titleBuilder(s)),
            ),
            body: bodyBuilder(context, theme, colorScheme, s),
          ),
        );
      },
    );
  }
}
