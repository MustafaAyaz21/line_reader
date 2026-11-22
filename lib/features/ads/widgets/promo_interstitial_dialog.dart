import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';

/// Misafir kullanıcılarda her 5 kelime sorgulamasında 1, standart (yetkisiz)
/// kayıtlı kullanıcılarda her 8 kelime sorgulamasında 1 gösterilen, 5 saniye
/// sonra geçilebilen resmi geliştirme aşaması duyuru / reklam penceresi.
class PromoInterstitialDialog extends StatefulWidget {
  const PromoInterstitialDialog({
    super.key,
    this.countdownSeconds = 5,
  });

  final int countdownSeconds;

  static Future<void> show(
    BuildContext context, {
    int countdownSeconds = 5,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Line Reader Duyuru',
      barrierColor: Colors.black.withAlpha(185),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        return PromoInterstitialDialog(countdownSeconds: countdownSeconds);
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  @override
  State<PromoInterstitialDialog> createState() =>
      _PromoInterstitialDialogState();
}

class _PromoInterstitialDialogState extends State<PromoInterstitialDialog> {
  late int _remainingSeconds;
  Timer? _timer;

  bool get _canSkip => _remainingSeconds <= 0;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds.clamp(0, 30);
    if (_remainingSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _remainingSeconds -= 1;
          if (_remainingSeconds <= 0) {
            _remainingSeconds = 0;
            timer.cancel();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleClose() {
    if (!_canSkip) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = widget.countdownSeconds > 0 ? widget.countdownSeconds : 1;
    final progress = (1 - (_remainingSeconds / total)).clamp(0.0, 1.0);

    return PopScope(
      canPop: _canSkip,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Column(
              children: <Widget>[
                // Üst satır: Duyuru etiketi + 5 sn geri sayım / Geç butonu
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(28),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withAlpha(45)),
                      ),
                      child: Text(
                        s.t('Line Reader • Duyuru', 'Line Reader • Notice'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _canSkip
                          ? FilledButton.icon(
                              key: const ValueKey<String>('promo_skip_button'),
                              onPressed: _handleClose,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF0F172A),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                              ),
                              icon: const Icon(Icons.close_rounded, size: 17),
                              label: Text(
                                s.t('Geç', 'Skip'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : Container(
                              key: const ValueKey<String>(
                                'promo_countdown_pill',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(32),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withAlpha(60),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      value: progress,
                                      strokeWidth: 2,
                                      color: Colors.white,
                                      backgroundColor:
                                          Colors.white.withAlpha(60),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    s.t(
                                      '$_remainingSeconds sn',
                                      '${_remainingSeconds}s',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Orta: Resmi ve sade geliştirme aşaması duyuru kartı (küçük/yatay ekranda taşmaz)
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Material(
                          color: colorScheme.surface,
                          elevation: 12,
                          borderRadius: BorderRadius.circular(24),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.auto_stories_rounded,
                                    size: 32,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    s.t(
                                      'Geliştirme Sürümü',
                                      'Development Preview',
                                    ),
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  s.t(
                                    'Geliştirme Aşamasındayız',
                                    'We Are Actively Developing',
                                  ),
                                  textAlign: TextAlign.center,
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  s.t(
                                    'Line Reader şu anda aktif geliştirme aşamasındadır. Okuma ve kelime öğrenme deneyiminizi daha da iyileştirebilmemiz için karşılaştığınız eksikleri, önerilerinizi ve geri dönütlerinizi bizimle paylaşmanız bizim için çok değerlidir.',
                                    'Line Reader is currently in active development. Your feedback, suggestions, and observations are truly valuable to help us craft an even better reading and vocabulary experience.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.55,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Divider(
                                  height: 1,
                                  color: colorScheme.outlineVariant,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Line Apps • Developed by Mustafa Ayaz',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    key: const ValueKey<String>(
                                      'promo_continue_button',
                                    ),
                                    onPressed: _canSkip ? _handleClose : null,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      _canSkip
                                          ? s.t(
                                              'Okumaya Devam Et',
                                              'Continue Reading',
                                            )
                                          : s.t(
                                              'Geçmek için $_remainingSeconds sn bekleyin',
                                              'You can skip in ${_remainingSeconds}s',
                                            ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
