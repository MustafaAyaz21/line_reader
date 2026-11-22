import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android'de başka bir uygulamada kelime seçilip üç nokta menüsünden
/// "Line Reader ile arat" (`ACTION_PROCESS_TEXT`) seçildiğinde gelen metni
/// Flutter tarafına ileten platform kanalı köprüsü.
abstract final class ProcessTextChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.lineapps.linereader/process_text',
  );

  /// Henüz tüketilmemiş (bekleyen) dış arama metni.
  /// `SplashScreen` veya `HomeScreen` açılana kadar metin burada güvenle korunur.
  static final ValueNotifier<String?> pendingTextNotifier =
      ValueNotifier<String?>(null);

  static bool _isInitialized = false;

  /// Bekleyen dış arama metni var mı?
  static bool get hasPendingText {
    final value = pendingTextNotifier.value;
    return value != null && value.trim().isNotEmpty;
  }

  /// Platform kanalını bir kez ilklendirir; hem soğuk başlangıçtaki (`onCreate`)
  /// bekleyen metni çeker hem de uygulama açıkken gelen (`onNewIntent`) metinleri dinler.
  static void ensureInitialized() {
    if (_isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onProcessText') {
        final raw = call.arguments;
        if (raw is String) {
          _enqueueRawText(raw);
        }
      }
    });

    _loadInitialProcessText();
  }

  static Future<void> _loadInitialProcessText() async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'consumeInitialProcessText',
      );
      if (raw != null) {
        _enqueueRawText(raw);
      }
    } on MissingPluginException {
      // Android dışındaki platformlarda veya widget testlerinde sessizce yoksay.
    } catch (_) {
      // Kanal çağrısı başarısız olursa uygulamayı kesintiye uğratma.
    }
  }

  static void _enqueueRawText(String raw) {
    final cleaned = sanitizeExternalQuery(raw);
    if (cleaned == null) return;
    // Aynı metin art arda gelse bile dinleyicinin yeniden tetiklenmesi için
    // önce null'a çekip sonra yeni değeri ata.
    if (pendingTextNotifier.value == cleaned) {
      pendingTextNotifier.value = null;
    }
    pendingTextNotifier.value = cleaned;
  }

  /// Bekleyen metni döndürür ve tamponu temizler.
  static String? consumePendingText() {
    final value = pendingTextNotifier.value;
    if (value == null || value.trim().isEmpty) return null;
    pendingTextNotifier.value = null;
    return value;
  }

  /// Dış uygulamadan seçilip gelen kelime/ifadedeki baştaki ve sondaki
  /// gereksiz noktalama, tırnak ve parantezleri temizler.
  static String? sanitizeExternalQuery(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return null;

    final stripped = collapsed
        .replaceFirst(
          RegExp(r'^[\s"\x27`“”‘’(\[\{<.,!?;:—–\-•]+'),
          '',
        )
        .replaceFirst(
          RegExp(r'[\s"\x27`“”‘’)\]\}>.,!?;:—–\-•]+$'),
          '',
        )
        .trim();

    if (stripped.isNotEmpty) {
      return stripped;
    }
    return collapsed;
  }

  /// Testlerde Android'den "Line Reader ile arat" tetiklenmesini simüle eder.
  @visibleForTesting
  static void dispatchExternalTextForTest(String raw) {
    _enqueueRawText(raw);
  }

  /// Testler arasında kanal durumunu sıfırlar.
  @visibleForTesting
  static void resetForTest() {
    pendingTextNotifier.value = null;
    _isInitialized = false;
  }
}
