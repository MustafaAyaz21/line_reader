import 'package:flutter/services.dart';

import 'process_text_channel.dart';

/// Şeffaf açılır mini kart (`ProcessTextOverlayActivity` — "Line'da Bak") ile
/// Flutter arasındaki platform kanalı köprüsü.
abstract final class LookupOverlayChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.lineapps.linereader/lookup_overlay',
  );

  /// Seçilip gönderilen başlangıç metnini alır ve dış noktalama gürültüsünü temizler.
  static Future<String?> getLookupText() async {
    try {
      final raw = await _channel.invokeMethod<String>('getLookupText');
      if (raw == null) return null;
      return ProcessTextChannel.sanitizeExternalQuery(raw);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Overlay aktivitesini canlı iken yeni bir "Line'da Bak" metni geldiğinde dinler.
  static void setOnLookupTextListener(void Function(String text)? listener) {
    if (listener == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onLookupText') {
        final raw = call.arguments;
        if (raw is String) {
          final cleaned = ProcessTextChannel.sanitizeExternalQuery(raw);
          if (cleaned != null && cleaned.isNotEmpty) {
            listener(cleaned);
          }
        }
      }
    });
  }

  /// Şeffaf mini kartı kapatıp kullanıcıyı arkadaki uygulamaya anında geri döndürür.
  static Future<void> closeOverlay() async {
    try {
      await _channel.invokeMethod<void>('closeOverlay');
    } on MissingPluginException {
      // Test veya Android dışı ortamlarda sessizce yoksay.
    } catch (_) {}
  }

  /// Kelimeyi tam Line Reader uygulamasındaki Kelimelerim -> Kelime Ara
  /// bölümünde açar ve mini kartı kapatır.
  static Future<void> openInMainApp(String word) async {
    try {
      await _channel.invokeMethod<void>(
        'openInMainApp',
        <String, Object?>{'word': word.trim()},
      );
    } on MissingPluginException {
      // Test veya Android dışı ortamlarda sessizce yoksay.
    } catch (_) {}
  }
}
