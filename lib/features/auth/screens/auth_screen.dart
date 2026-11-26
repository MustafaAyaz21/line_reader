import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  late bool _isSignUpMode;
  bool _obscurePassword = true;
  bool _justVerified = false;
  bool _isCheckingVerification = false;
  bool _isVerifyingOtp = false;
  int _resendCooldown = 0;
  Timer? _verificationPollTimer;
  Timer? _resendCooldownTimer;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isSignUpMode = widget.initialSignUpTab;
    if (widget.controller.isAwaitingEmailVerification) {
      if (widget.controller.isOtpVerificationMode) {
        _startCooldownTimer(
          widget.controller.otpResendCooldownSeconds > 0
              ? widget.controller.otpResendCooldownSeconds
              : 60,
        );
      } else {
        _startVerificationPolling();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _verificationPollTimer?.cancel();
    _resendCooldownTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  void _startCooldownTimer(int seconds) {
    _resendCooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _resendCooldown = seconds.clamp(0, 120));
    if (_resendCooldown <= 0) return;
    _resendCooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_resendCooldown <= 1) {
          timer.cancel();
          setState(() => _resendCooldown = 0);
        } else {
          setState(() => _resendCooldown -= 1);
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.controller.isAwaitingEmailVerification) {
        _checkVerificationNow();
      }
      // Kullanıcı Google penceresinden dönmüş veya vazgeçmişse takılı kalmayı önle
      if (widget.controller.isBusy) {
        Future<void>.delayed(const Duration(milliseconds: 1200), () {
          if (mounted &&
              widget.controller.isBusy &&
              !widget.controller.isAuthenticated) {
            widget.controller.cancelBusyState();
            setState(() {
              _errorMessage = null;
            });
          }
        });
      }
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
    if (_resendCooldown > 0) return;
    final lang = context.l10n.t('tr', 'en');
    final result = await widget.controller.resendVerificationEmail(lang: lang);
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _infoMessage = result.message ??
            context.l10n.t(
              'Doğrulama kodu tekrar gönderildi.',
              'Verification code resent.',
            );
        _errorMessage = null;
      } else {
        _errorMessage = result.message;
      }
    });
    if (widget.controller.isOtpVerificationMode) {
      _startCooldownTimer(
        widget.controller.otpResendCooldownSeconds > 0
            ? widget.controller.otpResendCooldownSeconds
            : 60,
      );
    } else {
      _startVerificationPolling();
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '').trim();
    if (code.length != 6 || _isVerifyingOtp || _justVerified) return;
    setState(() {
      _isVerifyingOtp = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    final lang = context.l10n.t('tr', 'en');
    final result = await widget.controller.verifyEmailOtp(code, lang: lang);
    if (!mounted) return;
    if (result.isSuccess) {
      HapticFeedback.mediumImpact();
      _resendCooldownTimer?.cancel();
      setState(() {
        _isVerifyingOtp = false;
        _justVerified = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      if (widget.canPop) {
        Navigator.of(context).pop(true);
      }
    } else {
      HapticFeedback.lightImpact();
      setState(() {
        _isVerifyingOtp = false;
        _errorMessage = result.message ??
            context.l10n.t(
              'Kod doğrulanamadı.',
              'Could not verify code.',
            );
      });
    }
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
    } else {
      // İptal edildiyse veya vazgeçildiyse ekranı temiz bırak
      setState(() {
        _errorMessage = null;
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

    final lang = s.t('tr', 'en');
    final result = _isSignUpMode
        ? await widget.controller.signUpWithEmail(
            email: email,
            password: password,
            displayName: name,
            lang: lang,
          )
        : await widget.controller.signInWithEmail(
            email: email,
            password: password,
          );

    if (!mounted) return;

    if (result.isSuccess) {
      if (widget.controller.isAwaitingEmailVerification) {
        if (widget.controller.isOtpVerificationMode) {
          _otpController.clear();
          _startCooldownTimer(
            widget.controller.otpResendCooldownSeconds > 0
                ? widget.controller.otpResendCooldownSeconds
                : 60,
          );
          setState(() {
            _infoMessage = s.t(
              '6 haneli doğrulama kodunu $email adresine gönderdik.',
              'We sent a 6-digit verification code to $email.',
            );
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _otpFocusNode.requestFocus();
          });
        } else {
          _startVerificationPolling();
          setState(() {
            _infoMessage = s.t(
              'Doğrulama bağlantısı $email adresine gönderildi. Maildeki linke tıklayınca otomatik giriş yapılacaktır.',
              'Verification link sent to $email. Click the link in your email to continue automatically.',
            );
          });
        }
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
        _isSignUpMode = false;
        _passwordController.clear();
        _errorMessage = null;
        _infoMessage = s.t(
          'Şifre sıfırlama bağlantısı e-posta adresinize gönderildi. Şifrenizi yeniledikten sonra bu ekrandan giriş yapabilirsiniz.',
          'A password reset link has been sent to your email. You can sign in once you reset your password.',
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.t(
                'Şifre sıfırlama bağlantısı gönderildi. Giriş ekranına yönlendirildiniz.',
                'Password reset link sent. Redirected to sign-in.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.black.withAlpha(20),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(20),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            'assets/app_logo.png',
                            fit: BoxFit.contain,
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
                      if (isBusy) ...<Widget>[
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              widget.controller.cancelBusyState();
                              setState(() {
                                _errorMessage = null;
                              });
                            },
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: Text(
                              s.t('Giriş İşlemini İptal Et', 'Cancel Sign-In'),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildOtpBoxes(ThemeData theme, ColorScheme colorScheme) {
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '');
    return GestureDetector(
      onTap: () => _otpFocusNode.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Gizli gerçek TextField (kopyala-yapıştır ve klavye otomatik doldurma için)
          Opacity(
            opacity: 0.0,
            child: SizedBox(
              height: 56,
              child: TextField(
                key: const ValueKey<String>('auth_otp_input'),
                controller: _otpController,
                focusNode: _otpFocusNode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.oneTimeCode],
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (value) {
                  setState(() => _errorMessage = null);
                  if (value.length == 6) {
                    _handleVerifyOtp();
                  }
                },
                onSubmitted: (_) => _handleVerifyOtp(),
              ),
            ),
          ),
          // 6 adet modern OTP kutucuğu
          IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List<Widget>.generate(6, (index) {
                final hasChar = index < code.length;
                final isActive =
                    _otpFocusNode.hasFocus && index == code.length.clamp(0, 5);
                final char = hasChar ? code[index] : '';
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 46,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hasChar
                        ? colorScheme.primaryContainer.withAlpha(90)
                        : colorScheme.surfaceContainerHighest.withAlpha(110),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive
                          ? colorScheme.primary
                          : (hasChar
                              ? colorScheme.primary.withAlpha(150)
                              : colorScheme.outlineVariant),
                      width: isActive ? 2.0 : 1.2,
                    ),
                    boxShadow: isActive
                        ? <BoxShadow>[
                            BoxShadow(
                              color: colorScheme.primary.withAlpha(36),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    char,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
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
    final isOtpMode = widget.controller.isOtpVerificationMode;
    final otpDigits = _otpController.text.replaceAll(RegExp(r'\D'), '');

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withAlpha(242),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withAlpha(130),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withAlpha(18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: _justVerified
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              CircleAvatar(
                                radius: 34,
                                backgroundColor:
                                    const Color(0xFF16A34A).withAlpha(36),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 38,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                              const SizedBox(height: 18),
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
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withAlpha(190),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(
                                    isOtpMode
                                        ? Icons.mark_email_read_rounded
                                        : Icons.mark_email_unread_outlined,
                                    size: 32,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
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
                              const SizedBox(height: 10),
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withAlpha(140),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    email,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isOtpMode
                                    ? s.t(
                                        'Gelen kutunuza gönderdiğimiz 6 haneli tek kullanımlık doğrulama kodunu aşağıya girin.',
                                        'Enter the 6-digit verification code we sent to your inbox below.',
                                      )
                                    : s.t(
                                        kIsWeb
                                            ? 'Maildeki "E-postayı Doğrula" bağlantısına tıkladığınızda web sitesine otomatik dönüp giriş yapacaksınız.'
                                            : 'Maildeki "E-postayı Doğrula" bağlantısına tıkladığınızda uygulamaya otomatik dönüp giriş yapacaksınız.',
                                        'Tap the verification link in your email to return and sign in automatically.',
                                      ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 22),
                              if (isOtpMode) ...<Widget>[
                                _buildOtpBoxes(theme, colorScheme),
                                const SizedBox(height: 20),
                                FilledButton(
                                  key: const ValueKey<String>(
                                    'auth_verify_otp_button',
                                  ),
                                  onPressed: (otpDigits.length == 6 &&
                                          !_isVerifyingOtp)
                                      ? _handleVerifyOtp
                                      : null,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: _isVerifyingOtp
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                          ),
                                        )
                                      : Text(
                                          s.t(
                                            'Doğrula ve Devam Et',
                                            'Verify and Continue',
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                              ] else
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
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              if (_infoMessage != null) ...<Widget>[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withAlpha(140),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _infoMessage!,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                              if (_errorMessage != null) ...<Widget>[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              OutlinedButton.icon(
                                onPressed: _resendCooldown > 0
                                    ? null
                                    : _handleResendVerification,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(
                                  _resendCooldown > 0
                                      ? s.t(
                                          'Kodu Tekrar Gönder ($_resendCooldown sn)',
                                          'Resend Code (${_resendCooldown}s)',
                                        )
                                      : s.t(
                                          isOtpMode
                                              ? 'Kodu Tekrar Gönder'
                                              : 'Doğrulama Mailini Tekrar Gönder',
                                          isOtpMode
                                              ? 'Resend Code'
                                              : 'Resend Verification Email',
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () async {
                                  _verificationPollTimer?.cancel();
                                  _resendCooldownTimer?.cancel();
                                  _otpController.clear();
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
