import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_backdrop.dart';
import '../controllers/auth_controller.dart';

/// Gmail (Google) ile tek tık giriş, E-posta/Şifre ile kayıt & giriş ve
/// günlük 40 kelime çeviri haklı Misafir devamı sunan hesap ekranı.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.controller,
    this.canPop = false,
    this.initialSignUpTab = true,
  });

  final AuthController controller;

  /// Ayarlardan veya kota uyarısından açıldıysa geri dönülebilir (`true`);
  /// ilk açılış karşılama ekranındaysa (`false`) giriş ya da Misafir seçilir.
  final bool canPop;
  final bool initialSignUpTab;

  static Future<bool?> show(
    BuildContext context, {
    required AuthController controller,
    bool initialSignUpTab = true,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AuthScreen(
          controller: controller,
          canPop: true,
          initialSignUpTab: initialSignUpTab,
        ),
      ),
    );
  }

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late bool _isSignUpMode;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _isSignUpMode = widget.initialSignUpTab;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = await widget.controller.signInWithGoogle();
    if (!mounted) return;

    if (result.isSuccess) {
      if (widget.canPop) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    if (!result.isCancelled) {
      setState(() {
        _errorMessage = result.message ??
            context.l10n.t(
              'Google ile giriş yapılamadı.',
              'Could not sign in with Google.',
            );
      });
    }
  }

  Future<void> _handleEmailSubmit() async {
    final s = context.l10n;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = s.t(
          'Lütfen geçerli bir e-posta adresi girin.',
          'Please enter a valid email address.',
        );
        _infoMessage = null;
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _errorMessage = s.t(
          'Şifre en az 6 karakter olmalıdır.',
          'Password must be at least 6 characters.',
        );
        _infoMessage = null;
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = _isSignUpMode
        ? await widget.controller.signUpWithEmail(
            email: email,
            password: password,
            displayName: name.isEmpty ? null : name,
          )
        : await widget.controller.signInWithEmail(
            email: email,
            password: password,
          );

    if (!mounted) return;

    if (result.isSuccess) {
      if (widget.canPop) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    setState(() {
      _errorMessage = result.message ??
          s.t('İşlem tamamlanamadı.', 'Could not complete request.');
    });
  }

  Future<void> _handleForgotPassword() async {
    final s = context.l10n;
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = s.t(
          'Şifre sıfırlama için önce e-posta adresinizi yazın.',
          'Enter your email address first to reset your password.',
        );
        _infoMessage = null;
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = await widget.controller.sendPasswordResetEmail(email);
    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _infoMessage = s.t(
          'Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.',
          'A password reset link has been sent to your email.',
        );
      });
    } else {
      setState(() {
        _errorMessage = result.message ??
            s.t(
              'Şifre sıfırlama bağlantısı gönderilemedi.',
              'Could not send password reset email.',
            );
      });
    }
  }

  Future<void> _handleContinueAsGuest() async {
    await widget.controller.continueAsGuest();
    if (!mounted) return;
    if (widget.canPop) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final isBusy = widget.controller.isBusy;
        final visuals = AppThemeVisuals.of(context);

        return AppThemeBackdrop(
          child: Scaffold(
            backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
            appBar: widget.canPop
              ? AppBar(
                  title: Text(_isSignUpMode ? s.signUp : s.signIn),
                )
              : null,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.auto_stories_rounded,
                            size: 32,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Line Reader',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.t(
                          'Günlük 80 kelime çeviri hakkı için ücretsiz hesabınızla devam edin; aktivasyon kodu ile sınırsız erişime geçin.',
                          'Continue with a free account for 80 daily word translations; redeem a code for unlimited access.',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Kayıt Ol / Giriş Yap sekme seçici
                      SegmentedButton<bool>(
                        segments: <ButtonSegment<bool>>[
                          ButtonSegment<bool>(
                            value: true,
                            label: Text(s.signUp),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text(s.signIn),
                          ),
                        ],
                        selected: <bool>{_isSignUpMode},
                        onSelectionChanged: isBusy
                            ? null
                            : (selected) {
                                setState(() {
                                  _isSignUpMode = selected.first;
                                  _errorMessage = null;
                                  _infoMessage = null;
                                });
                              },
                      ),
                      const SizedBox(height: 18),
                      // Google (Gmail) ile giriş butonu
                      OutlinedButton.icon(
                        key: const ValueKey<String>('auth_google_button'),
                        onPressed: isBusy ? null : _handleGoogleSignIn,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                        label: Text(
                          s.continueWithGoogle,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(child: Divider(color: colorScheme.outlineVariant)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              s.t('veya e-posta ile', 'or with email'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: colorScheme.outlineVariant)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_isSignUpMode) ...<Widget>[
                        TextField(
                          controller: _nameController,
                          enabled: !isBusy,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: s.t('Ad Soyad (Opsiyonel)', 'Name (Optional)'),
                            prefixIcon: const Icon(Icons.person_outline_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        key: const ValueKey<String>('auth_email_field'),
                        controller: _emailController,
                        enabled: !isBusy,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: s.t('E-posta', 'Email'),
                          prefixIcon: const Icon(Icons.mail_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey<String>('auth_password_field'),
                        controller: _passwordController,
                        enabled: !isBusy,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => isBusy ? null : _handleEmailSubmit(),
                        decoration: InputDecoration(
                          labelText: s.t('Şifre', 'Password'),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      if (!_isSignUpMode) ...<Widget>[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isBusy ? null : _handleForgotPassword,
                            child: Text(
                              s.t('Şifremi Unuttum', 'Forgot Password?'),
                            ),
                          ),
                        ),
                      ] else
                        const SizedBox(height: 14),
                      if (_errorMessage != null) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_infoMessage != null) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _infoMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        key: const ValueKey<String>('auth_email_submit_button'),
                        onPressed: isBusy ? null : _handleEmailSubmit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Text(
                                _isSignUpMode
                                    ? s.t('E-posta ile Kayıt Ol', 'Sign Up with Email')
                                    : s.t('E-posta ile Giriş Yap', 'Sign In with Email'),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                      const SizedBox(height: 20),
                      // Misafir devamı + günlük 40 kelime çeviri sınırı açıklaması
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withAlpha(130),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.guestLimitNotice(
                                      AuthController.guestDailyTranslationLimit,
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              key: const ValueKey<String>('auth_guest_button'),
                              onPressed: isBusy ? null : _handleContinueAsGuest,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                s.continueAsGuest,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}
