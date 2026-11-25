import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../auth/controllers/auth_controller.dart';
import '../controllers/ad_config_controller.dart';

/// Reklam alanı konumlandırması (üst ya da alt).
enum AppBannerPlacement {
  top,
  bottom,
}

/// Google Play AdMob standartlarına uygun, Premium/Yetkili olmayan kullanıcılara
/// (Misafir ve Standart Kayıtlı) gösterilen dinamik banner reklam bileşeni.
///
/// Kullanıcı Sınırsız (Premium / Admin) yetkisine sahipse otomatik olarak
/// hiçbir alan kaplamadan gizlenir (`SizedBox.shrink()`).
class AppBannerAd extends StatelessWidget {
  const AppBannerAd({
    super.key,
    required this.authController,
    this.placement = AppBannerPlacement.bottom,
    this.customHeadline,
    this.customBody,
    this.customActionText,
    this.onActionPressed,
    this.showBadge = true,
  });

  final AuthController authController;
  final AppBannerPlacement placement;

  final String? customHeadline;
  final String? customBody;
  final String? customActionText;
  final VoidCallback? onActionPressed;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([authController, AdConfigController.instance]),
      builder: (context, _) {
        // Premium / Yetkili kullanıcılarda veya reklam kapatıldıysa sıfır piksel
        if (authController.isUnlimited || !AdConfigController.instance.isEnabled) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final s = context.l10n;

        final isTop = placement == AppBannerPlacement.top;
        final config = AdConfigController.instance;

        final headline = customHeadline ?? config.headline;
        final body = customBody ?? config.body;
        final actionText = customActionText ?? config.actionText;

        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(
            top: isTop ? 6 : 4,
            bottom: isTop ? 4 : 6,
            left: 12,
            right: 12,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(140),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(120),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 8,
                offset: Offset(0, isTop ? 2 : -2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Sol Reklam / Admob İkon Alanı
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // Metin Bilgisi (Başlık ve Açıklama)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (showBadge) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withAlpha(35),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s.t('REKLAM', 'AD'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Aksiyon Butonu
              if (actionText.isNotEmpty) ...[
                const SizedBox(width: 10),
                FilledButton.tonal(
                  onPressed: onActionPressed ??
                      () {
                        // Tıklandığında varsayılan olarak reklam/kod etkileşimi
                      },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: const Size(54, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    actionText,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
