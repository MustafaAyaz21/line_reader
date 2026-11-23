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

  List<DevEntitlementUser> _users = const <DevEntitlementUser>[];
  List<DevAccessCode> _codes = const <DevAccessCode>[];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _ownsService = widget.service == null;
    _service = widget.service ?? DeveloperPanelService();
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _maxUsesController.dispose();
    _noteController.dispose();
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

      final results = await Future.wait<Object>(<Future<Object>>[
        _service.fetchUsers(token),
        _service.fetchCodes(token),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<DevEntitlementUser>;
        _codes = results[1] as List<DevAccessCode>;
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
                text: s.t('Premium Üyeler', 'Premium Users'),
              ),
              Tab(
                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                text: s.t('Aktivasyon Kodları', 'Access Codes'),
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
                    ],
                  ),
      ),
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
                FilledButton.icon(
                  key: const ValueKey<String>('dev_panel_grant_premium_btn'),
                  onPressed: _isSubmitting ? null : _handleGrantPremium,
                  icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                  label: Text(s.t('Premium Üye Ver', 'Grant Premium')),
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
                  user.isDeveloper
                      ? s.t('Geliştirici (PC korumalı)', 'Developer (PC protected)')
                      : (user.codeUsed != null && user.codeUsed!.isNotEmpty
                          ? '${s.t('Premium Üye', 'Premium Member')} • ${user.codeUsed}'
                          : s.t('Premium Üye', 'Premium Member')),
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
                    : IconButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => _handleRevokePremium(user),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                        tooltip: s.t('Yetkiyi Kaldır', 'Revoke'),
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
}
