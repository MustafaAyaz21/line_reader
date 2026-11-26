import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme_backdrop.dart';
import '../../auth/controllers/auth_controller.dart';
import '../services/developer_panel_service.dart';

/// Yalnızca sunucu tarafından doğrulanan Geliştirici (`admin`) hesaplarına
/// Ayarlar ekranında otomatik açılan mobil yönetim paneli.
///
/// - İstediği Gmail'e Premium Üye yetkisi verme / kaldırma
/// - Aktivasyon kodu üretme, kopyalama, aktif/pasif yapma ve silme
/// - Geliştirici rolü atama/kaldırma güvenlik gereği yalnızca PC panelinde kalır.
class DeveloperPanelScreen extends StatefulWidget {
  const DeveloperPanelScreen({
    super.key,
    required this.authController,
    this.service,
  });

  final AuthController authController;
  final DeveloperPanelService? service;

  @override
  State<DeveloperPanelScreen> createState() => _DeveloperPanelScreenState();
}

class _DeveloperPanelScreenState extends State<DeveloperPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final DeveloperPanelService _service;
  late final bool _ownsService;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _maxUsesController =
      TextEditingController(text: '5');
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _articleTopicController = TextEditingController();
  final TextEditingController _draftTitleController = TextEditingController();
  final TextEditingController _draftContentController = TextEditingController();

  List<DevEntitlementUser> _users = const <DevEntitlementUser>[];
  List<DevAccessCode> _codes = const <DevAccessCode>[];
  List<DevArticleSummary> _articles = const <DevArticleSummary>[];
  List<DevMissingWordReport> _missingWords = const <DevMissingWordReport>[];
  String _selectedLevel = 'B1';
  String _selectedVoice = 'Kore';
  String _articleSortMode = 'date_desc';
  bool _onlyMissingArticles = false;
  DevGeneratedArticle? _draftArticle;
  bool _isGeneratingArticle = false;
  int _articleGenElapsedSec = 0;
  Timer? _articleGenTimer;
  bool _isGeneratingAudio = false;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Makaleler sekmesi açılır/kapanır bölüm durumları (yığın önleme)
  bool _isPublishSectionExpanded = false;
  bool _isPublishedSectionExpanded = false;
  bool _isDraftMeaningsExpanded = false;
  bool _isDraftSentencesExpanded = false;
  bool _isDraftRelationsExpanded = false;

  static const List<String> _levels = <String>[
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  ];
  static const List<String> _voices = <String>[
    'Kore',
    'Puck',
    'Aoede',
    'Charon',
  ];

  final TextEditingController _manualTitleController = TextEditingController();
  final TextEditingController _manualAuthorController = TextEditingController();
  final TextEditingController _manualContentController = TextEditingController();
  bool _isManualInputMode = false;

  // Tek Tıkla Kaynaktan Çek & Yayınla Durumu
  final TextEditingController _quickPublishTopicController = TextEditingController();
  String _quickPublishLevel = 'B1';
  String _quickPublishVoice = 'Kore';
  bool _isQuickPublishing = false;
  int _quickPublishStep = 0;
  String _quickPublishStepMessage = '';
  int _quickPublishElapsedSec = 0;
  Timer? _quickPublishTimer;
  DevQuickPublishResult? _lastQuickPublishResult;
  bool _isQuickPublishSectionExpanded = true;

  // Otomatik Günlük Yayın Planlayıcı Durumu
  DevScheduleConfig? _scheduleConfig;
  bool _isScheduleSectionExpanded = true;
  bool _isScheduleEnabled = true;
  int _selectedPublishHour = 9;
  bool _isSavingSchedule = false;
  bool _isTestingSchedule = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _ownsService = widget.service == null;
    _service = widget.service ?? DeveloperPanelService();
    _loadAll();
  }

  @override
  void dispose() {
    _quickPublishTimer?.cancel();
    _articleGenTimer?.cancel();
    _tabController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _maxUsesController.dispose();
    _noteController.dispose();
    _articleTopicController.dispose();
    _quickPublishTopicController.dispose();
    _manualTitleController.dispose();
    _manualAuthorController.dispose();
    _manualContentController.dispose();
    _draftTitleController.dispose();
    _draftContentController.dispose();
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  Future<String?> _requireToken() async {
    final token = await widget.authController.getIdToken();
    if (token == null || token.trim().isEmpty) {
      _showSnack(
        context.l10n.t(
          'Oturum doğrulanamadı. Lütfen tekrar giriş yapın.',
          'Could not verify session. Please sign in again.',
        ),
        isError: true,
      );
      return null;
    }
    return token;
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = await widget.authController.getIdToken();
      if (token == null || token.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = context.l10n.t(
            'Geliştirici doğrulaması için oturum anahtarı alınamadı.',
            'Could not retrieve session token for developer verification.',
          );
        });
        return;
      }

      final results = await Future.wait<Object?>(<Future<Object?>>[
        _service.fetchUsers(token),
        _service.fetchCodes(token),
        _service
            .fetchArticles(token)
            .catchError((_) => const <DevArticleSummary>[]),
        _service
            .fetchScheduleConfig(token)
            .catchError((_) => null),
        _service
            .fetchMissingWords(token)
            .catchError((_) => const <DevMissingWordReport>[]),
      ]);
      if (!mounted) return;
      final sched = results[3] as DevScheduleConfig?;
      setState(() {
        _users = results[0] as List<DevEntitlementUser>;
        _codes = results[1] as List<DevAccessCode>;
        _articles = results[2] as List<DevArticleSummary>;
        _missingWords = results[4] as List<DevMissingWordReport>;
        if (sched != null) {
          _scheduleConfig = sched;
          _isScheduleEnabled = sched.isEnabled;
          _selectedPublishHour = sched.publishHour;
        }
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colorScheme.error : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _handleGrantPremium() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!email.contains('@') || email.length < 5) {
      _showSnack(
        context.l10n.t(
          'Geçerli bir Gmail / e-posta adresi girin.',
          'Enter a valid email address.',
        ),
        isError: true,
      );
      return;
    }
    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.grantPremium(token, email);
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        _emailController.clear();
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleGrantSpecialThemesFromInput() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!email.contains('@') || email.length < 5) {
      _showSnack(
        context.l10n.t(
          'Geçerli bir Gmail / e-posta adresi girin.',
          'Enter a valid email address.',
        ),
        isError: true,
      );
      return;
    }
    await _handleSetSpecialThemes(email, enabled: true, clearInput: true);
  }

  Future<void> _handleSetSpecialThemes(
    String email, {
    required bool enabled,
    bool clearInput = false,
  }) async {
    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.setSpecialThemes(
        token,
        email,
        enabled: enabled,
      );
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        if (clearInput) _emailController.clear();
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleRevokePremium(DevEntitlementUser user) async {
    final s = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('Premium Yetkisini Kaldır', 'Revoke Premium')),
        content: Text(
          s.t(
            '${user.email} hesabının Premium yetkisi kaldırılsın mı?',
            'Revoke Premium membership from ${user.email}?',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.t('Kaldır', 'Revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.revokePremium(token, user.email);
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _generateRandomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    final suffix = List<String>.generate(
      6,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    _codeController.text = 'LINE-$suffix';
  }

  Future<void> _handleCreateCode() async {
    final code = _codeController.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9_-]'), '');
    if (code.length < 4) {
      _showSnack(
        context.l10n.t(
          'Kod en az 4 karakter olmalıdır.',
          'Code must be at least 4 characters.',
        ),
        isError: true,
      );
      return;
    }
    final maxUses = int.tryParse(_maxUsesController.text.trim()) ?? 1;
    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.createCode(
        token,
        code: code,
        maxUses: maxUses.clamp(1, 100000),
        note: _noteController.text.trim(),
      );
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        _codeController.clear();
        _noteController.clear();
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleToggleCode(DevAccessCode item, bool nextActive) async {
    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.toggleCodeActive(
        token,
        code: item.code,
        isActive: nextActive,
      );
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleDeleteCode(DevAccessCode item) async {
    final s = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('Kodu Sil', 'Delete Code')),
        content: Text(
          s.t(
            '${item.code} aktivasyon kodu silinsin mi?',
            'Delete activation code ${item.code}?',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.deleteCode(token, item.code);
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.t('Geliştirici Paneli', 'Developer Panel')),
          actions: <Widget>[
            IconButton(
              onPressed: _isLoading ? null : _loadAll,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: s.t('Yenile', 'Refresh'),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: <Tab>[
              Tab(
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                text: s.t('Premium', 'Premium'),
              ),
              Tab(
                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                text: s.t('Kodlar', 'Codes'),
              ),
              Tab(
                icon: const Icon(Icons.auto_stories_outlined, size: 18),
                text: s.t('Makaleler', 'Articles'),
              ),
              Tab(
                icon: const Icon(Icons.flag_outlined, size: 18),
                text: s.t('Eksik Kelimeler', 'Missing'),
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.shield_outlined,
                            size: 44,
                            color: colorScheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _loadAll,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(s.retry),
                          ),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: <Widget>[
                      _buildUsersTab(theme, colorScheme, s),
                      _buildCodesTab(theme, colorScheme, s),
                      _buildArticlesTab(theme, colorScheme, s),
                      _buildMissingWordsTab(theme, colorScheme, s),
                    ],
                  ),
      ),
    );
  }

  Widget _buildMissingWordsTab(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    if (_missingWords.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.t(
              'Henüz kullanıcılar tarafından bildirilmiş eksik kelime yok.',
              'No missing words reported yet.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _missingWords.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _missingWords[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(120),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.flag_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.word,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      s.t(
                        '${item.reportCount} bildirim',
                        '${item.reportCount} reports',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        final token = await _requireToken();
                        if (token == null) return;
                        setState(() => _isSubmitting = true);
                        final res = await _service.deleteMissingWord(
                          token,
                          item.word,
                        );
                        if (!mounted) return;
                        setState(() {
                          _isSubmitting = false;
                          if (res.ok) {
                            _missingWords = _missingWords
                                .where((w) => w.word != item.word)
                                .toList(growable: false);
                          }
                        });
                        _showSnack(res.message, isError: !res.ok);
                      },
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
                tooltip: s.t('Listeden Kaldır', 'Remove'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsersTab(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  s.t('Gmail\'e Premium Üye Ver', 'Grant Premium by Email'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.t(
                    'E-posta adresini yazarak anında sınırsız çeviri ve reklamsız Premium yetkisi tanımlayın.',
                    'Enter an email address to grant unlimited translations and ad-free Premium access instantly.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('dev_panel_email_field'),
                  controller: _emailController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'kullanici@gmail.com',
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'dev_panel_grant_premium_btn',
                        ),
                        onPressed: _isSubmitting ? null : _handleGrantPremium,
                        icon: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 18,
                        ),
                        label: Text(s.t('Premium Ver', 'Grant Premium')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const ValueKey<String>(
                          'dev_panel_grant_special_themes_btn',
                        ),
                        onPressed: _isSubmitting
                            ? null
                            : _handleGrantSpecialThemesFromInput,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text(s.t('Özel Tema Ver', 'Special Themes')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${s.t('Yetkili Hesaplar', 'Active Accounts')} (${_users.length})',
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (_users.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                s.t('Henüz yetkili kullanıcı yok.', 'No active accounts yet.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ..._users.map((user) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: user.isDeveloper
                      ? colorScheme.primaryContainer
                      : colorScheme.secondaryContainer,
                  child: Icon(
                    user.isDeveloper
                        ? Icons.code_rounded
                        : Icons.workspace_premium_rounded,
                    size: 18,
                    color: user.isDeveloper
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSecondaryContainer,
                  ),
                ),
                title: Text(
                  user.email,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  () {
                    final parts = <String>[];
                    if (user.isDeveloper) {
                      parts.add(s.t('Geliştirici', 'Developer'));
                    } else if (user.isUnlimited) {
                      parts.add(
                        user.codeUsed != null && user.codeUsed!.isNotEmpty
                            ? '${s.t('Premium Üye', 'Premium Member')} (${user.codeUsed})'
                            : s.t('Premium Üye', 'Premium Member'),
                      );
                    } else {
                      parts.add(s.t('Standart Üye', 'Standard Member'));
                    }
                    if (user.authProviderLabel != null) {
                      parts.add(user.authProviderLabel!);
                    }
                    if (user.hasSpecialThemes && !user.isDeveloper) {
                      parts.add('✨ ${s.t('Özel Tema', 'Special Themes')}');
                    }
                    return parts.join(' • ');
                  }(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: user.isDeveloper
                    ? Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => _handleSetSpecialThemes(
                                      user.email,
                                      enabled: !user.hasSpecialThemes,
                                    ),
                            icon: Icon(
                              user.hasSpecialThemes
                                  ? Icons.auto_awesome_rounded
                                  : Icons.auto_awesome_outlined,
                              color: user.hasSpecialThemes
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            tooltip: user.hasSpecialThemes
                                ? s.t('Özel Temayı Kapat', 'Disable Special Themes')
                                : s.t('Özel Tema Aç', 'Enable Special Themes'),
                          ),
                          if (user.isUnlimited)
                            IconButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _handleRevokePremium(user),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: colorScheme.error,
                              ),
                              tooltip: s.t(
                                'Premium Yetkisini Kaldır',
                                'Revoke Premium',
                              ),
                            )
                          else
                            IconButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () async {
                                      final token = await _requireToken();
                                      if (token == null) return;
                                      setState(() => _isSubmitting = true);
                                      try {
                                        final res = await _service.grantPremium(
                                          token,
                                          user.email,
                                        );
                                        _showSnack(
                                          res.message,
                                          isError: !res.ok,
                                        );
                                        if (res.ok) await _loadAll();
                                      } catch (e) {
                                        _showSnack(
                                          e.toString(),
                                          isError: true,
                                        );
                                      } finally {
                                        if (mounted) {
                                          setState(() => _isSubmitting = false);
                                        }
                                      }
                                    },
                              icon: Icon(
                                Icons.workspace_premium_outlined,
                                color: colorScheme.primary,
                              ),
                              tooltip: s.t('Premium Üye Ver', 'Grant Premium'),
                            ),
                        ],
                      ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCodesTab(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  s.t('Yeni Aktivasyon Kodu Üret', 'Create Activation Code'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>('dev_panel_code_field'),
                        controller: _codeController,
                        enabled: !_isSubmitting,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText: 'LINE-XXXXXX',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const ValueKey<String>('dev_panel_random_code_btn'),
                      onPressed: _isSubmitting ? null : _generateRandomCode,
                      icon: const Icon(Icons.casino_outlined, size: 18),
                      label: Text(s.t('Üret', 'Random')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _maxUsesController,
                        enabled: !_isSubmitting,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: s.t('Kullanım', 'Max uses'),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _noteController,
                        enabled: !_isSubmitting,
                        decoration: InputDecoration(
                          labelText: s.t('Not (isteğe bağlı)', 'Note (optional)'),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey<String>('dev_panel_create_code_btn'),
                  onPressed: _isSubmitting ? null : _handleCreateCode,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(s.t('Aktivasyon Kodu Oluştur', 'Create Code')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${s.t('Mevcut Kodlar', 'Existing Codes')} (${_codes.length})',
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (_codes.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                s.t('Henüz aktivasyon kodu yok.', 'No activation codes yet.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ..._codes.map((item) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                item.code,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: item.isActive
                                      ? colorScheme.primaryContainer
                                      : colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${item.usedCount}/${item.maxUses}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: item.isActive
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item.note != null && item.note!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.note!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: item.code));
                        _showSnack(
                          s.t('${item.code} kopyalandı.', 'Copied ${item.code}.'),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: s.t('Kopyala', 'Copy'),
                    ),
                    Switch(
                      value: item.isActive,
                      onChanged: _isSubmitting
                          ? null
                          : (val) => _handleToggleCode(item, val),
                    ),
                    IconButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => _handleDeleteCode(item),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: colorScheme.error,
                      ),
                      tooltip: s.delete,
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _handleGenerateArticle() async {
    final token = await _requireToken();
    if (token == null) return;

    _articleGenTimer?.cancel();
    setState(() {
      _isGeneratingArticle = true;
      _articleGenElapsedSec = 0;
    });
    _articleGenTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isGeneratingArticle) return;
      setState(() => _articleGenElapsedSec += 1);
    });
    try {
      final generated = await _service.generateArticle(
        token,
        level: _selectedLevel,
        topic: _articleTopicController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _draftArticle = generated;
        _draftTitleController.text = generated.title;
        _draftContentController.text = generated.content;
        _isDraftMeaningsExpanded = false;
        _isDraftSentencesExpanded = false;
        _isDraftRelationsExpanded = false;
      });
      _showSnack(
        context.l10n.t(
          'Makale hazır! İstersen Podcast AI sesi ekleyip anında yayınlayabilirsin.',
          'Article generated! You can add Podcast AI audio and publish instantly.',
        ),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      _articleGenTimer?.cancel();
      _articleGenTimer = null;
      if (mounted) {
        setState(() {
          _isGeneratingArticle = false;
          _articleGenElapsedSec = 0;
        });
      }
    }
  }

  Future<void> _handleGenerateAudio() async {
    final draft = _draftArticle;
    if (draft == null) return;
    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isGeneratingAudio = true);
    try {
      final result = await _service.generateArticleAudio(
        token,
        id: draft.id,
        title: _draftTitleController.text.trim().isNotEmpty
            ? _draftTitleController.text.trim()
            : draft.title,
        content: _draftContentController.text.trim().isNotEmpty
            ? _draftContentController.text.trim()
            : draft.content,
        voice: _selectedVoice,
      );
      if (!mounted) return;
      setState(() {
        _draftArticle = _draftArticle?.copyWith(
          audioUrl: result.audioUrl,
          audioVoice: result.audioVoice,
          audioDurationSec: result.audioDurationSec,
          audioSegments: result.audioSegments,
        );
      });
      _showSnack(result.message);
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isGeneratingAudio = false);
    }
  }

  void _handlePrepareManualArticle() {
    final title = _manualTitleController.text.trim();
    final author = _manualAuthorController.text.trim();
    final content = _manualContentController.text.trim();

    if (title.isEmpty) {
      _showSnack(context.l10n.t('Lütfen makale başlığı girin.', 'Please enter an article title.'), isError: true);
      return;
    }
    if (content.length < 50) {
      _showSnack(context.l10n.t('Makale metni en az 50 karakter olmalıdır.', 'Article text must be at least 50 chars.'), isError: true);
      return;
    }

    final wordCount = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final readingMin = (wordCount / 140).ceil().clamp(1, 30);
    final readingTime = readingMin <= 1 ? '1 - 2 dk' : '$readingMin - ${readingMin + 1} dk';
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final id = '${_selectedLevel.toLowerCase()}-$slug';

    final lines = content.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final desc = lines.isNotEmpty ? (lines.first.length > 120 ? '${lines.first.substring(0, 117)}...' : lines.first) : title;

    final manualDraft = DevGeneratedArticle(
      id: id,
      level: _selectedLevel,
      title: title,
      content: content,
      readingTime: readingTime,
      description: desc,
      author: author.isNotEmpty ? author : 'Line Reader',
      category: 'General',
      wordMeanings: const <String, dynamic>{},
      sentenceTranslations: const <String, dynamic>{},
      wordRelations: const <String, dynamic>{},
    );

    setState(() {
      _draftArticle = manualDraft;
      _draftTitleController.text = title;
      _draftContentController.text = content;
    });

    _showSnack(context.l10n.t('Manuel makale taslağı hazırlandı! Aşağıdan inceleyip yayınlayabilirsiniz.', 'Manual draft ready! Review below and publish.'));
  }

  Future<void> _handlePublishArticle() async {
    final draft = _draftArticle;
    if (draft == null) return;
    final token = await _requireToken();
    if (token == null) return;

    final updatedDraft = draft.copyWith(
      title: _draftTitleController.text.trim().isNotEmpty
          ? _draftTitleController.text.trim()
          : draft.title,
      content: _draftContentController.text.trim().isNotEmpty
          ? _draftContentController.text.trim()
          : draft.content,
    );

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.publishArticle(token, updatedDraft);
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        setState(() {
          _draftArticle = null;
          _articleTopicController.clear();
          _draftTitleController.clear();
          _draftContentController.clear();
          _isDraftMeaningsExpanded = false;
          _isDraftSentencesExpanded = false;
          _isDraftRelationsExpanded = false;
          _isPublishedSectionExpanded = true;
        });
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleToggleArticleHidden(DevArticleSummary item) async {
    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.toggleArticleHidden(
        token,
        id: item.id,
        isHidden: !item.isHidden,
      );
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleDeleteArticle(DevArticleSummary item) async {
    final s = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('Makaleyi Sil', 'Delete Article')),
        content: Text(
          s.t(
            '"${item.title}" makalesi kalıcı olarak silinsin mi?',
            'Permanently delete "${item.title}"?',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final token = await _requireToken();
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.deleteArticle(token, item.id);
      _showSnack(result.message, isError: !result.ok);
      if (result.ok) {
        await _loadAll();
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleQuickPublish() async {
    final token = await _requireToken();
    if (token == null) return;

    setState(() {
      _isQuickPublishing = true;
      _quickPublishStep = 1;
      _quickPublishStepMessage = 'İlgi çekici kaynaklar taranıyor...';
      _quickPublishElapsedSec = 0;
      _lastQuickPublishResult = null;
    });

    _quickPublishTimer?.cancel();
    _quickPublishTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _quickPublishElapsedSec++;
        if (_quickPublishStep == 1 && _quickPublishElapsedSec >= 3) {
          _quickPublishStep = 2;
          _quickPublishStepMessage = 'Makale bulundu! CEFR analizi ve kelime/cümle çevirileri hazırlanıyor...';
        } else if (_quickPublishStep == 2 && _quickPublishElapsedSec >= 8) {
          _quickPublishStep = 3;
          _quickPublishStepMessage = 'Podcast AI stüdyo sesi üretiliyor ve zaman senkronu yapılıyor...';
        } else if (_quickPublishStep == 3 && _quickPublishElapsedSec >= 16) {
          _quickPublishStep = 4;
          _quickPublishStepMessage = 'D1 veritabanı ve GitHub akışına anında yükleniyor...';
        }
      });
    });

    try {
      final res = await _service.quickPublishArticle(
        token,
        level: _quickPublishLevel,
        topic: _quickPublishTopicController.text.trim(),
        voice: _quickPublishVoice,
      );

      _quickPublishTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isQuickPublishing = false;
        _quickPublishStep = 5;
        _quickPublishStepMessage = res.message;
        _lastQuickPublishResult = res;
      });

      _showSnack(res.message);
      await _loadAll();
    } catch (e) {
      _quickPublishTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isQuickPublishing = false;
        _quickPublishStep = 0;
      });
      _showSnack('Tek tıkla yayınlama başarısız: $e', isError: true);
    }
  }

  Future<void> _handleSaveScheduleConfig() async {
    final token = await _requireToken();
    if (token == null) return;
    setState(() => _isSavingSchedule = true);
    try {
      final res = await _service.updateScheduleConfig(
        token,
        isEnabled: _isScheduleEnabled,
        publishHour: _selectedPublishHour,
      );
      _showSnack(res.message, isError: !res.ok);
      await _loadAll();
    } catch (e) {
      _showSnack('Plan kaydedilemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingSchedule = false);
    }
  }

  Future<void> _handleTestScheduleRunNow() async {
    final token = await _requireToken();
    if (token == null) return;
    setState(() => _isTestingSchedule = true);
    try {
      final res = await _service.triggerScheduleRunNow(token, mode: 'full_pipeline');
      _showSnack(res.message, isError: !res.ok);
      await _loadAll();
    } catch (e) {
      _showSnack('Test çalışması başarısız: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isTestingSchedule = false);
    }
  }

  static const Map<String, int> _levelOrder = <String, int>{
    'A1': 1,
    'A2': 2,
    'B1': 3,
    'B2': 4,
    'C1': 5,
    'C2': 6,
  };

  List<DevArticleSummary> _filteredSortedArticles() {
    final list = _onlyMissingArticles
        ? _articles.where((a) => a.hasMissingFields).toList()
        : List<DevArticleSummary>.from(_articles);

    list.sort((a, b) {
      if (_articleSortMode == 'date_desc' || _articleSortMode == 'date_asc') {
        final ta = a.publishedAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.publishedAt?.millisecondsSinceEpoch ?? 0;
        if (ta != tb) {
          return _articleSortMode == 'date_desc'
              ? tb.compareTo(ta)
              : ta.compareTo(tb);
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      if (_articleSortMode == 'level_asc') {
        final la = _levelOrder[a.level] ?? 99;
        final lb = _levelOrder[b.level] ?? 99;
        if (la != lb) return la.compareTo(lb);
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return list;
  }

  String? _formatPublishedDate(DateTime? dt) {
    if (dt == null) return null;
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${dt.year} $hh:$min';
  }

  Widget _buildSectionToggleButton({
    required Key key,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isExpanded
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isExpanded
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArticleGenProgressBox(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final elapsed = _articleGenElapsedSec;
    const expectedSec = 10;
    final progress = (elapsed / expectedSec).clamp(0.08, 0.92);
    final remaining = expectedSec - elapsed;
    final stageLabel = elapsed < 4
        ? s.t('Makale yazılıyor...', 'Writing article...')
        : elapsed < 8
            ? s.t(
                'Kelime anlamları ve çeviriler hazırlanıyor...',
                'Preparing meanings and translations...',
              )
            : elapsed <= 14
                ? s.t('Son kontroller yapılıyor...', 'Finalizing...')
                : s.t(
                    'Yedek model deneniyor, lütfen bekleyin...',
                    'Trying fallback model, please wait...',
                  );
    final timingLabel = remaining > 0
        ? s.t(
            '$elapsed sn geçti • Tahmini ~$remaining sn kaldı',
            '${elapsed}s elapsed • ~${remaining}s left',
          )
        : s.t(
            '$elapsed sn geçti • Neredeyse hazır',
            '${elapsed}s elapsed • Almost done',
          );

    return Container(
      key: const ValueKey<String>('dev_panel_article_gen_progress'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withAlpha(75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  stageLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$elapsed sn',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timingLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableDraftFeatureBox({
    required Key key,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget Function() expandedContentBuilder,
  }) {
    final hasItems = count > 0;
    return Material(
      color: colorScheme.surface.withAlpha(210),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpanded
              ? colorScheme.primary
              : colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: key,
            onTap: hasItems ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    icon,
                    size: 17,
                    color: hasItems
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$title ($count)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: hasItems
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (hasItems)
                    Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    )
                  else
                    Text(
                      'Yok',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isExpanded && hasItems) ...<Widget>[
            Divider(height: 1, color: colorScheme.outlineVariant),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 170),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: expandedContentBuilder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickPublishSection(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final busy = _isSubmitting || _isGeneratingArticle || _isGeneratingAudio || _isQuickPublishing;
    final lastRes = _lastQuickPublishResult;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildSectionToggleButton(
          key: const ValueKey<String>('dev_panel_toggle_quick_publish_btn'),
          theme: theme,
          colorScheme: colorScheme,
          icon: Icons.bolt_rounded,
          title: s.t('⚡ Tek Tıkla Makale Çek & Yayınla', '⚡ One-Click Fetch & Publish'),
          subtitle: _isQuickPublishing
              ? s.t('İşlem sürüyor (${_quickPublishElapsedSec} sn)...', 'Processing (${_quickPublishElapsedSec}s)...')
              : s.t('Seviyeyi seç; ilgi çekici yazıyı bulsun, seslendirsin ve anında canlıya alsın', 'Select level to find, voice, and publish instantly'),
          isExpanded: _isQuickPublishSectionExpanded,
          onTap: () => setState(
            () => _isQuickPublishSectionExpanded = !_isQuickPublishSectionExpanded,
          ),
        ),
        if (_isQuickPublishSectionExpanded) ...<Widget>[
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    s.t('Hedef CEFR Seviyesi Seçin *', 'Select Target CEFR Level *'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.t(
                      'Sistem seçilen seviyeye uygun merak uyandırıcı, ilgi çekici bir konuyu tarar, kelime ve cümle anlamlarını çıkarır ve stüdyo Podcast AI sesini oluşturur.',
                      'The system picks a captivating topic for this level, analyzes vocabulary, and generates studio Podcast AI audio.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _levels.map((lvl) {
                      return ChoiceChip(
                        label: Text(lvl, style: const TextStyle(fontWeight: FontWeight.w700)),
                        selected: _quickPublishLevel == lvl,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => _quickPublishLevel = lvl),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _quickPublishTopicController,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: s.t(
                        'Odak Konusu (İsteğe bağlı — boşsa sistem popüler konulardan seçer)',
                        'Focus Topic (Optional — system picks if blank)',
                      ),
                      hintText: s.t(
                        'Örn: Nörobilim, Derin Uzay, İnsan Psikolojisi, Gizemler...',
                        'e.g. Neuroscience, Deep Space, Human Psychology, Mysteries...',
                      ),
                      isDense: true,
                      prefixIcon: const Icon(Icons.explore_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Text(
                        s.t('Podcast Sesi:', 'Podcast Voice:'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          children: _voices.map((v) {
                            return ChoiceChip(
                              label: Text(v),
                              selected: _quickPublishVoice == v,
                              onSelected: busy
                                  ? null
                                  : (_) => setState(() => _quickPublishVoice = v),
                            );
                          }).toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy ? null : _handleQuickPublish,
                    icon: _isQuickPublishing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.bolt_rounded, size: 20),
                    label: Text(
                      _isQuickPublishing
                          ? s.t('Makale Çekiliyor ve Yayınlanıyor (${_quickPublishElapsedSec} sn)...', 'Publishing (${_quickPublishElapsedSec}s)...')
                          : s.t('Makaleyi Bul, Seslendir ve Yayınla', 'Find, Voice & Publish Article'),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (_isQuickPublishing || lastRes != null || _quickPublishStep > 0) ...<Widget>[
                    const SizedBox(height: 16),
                    _buildQuickPublishLiveCard(theme, colorScheme, s),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildQuickPublishLiveCard(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final lastRes = _lastQuickPublishResult;
    final isDone = _quickPublishStep >= 5;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDone
            ? colorScheme.primaryContainer.withOpacity(0.18)
            : colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? colorScheme.primary.withOpacity(0.4)
              : colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isDone ? Icons.check_circle_rounded : Icons.sync_rounded,
                size: 20,
                color: isDone ? Colors.green : colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isDone
                      ? s.t('Makale Başarıyla Yayına Alındı!', 'Article Successfully Published!')
                      : s.t('Canlı Yayınlama Durumu', 'Live Publishing Status'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDone ? Colors.green.withOpacity(0.15) : colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.timer_outlined, size: 14, color: isDone ? Colors.green : colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      isDone
                          ? '${lastRes?.totalSec ?? _quickPublishElapsedSec} sn'
                          : '$_quickPublishElapsedSec sn',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDone ? Colors.green : colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildLiveStepRow(
            stepNumber: 1,
            label: s.t('1. İlgi çekici kaynaklar ve konular taranıyor...', '1. Curating engaging sources & topics...'),
            currentStep: _quickPublishStep,
            colorScheme: colorScheme,
            theme: theme,
          ),
          const SizedBox(height: 8),
          _buildLiveStepRow(
            stepNumber: 2,
            label: lastRes?.article != null
                ? s.t(
                    '2. Makale bulundu: "${lastRes!.article!.title}" (${lastRes.article!.level})',
                    '2. Article found: "${lastRes!.article!.title}" (${lastRes.article!.level})',
                  )
                : s.t(
                    '2. Makale bulundu ve CEFR kelime/cümle analizi yapılıyor...',
                    '2. Article found & analyzing vocabulary and CEFR level...',
                  ),
            currentStep: _quickPublishStep,
            colorScheme: colorScheme,
            theme: theme,
          ),
          const SizedBox(height: 8),
          _buildLiveStepRow(
            stepNumber: 3,
            label: s.t(
              '3. Podcast AI stüdyo sesi üretiliyor ve zaman senkronu yapılıyor...',
              '3. Producing studio Podcast AI audio & word timing...',
            ),
            currentStep: _quickPublishStep,
            colorScheme: colorScheme,
            theme: theme,
          ),
          const SizedBox(height: 8),
          _buildLiveStepRow(
            stepNumber: 4,
            label: s.t(
              '4. D1 veritabanı ve GitHub akışına anında yükleniyor...',
              '4. Instant upload to D1 database and GitHub feed...',
            ),
            currentStep: _quickPublishStep,
            colorScheme: colorScheme,
            theme: theme,
          ),
          if (isDone && lastRes != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '🎉 ${lastRes.message}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '⏱️ Metin & Analiz: ${(lastRes.articleMs / 1000).toStringAsFixed(1)}s  |  🎙️ Podcast Sesi: ${(lastRes.audioMs / 1000).toStringAsFixed(1)}s  |  🚀 Canlıya Alma: ${(lastRes.publishMs / 1000).toStringAsFixed(1)}s',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveStepRow({
    required int stepNumber,
    required String label,
    required int currentStep,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    final bool isCompleted = currentStep > stepNumber || currentStep >= 5;
    final bool isActive = currentStep == stepNumber && currentStep < 5;

    Widget iconWidget;
    Color textColor;
    if (isCompleted) {
      iconWidget = const Icon(Icons.check_circle_rounded, size: 18, color: Colors.green);
      textColor = colorScheme.onSurface;
    } else if (isActive) {
      iconWidget = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
      );
      textColor = colorScheme.primary;
    } else {
      iconWidget = Icon(Icons.radio_button_unchecked_rounded, size: 18, color: colorScheme.outlineVariant);
      textColor = colorScheme.onSurfaceVariant.withOpacity(0.6);
    }

    return Row(
      children: <Widget>[
        iconWidget,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleConfigSection(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final cfg = _scheduleConfig;
    final busy = _isSubmitting || _isSavingSchedule || _isTestingSchedule;
    final preHour = (_selectedPublishHour - 1 + 24) % 24;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildSectionToggleButton(
          key: const ValueKey<String>('dev_panel_toggle_schedule_section_btn'),
          theme: theme,
          colorScheme: colorScheme,
          icon: Icons.schedule_rounded,
          title: s.t('📅 Otomatik Günlük Yayın Planlayıcı', '📅 Automated Scheduled Publisher'),
          subtitle: _isScheduleEnabled
              ? s.t(
                  'Her gün saat ${_selectedPublishHour.toString().padLeft(2, '0')}:00\'da A1-C2 tüm 6 seviye yayınlanır',
                  'Every day at ${_selectedPublishHour.toString().padLeft(2, '0')}:00 all 6 levels go live',
                )
              : s.t('Otomatik yayınlama devre dışı', 'Scheduled publishing disabled'),
          isExpanded: _isScheduleSectionExpanded,
          onTap: () => setState(
            () => _isScheduleSectionExpanded = !_isScheduleSectionExpanded,
          ),
        ),
        if (_isScheduleSectionExpanded) ...<Widget>[
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      s.t('Otomatik Günlük Yayınlama', 'Automated Daily Publishing'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      s.t(
                        'Açık olduğunda her gün belirlediğin saatte tüm seviyeler (A1, A2, B1, B2, C1, C2) için 6 yeni makale otomatik yayınlanır.',
                        'When enabled, 6 fresh articles (A1-C2) are published daily at your specified hour.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    value: _isScheduleEnabled,
                    onChanged: busy ? null : (val) => setState(() => _isScheduleEnabled = val),
                  ),
                  const Divider(height: 24),
                  Text(
                    s.t('Yayın Saati Seçin (Türkiye Saati / UTC+3) *', 'Select Publish Hour (Turkey Time) *'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <int>[6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 21].map((h) {
                      final label = '${h.toString().padLeft(2, '0')}:00';
                      return ChoiceChip(
                        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        selected: _selectedPublishHour == h,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => _selectedPublishHour = h),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.bolt_rounded, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              s.t('İki Aşamalı Kusursuz Çalışma Prensibi', 'Two-Stage Instant Publishing Principle'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.t(
                            '1. Hazırlık (Saat ${preHour.toString().padLeft(2, '0')}:15): Sistem arka planda A1\'den C2\'ye 6 seviyenin tamamı için ilgi çekici makaleleri, kelime analizlerini ve Podcast AI seslerini hazırlar, gizli olarak yükler.\n'
                            '2. Canlıya Alma (Saat ${_selectedPublishHour.toString().padLeft(2, '0')}:00): Hedef saat geldiğinde hiçbir bekleme veya gecikme olmaksızın tüm makaleler tek saniyede yayına açılır.',
                            '1. Pre-bake (${preHour.toString().padLeft(2, '0')}:15): System prepares all 6 CEFR level articles with audio and keeps them hidden.\n'
                            '2. Go-Live (${_selectedPublishHour.toString().padLeft(2, '0')}:00): Instant zero-delay unhiding at the exact target hour.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        if (cfg?.lastPreparedDate != null || cfg?.lastPublishedDate != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            '📅 Son Hazırlık: ${cfg?.lastPreparedDate ?? "-"}  |  🚀 Son Yayın: ${cfg?.lastPublishedDate ?? "-"}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : _handleSaveScheduleConfig,
                          icon: _isSavingSchedule
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(s.t('Planı Kaydet', 'Save Schedule')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : _handleTestScheduleRunNow,
                          icon: _isTestingSchedule
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.play_circle_outline_rounded, size: 18),
                          label: Text(s.t('Şimdi Test Et (6 Seviye)', 'Test Run (6 Levels)')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildArticlesTab(
    ThemeData theme,
    ColorScheme colorScheme,
    AppStrings s,
  ) {
    final busy = _isSubmitting || _isGeneratingArticle || _isGeneratingAudio || _isQuickPublishing;
    final draft = _draftArticle;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      children: <Widget>[
        // 1. Yeni Bölüm: Tek Tıkla Kaynaktan Çek & Canlı Yayınla (Canlı Adım Takibi)
        _buildQuickPublishSection(theme, colorScheme, s),

        // 2. Yeni Bölüm: Otomatik Günlük Yayın Planlayıcı (A1-C2 İki Aşamalı Sistem)
        _buildScheduleConfigSection(theme, colorScheme, s),

        // 3. Açılır/Kapanır Bölüm: Detaylı Makale Yayınla (Gemini + Manuel Metin Taslağı)
        _buildSectionToggleButton(
          key: const ValueKey<String>('dev_panel_toggle_publish_section_btn'),
          theme: theme,
          colorScheme: colorScheme,
          icon: Icons.auto_awesome_rounded,
          title: s.t('Detaylı Makale / Taslak Yayınla', 'Detailed Article / Draft Publishing'),
          subtitle: draft != null
              ? s.t(
                  'Taslak hazır: ${draft.title}',
                  'Draft ready: ${draft.title}',
                )
              : s.t(
                  'Manuel metin gir veya özel parametrelerle taslak hazırla',
                  'Enter manual text or prepare custom draft',
                ),
          isExpanded: _isPublishSectionExpanded,
          onTap: () => setState(
            () => _isPublishSectionExpanded = !_isPublishSectionExpanded,
          ),
        ),
        if (_isPublishSectionExpanded) ...<Widget>[
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SegmentedButton<bool>(
                    segments: <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: false,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: Text(s.t('AI İle Üret', 'Generate with AI')),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: Text(s.t('Manuel Metin Gir', 'Manual Input')),
                      ),
                    ],
                    selected: <bool>{_isManualInputMode},
                    onSelectionChanged: busy
                        ? null
                        : (val) => setState(() => _isManualInputMode = val.first),
                  ),
                  const SizedBox(height: 14),
                  if (_isManualInputMode) ...<Widget>[
                    Text(
                      s.t('Gerçek / Manuel Makale Girişi', 'Manual Article Publishing'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.t(
                        'Başlık, yazar/kaynak ve doğrudan gerçek İngilizce makale metnini girin.',
                        'Enter title, author/source, and paste the authentic English text.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _levels.map((lvl) {
                        return ChoiceChip(
                          label: Text(lvl),
                          selected: _selectedLevel == lvl,
                          onSelected: busy
                              ? null
                              : (_) => setState(() => _selectedLevel = lvl),
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _manualTitleController,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: s.t('Makale Başlığı *', 'Article Title *'),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _manualAuthorController,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: s.t('Yazar / Kaynak (örn. The Conversation)', 'Author / Source'),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _manualContentController,
                      enabled: !busy,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: s.t('Gerçek Makale Metni *', 'Article Text *'),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy ? null : _handlePrepareManualArticle,
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: Text(s.t('Taslağı Hazırla ve İncele', 'Prepare & Review Draft')),
                    ),
                  ] else ...<Widget>[
                    Text(
                      s.t('Gemini ile Makale Üret', 'Generate Article with Gemini'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    s.t(
                      'Seviye seçip metin, kelime anlamları, çeviriler, eş/zıt anlamlar ve Podcast AI sesini üret.',
                      'Pick a level to generate text, meanings, translations, synonyms/antonyms, and Podcast AI audio.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _levels.map((lvl) {
                      return ChoiceChip(
                        label: Text(lvl),
                        selected: _selectedLevel == lvl,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => _selectedLevel = lvl),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey<String>('dev_panel_article_topic_field'),
                    controller: _articleTopicController,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: s.t(
                        'Konu (boş bırakırsan Gemini seçer)',
                        'Topic (optional — Gemini picks if blank)',
                      ),
                      hintText: 'e.g. Future of Space Travel',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey<String>('dev_panel_generate_article_btn'),
                    onPressed: busy ? null : _handleGenerateArticle,
                    icon: _isGeneratingArticle
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(
                      _isGeneratingArticle
                          ? s.t(
                              'Üretiliyor... ($_articleGenElapsedSec sn)',
                              'Generating... (${_articleGenElapsedSec}s)',
                            )
                          : s.t('Gemini ile Makale Üret', 'Generate with Gemini'),
                    ),
                  ),
                  if (_isGeneratingArticle) ...<Widget>[
                    const SizedBox(height: 10),
                    _buildArticleGenProgressBox(theme, colorScheme, s),
                  ],
                ],
                ],
              ),
            ),
          ),
          if (draft != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: colorScheme.primaryContainer.withAlpha(65),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Chip(
                          label: Text(
                            draft.level,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                s.t('Taslak Hazır', 'Draft Ready'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if ((draft.category != null &&
                                      draft.category!.isNotEmpty) ||
                                  (draft.author != null &&
                                      draft.author!.isNotEmpty))
                                Text(
                                  <String>[
                                    if (draft.category != null &&
                                        draft.category!.isNotEmpty)
                                      draft.category!,
                                    if (draft.author != null &&
                                        draft.author!.isNotEmpty)
                                      draft.author!,
                                  ].join(' • '),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => _draftArticle = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _draftTitleController,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: s.t('Başlık', 'Title'),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    if (draft.description != null &&
                        draft.description!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withAlpha(185),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Text(
                          draft.description!.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _draftContentController,
                      enabled: !busy,
                      maxLines: 6,
                      minLines: 4,
                      decoration: InputDecoration(
                        labelText: s.t('Metin', 'Content'),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Açılır/kapanır özellik kutucukları (küçük ekranda yığın olmaz!)
                    _buildExpandableDraftFeatureBox(
                      key: const ValueKey<String>(
                        'dev_panel_draft_toggle_meanings',
                      ),
                      theme: theme,
                      colorScheme: colorScheme,
                      icon: Icons.translate_rounded,
                      title: s.t('Kelime Anlamları', 'Word Meanings'),
                      count: draft.wordMeanings.length,
                      isExpanded: _isDraftMeaningsExpanded,
                      onToggle: () => setState(
                        () => _isDraftMeaningsExpanded =
                            !_isDraftMeaningsExpanded,
                      ),
                      expandedContentBuilder: () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: draft.wordMeanings.entries.map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${e.key}: ${e.value}',
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildExpandableDraftFeatureBox(
                      key: const ValueKey<String>(
                        'dev_panel_draft_toggle_sentences',
                      ),
                      theme: theme,
                      colorScheme: colorScheme,
                      icon: Icons.notes_rounded,
                      title: s.t('Cümle Çevirileri', 'Sentence Translations'),
                      count: draft.sentenceTranslations.length,
                      isExpanded: _isDraftSentencesExpanded,
                      onToggle: () => setState(
                        () => _isDraftSentencesExpanded =
                            !_isDraftSentencesExpanded,
                      ),
                      expandedContentBuilder: () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: draft.sentenceTranslations.entries.map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  e.key,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '→ ${e.value}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildExpandableDraftFeatureBox(
                      key: const ValueKey<String>(
                        'dev_panel_draft_toggle_relations',
                      ),
                      theme: theme,
                      colorScheme: colorScheme,
                      icon: Icons.compare_arrows_rounded,
                      title: s.t('Eş / Zıt Anlamlar', 'Synonyms & Antonyms'),
                      count: draft.wordRelations.length,
                      isExpanded: _isDraftRelationsExpanded,
                      onToggle: () => setState(
                        () => _isDraftRelationsExpanded =
                            !_isDraftRelationsExpanded,
                      ),
                      expandedContentBuilder: () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: draft.wordRelations.entries.map((e) {
                          final val = e.value;
                          String summary;
                          if (val is Map) {
                            final syns = (val['syn'] is List)
                                ? (val['syn'] as List).join(', ')
                                : '';
                            final ants = (val['ant'] is List)
                                ? (val['ant'] as List).join(', ')
                                : '';
                            summary = <String>[
                              if (syns.isNotEmpty) 'Eş: $syns',
                              if (ants.isNotEmpty) 'Zıt: $ants',
                            ].join(' • ');
                          } else {
                            summary = val.toString();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${e.key} → $summary',
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MiniStatBadge(
                      label: draft.hasAudio
                          ? '🎙 Podcast Hazır (${draft.audioDurationSec ?? 0} sn)'
                          : '🎙 Podcast sesi henüz üretilmedi',
                      highlighted: draft.hasAudio,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Text(
                          s.t('Podcast Sesi:', 'Voice:'),
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: _selectedVoice,
                          isDense: true,
                          onChanged: busy
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(() => _selectedVoice = val);
                                  }
                                },
                          items: _voices
                              .map(
                                (v) => DropdownMenuItem<String>(
                                  value: v,
                                  child: Text(v),
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          key: const ValueKey<String>(
                            'dev_panel_generate_audio_btn',
                          ),
                          onPressed: busy ? null : _handleGenerateAudio,
                          icon: _isGeneratingAudio
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.podcasts_rounded, size: 17),
                          label: Text(
                            _isGeneratingAudio
                                ? s.t('Ses Üretiliyor...', 'Generating...')
                                : s.t('Podcast Sesi Üret', 'Generate Audio'),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        s.t(
                          'Gizli olarak kaydet (kullanıcılar görmez)',
                          'Save as hidden',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      value: draft.isHidden,
                      onChanged: busy
                          ? null
                          : (val) => setState(
                                () => _draftArticle = draft.copyWith(
                                  isHidden: val,
                                ),
                              ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      key: const ValueKey<String>(
                        'dev_panel_publish_article_btn',
                      ),
                      onPressed: busy ? null : _handlePublishArticle,
                      icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                      label: Text(
                        draft.isHidden
                            ? s.t('Gizli Kaydet', 'Save Hidden')
                            : s.t('Anında Yayınla', 'Publish Instantly'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        // 2. Açılır/Kapanır Bölüm: Yayındaki Makaleler
        _buildSectionToggleButton(
          key: const ValueKey<String>(
            'dev_panel_toggle_published_section_btn',
          ),
          theme: theme,
          colorScheme: colorScheme,
          icon: Icons.library_books_outlined,
          title:
              '${s.t('Yayındaki Makaleler', 'Published Articles')} (${_articles.length})',
          subtitle: s.t(
            'Mevcut makaleleri listele, sırala, gizle veya sil',
            'Browse, sort, hide, or delete published articles',
          ),
          isExpanded: _isPublishedSectionExpanded,
          onTap: () => setState(
            () => _isPublishedSectionExpanded = !_isPublishedSectionExpanded,
          ),
        ),
        if (_isPublishedSectionExpanded) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <({String key, String label})>[
                    (key: 'date_desc', label: s.t('Tarih (Yeni)', 'Newest')),
                    (key: 'date_asc', label: s.t('Tarih (Eski)', 'Oldest')),
                    (key: 'level_asc', label: s.t('Seviye (A1–C2)', 'Level')),
                    (key: 'title_asc', label: s.t('İsim (A–Z)', 'Name (A–Z)')),
                  ].map((opt) {
                    return ChoiceChip(
                      key: ValueKey<String>('dev_panel_sort_${opt.key}'),
                      label: Text(opt.label, style: theme.textTheme.labelSmall),
                      selected: _articleSortMode == opt.key,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          setState(() => _articleSortMode = opt.key),
                    );
                  }).toList(growable: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              key: const ValueKey<String>('dev_panel_only_missing_chip'),
              label: Text(
                s.t('Sadece Eksikler', 'Missing Only'),
                style: theme.textTheme.labelSmall,
              ),
              selected: _onlyMissingArticles,
              visualDensity: VisualDensity.compact,
              onSelected: (val) => setState(() => _onlyMissingArticles = val),
            ),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final filtered = _filteredSortedArticles();
              if (filtered.isEmpty) {
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      s.t('Bu filtreye uygun makale yok.', 'No matching articles.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: filtered.take(50).map((item) {
                  final missing = item.missingLabels;
                  final dateLabel = _formatPublishedDate(item.publishedAt);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 17,
                        backgroundColor: item.isHidden
                            ? colorScheme.surfaceContainerHighest
                            : colorScheme.secondaryContainer,
                        child: Text(
                          item.level,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: item.isHidden
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: item.isHidden
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${item.hasAudio ? "🎙 Podcast AI" : "🔊 Cihaz TTS"}${item.isHidden ? " • Gizli" : ""}${dateLabel != null ? " • $dateLabel" : ""}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (missing.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 3),
                            Text(
                              'Eksik: ${missing.join(", ")}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => _handleToggleArticleHidden(item),
                            icon: Icon(
                              item.isHidden
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 19,
                            ),
                            tooltip: item.isHidden
                                ? s.t('Görünür Yap', 'Unhide')
                                : s.t('Gizle', 'Hide'),
                          ),
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => _handleDeleteArticle(item),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                              color: colorScheme.error,
                            ),
                            tooltip: s.delete,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _MiniStatBadge extends StatelessWidget {
  const _MiniStatBadge({
    required this.label,
    this.highlighted = false,
  });

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlighted
            ? colorScheme.primary.withAlpha(32)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: highlighted
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
