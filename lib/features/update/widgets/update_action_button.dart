import 'package:flutter/material.dart';

import '../controllers/app_update_controller.dart';
import '../screens/app_update_screen.dart';

/// Üst barda API anahtarı ikonunun hemen solunda yer alan güncelleme butonu.
/// Yeni sürüm bulunduğunda ikonun alt kısmında belirgin kırmızı gösterge yanar;
/// dokunulduğunda ayrı Güncellemeler sayfasını açar.
class UpdateActionButton extends StatelessWidget {
  const UpdateActionButton({
    super.key,
    required this.controller,
  });

  final AppUpdateController controller;

  void _openUpdateScreen(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppUpdateScreen(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasUpdate = controller.hasUpdate;

        return IconButton(
          onPressed: () => _openUpdateScreen(context),
          tooltip: hasUpdate ? 'Yeni Güncelleme Mevcut' : 'Güncellemeler',
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 22,
                color: hasUpdate ? colorScheme.primary : colorScheme.onSurface,
              ),
              if (hasUpdate) ...[
                const SizedBox(height: 2.5),
                Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(2),
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
