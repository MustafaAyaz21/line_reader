import 'dart:async';

import 'package:flutter/foundation.dart';
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

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late bool _isSignUpMode;
  bool _obscurePassword = true;
  bool _justVerified = false;
  bool _isCheckingVerification = false;
  Timer? _verificationPollTimer;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isSignUpMode = widget.initialSignUpTab;
    if (widget.controller.isAwaitingEmailVerification) {
      _startVerificationPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _verificationPollTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.controller.isAwaitingEmailVerification) {
      _checkVerificationNow();
    }
  }

  void _startVerificationPolling() {
    _verificationPollTimer?.cancel();
    _verificationPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkVerificationNow(),
    );
  }

  Future<void> _checkVerificationNow() async {
    if (_isCheckingVerification || _justVerified || !mounted) return;
    if (!widget.controller.isAwaitingEmailVerification) return;
    _isCheckingVerification = true;
    try {
      final verified = await widget.controller.checkEmailVerified();
      if (!mounted) return;
      if (verified) {
        _verificationPollTimer?.cancel();
        setState(() => _justVerified = true);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        if (widget.canPop) {
          Navigator.of(context).pop(true);
        }
      }
    } finally {
      _isCheckingVerification = false;
    }
  }

  Future<void> _handleResendVerification() async {
    final result = await widget.controller.resendVerificationEmail();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _infoMessage = result.message ??
            context.l10n.t(
              'Doğrulama e-postası tekrar gönderildi.',
              'Verification email resent.',
            );
        _errorMessage = null;
      } else {
        _errorMessage = result.message;
      }
    });
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

    if (_isSignUpMode && name.length < 2) {
      setState(() {
        _errorMessage = s.t(
          'Lütfen adınızı ve soyadınızı girin (zorunlu).',
          'Please enter your full name (required).',
        );
        _infoMessage = null;
      });
      return;
    }

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
            displayName: name,
          )
        : await widget.controller.signInWithEmail(
            email: email,
            password: password,
          );

    if (!mounted) return;

    if (result.isSuccess) {
      if (widget.controller.isAwaitingEmailVerification) {
        _startVerificationPolling();
        setState(() {
          _infoMessage = s.t(
            'Doğrulama bağlantısı $email adresine gönderildi. Maildeki linke tıklayınca otomatik giriş yapılacaktır.',
            'Verification link sent to $email. Click the link in your email to continue automatically.',
          );
        });
        return;
      }
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
        final awaitingVerification =
            widget.controller.isAwaitingEmailVerification;

        if (_justVerified || awaitingVerification) {
          return _buildVerificationScaffold(
            context,
            theme: theme,
            colorScheme: colorScheme,
            visuals: visuals,
            s: s,
          );
        }

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
                          key: const ValueKey<String>('auth_name_field'),
                          controller: _nameController,
                          enabled: !isBusy,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: s.t('Ad Soyad *', 'Full Name *'),
                            helperText: s.t('Zorunlu alan', 'Required'),
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
                          labelText: _isSignUpMode
                              ? s.t('E-posta (Gmail) *', 'Email *')
                              : s.t('E-posta', 'Email'),
                          helperText: _isSignUpMode
                              ? s.t('Zorunlu alan', 'Required')
                              : null,
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
                          labelText: _isSignUpMode
                              ? s.t('Şifre *', 'Password *')
                              : s.t('Şifre', 'Password'),
                          helperText: _isSignUpMode
                              ? s.t('Zorunlu • En az 6 karakter', 'Required • Min 6 characters')
                              : null,
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

  Widget _buildVerificationScaffold(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme colorScheme,
    required AppThemeVisuals visuals,
    required AppStrings s,
  }) {
    final email = widget.controller.user?.email ?? _emailController.text.trim();

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _justVerified
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              CircleAvatar(
                                radius: 32,
                                backgroundColor: const Color(0xFF16A34A)
                                    .withAlpha(36),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 36,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                s.t('Doğrulandınız!', 'Email Verified!'),
                                key: const ValueKey<String>(
                                  'auth_verified_success_title',
                                ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                s.t(
                                  'Ana Menüye aktarılıyorsunuz...',
                                  'Taking you to Home...',
                                ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Center(
                                child: CircleAvatar(
                                  radius: 30,
                                  backgroundColor: colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.mark_email_unread_outlined,
                                    size: 30,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                s.t(
                                  'E-postanızı Doğrulayın',
                                  'Verify Your Email',
                                ),
                                key: const ValueKey<String>(
                                  'auth_verify_waiting_title',
                                ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                s.t(
                                  kIsWeb
                                      ? '$email adresine doğrulama bağlantısı gönderdik. Maildeki "E-postayı Doğrula" bağlantısına tıkladığınızda web sitesine otomatik dönüp giriş yapacaksınız.'
                                      : '$email adresine doğrulama bağlantısı gönderdik. Maildeki "E-postayı Doğrula" bağlantısına tıkladığınızda uygulamaya otomatik dönüp giriş yapacaksınız.',
                                  'We sent a verification link to $email. Tap the link in your email to return and sign in automatically.',
                                ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    s.t(
                                      'Doğrulama bekleniyor...',
                                      'Waiting for verification...',
                                    ),
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (_infoMessage != null) ...<Widget>[
                                const SizedBox(height: 14),
                                Text(
                                  _infoMessage!,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                              if (_errorMessage != null) ...<Widget>[
                                const SizedBox(height: 14),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.error,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              OutlinedButton.icon(
                                onPressed: _handleResendVerification,
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(
                                  s.t(
                                    'Doğrulama Mailini Tekrar Gönder',
                                    'Resend Verification Email',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () async {
                                  _verificationPollTimer?.cancel();
                                  await widget.controller.signOut();
                                  if (!mounted) return;
                                  setState(() {
                                    _infoMessage = null;
                                    _errorMessage = null;
                                  });
                                },
                                child: Text(
                                  s.t(
                                    'Farklı E-posta ile Dene',
                                    'Use a Different Email',
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
      ),
    );
  }
}
