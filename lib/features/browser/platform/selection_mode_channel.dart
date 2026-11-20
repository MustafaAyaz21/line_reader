import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kalem (Kelime Seçimi) modunun açık/kapalı durumunu native Android
/// ActionMode filtresine ileten platform kanalı.
abstract final class SelectionModeChannel {
  static const MethodChannel _channel =
      MethodChannel('com.lineapps.linereader/selection_mode');

  static Future<void> setPenMode(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'setPenMode',
        <String, Object>{'enabled': enabled},
      );
    } catch (_) {
      // Desteklenmeyen platformda veya kanal hazır değilse sessizce geç.
    }
  }
}
