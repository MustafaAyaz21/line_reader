import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/settings/api_key_controller.dart';
import '../../translation/services/gemini_translation_service.dart';

/// AppBar sağ üst köşesinde yer alan ve Gemini API anahtarı penceresini açan
/// ikon butonu. Gerçek doğrulama durumuna göre ikon ve durum noktasını gösterir.
class ApiKeyActionButton extends StatelessWidget {
  const ApiKeyActionButton({
    super.key,
    required this.controller,
    this.onClearCache,
  });

  final ApiKeyController controller;
  final Future<void> Function()? onClearCache;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = controller.status;

        final (IconData iconData, Color iconColor, Color? dotColor, String tip) =
            switch (status) {
          ApiKeyStatus.valid => (
              Icons.key_rounded,
              colorScheme.primary,
              colorScheme.primary,
              'Gemini API Anahtarı (Doğrulandı)',
            ),
          ApiKeyStatus.invalid => (
              Icons.key_off_rounded,
              colorScheme.error,
              colorScheme.error,
              'Gemini API Anahtarı (Geçersiz)',
            ),
          ApiKeyStatus.unverified => (
              Icons.key_outlined,
              colorScheme.onSurface,
              colorScheme.tertiary,
              'Gemini API Anahtarı (Doğrulanmadı)',
            ),
          ApiKeyStatus.none => (
              Icons.key_outlined,
              colorScheme.onSurface,
              null,
              'Gemini API Anahtarı',
            ),
        };

        return IconButton(
          onPressed: () => ApiKeyDialog.show(
            context,
            controller: controller,
            onClearCache: onClearCache,
          ),
          tooltip: tip,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(iconData, color: iconColor),
              if (dotColor != null)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Kullanıcının isteğe bağlı Gemini API anahtarını test edebildiği, kaydedebildiği,
/// silebildiği ve gerektiğinde çeviri önbelleğini temizleyebildiği pencere.
class ApiKeyDialog extends StatefulWidget {
  const ApiKeyDialog({
    super.key,
    required this.controller,
    this.onClearCache,
  });

  final ApiKeyController controller;
  final Future<void> Function()? onClearCache;

  static Future<void> show(
    BuildContext context, {
    required ApiKeyController controller,
    Future<void> Function()? onClearCache,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => ApiKeyDialog(
        controller: controller,
        onClearCache: onClearCache,
      ),
    );
  }

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  late final TextEditingController _textController;
  bool _obscureText = true;
  bool _isBusy = false;
  GeminiTestResult? _testResult;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.controller.apiKey ?? '',
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _handleTestConnection() async {
    setState(() {
      _isBusy = true;
      _testResult = null;
    });

    try {
      final result = await widget.controller.testConnection(
        _textController.text,
      );
      if (!mounted) return;
      setState(() => _testResult = result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testResult = const GeminiTestResult(
          isSuccess: false,
          message: 'Bağlantı testi sırasında beklenmeyen bir hata oluştu.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _handleSave() async {
    final trimmed = _textController.text.trim();
    if (trimmed.isEmpty) {
      await _handleDelete();
      return;
    }

    setState(() {
      _isBusy = true;
      _testResult = null;
    });

    try {
      final result = await widget.controller.verifyAndSaveApiKey(trimmed);
      if (!mounted) return;

      if (result.isSuccess) {
        // Doğrulanmış Gemini anahtarı kaydedildiğinde eski önbellek kayıtlarını temizle.
        await widget.onClearCache?.call();
        if (!mounted) return;
        Navigator.of(context).pop();
        _showFeedback('Gemini API anahtarı doğrulandı ve kaydedildi.');
        return;
      }

      if (result.isNetworkError) {
        Navigator.of(context).pop();
        _showFeedback(
          'İnternet yok; anahtar doğrulanmamış olarak kaydedildi.',
        );
        return;
      }

      // Geçersiz anahtar: pencereyi kapatma ve gerçek Gemini hatasını göster.
      setState(() => _testResult = result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testResult = const GeminiTestResult(
          isSuccess: false,
          message: 'API anahtarı doğrulanırken veya kaydedilirken hata oluştu.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _handleDelete() async {
    setState(() => _isBusy = true);
    try {
      await widget.controller.deleteApiKey();
      if (!mounted) return;
      Navigator.of(context).pop();
      _showFeedback('Gemini API anahtarı silindi.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testResult = const GeminiTestResult(
          isSuccess: false,
          message: 'API anahtarı silinirken bir sorun oluştu.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _handleClearCache() async {
    final callback = widget.onClearCache;
    if (callback == null) return;

    setState(() => _isBusy = true);
    try {
      await callback();
      if (!mounted) return;
      _showFeedback('Çeviri önbelleği temizlendi.');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
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
    final status = widget.controller.status;
    final hasExistingKey = widget.controller.hasApiKey;

    final (String statusText, Color bgColor, Color fgColor) = switch (status) {
      ApiKeyStatus.valid => (
          s.t(
            'Doğrulandı — Gemini aktif olarak kullanılıyor.',
            'Verified — Gemini is actively used.',
          ),
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
        ),
      ApiKeyStatus.invalid => (
          widget.controller.lastErrorMessage ??
              s.t(
                'Kayıtlı anahtar geçersiz — ücretsiz varsayılan servis kullanılıyor.',
                'Saved key is invalid — free default service is active.',
              ),
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
        ),
      ApiKeyStatus.unverified => (
          s.t(
            'Kayıtlı anahtar henüz doğrulanmadı — test edip doğrulayabilirsiniz.',
            'Saved key is not verified yet — test to verify.',
          ),
          colorScheme.secondaryContainer,
          colorScheme.onSecondaryContainer,
        ),
      ApiKeyStatus.none => (
          s.t(
            'Anahtar girilmedi — ücretsiz varsayılan servis aktif.',
            'No key set — free default service is active.',
          ),
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
        ),
    };

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.key_rounded, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.t('Gemini API Anahtarı', 'Gemini API Key')),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusText,
                style: theme.textTheme.bodySmall?.copyWith(color: fgColor),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              s.t(
                'İsteğe bağlı olarak Google AI Studio üzerinden aldığınız ücretsiz Gemini API anahtarını girip doğrulayabilirsiniz.',
                'Optionally enter and verify your free Gemini API key from Google AI Studio.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _textController,
              obscureText: _obscureText,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_testResult != null) {
                  setState(() => _testResult = null);
                }
              },
              onSubmitted: (_) => _isBusy ? null : _handleSave(),
              decoration: InputDecoration(
                labelText: s.t('API Anahtarı', 'API Key'),
                hintText: 'AIza...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscureText = !_obscureText);
                  },
                  icon: Icon(
                    _obscureText
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  tooltip: _obscureText
                      ? s.t('Göster', 'Show')
                      : s.t('Gizle', 'Hide'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _handleTestConnection,
              icon: _isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded, size: 18),
              label: Text(s.t('Bağlantıyı Test Et', 'Test Connection')),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _testResult!.isSuccess
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _testResult!.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _testResult!.isSuccess
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            if (widget.onClearCache != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isBusy ? null : _handleClearCache,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: Text(
                    s.t('Çeviri Önbelleğini Temizle', 'Clear Translation Cache'),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (hasExistingKey)
          TextButton(
            onPressed: _isBusy ? null : _handleDelete,
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
            ),
            child: Text(s.delete),
          ),
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _isBusy ? null : _handleSave,
          child: Text(s.save),
        ),
      ],
    );
  }
}
