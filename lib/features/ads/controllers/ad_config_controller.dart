import 'package:flutter/foundation.dart';

/// Dinamik banner reklam / duyuru yapılandırması.
/// İstediğin metin, başlık, buton yazısı ve yönlendirmeleri tek merkezden yönetir.
class AdConfigController extends ChangeNotifier {
  AdConfigController._();

  static final AdConfigController instance = AdConfigController._();

  String _headline = 'Line Reader • Beta Sürümü';
  String _body =
      'Uygulama şu an beta aşamasındadır, geri bildirimleriniz bizim için çok değerlidir. Umut (Alevi) kardeşimize selamlar.';
  String _actionText = 'Geri Bildirim';
  bool _isEnabled = true;

  String get headline => _headline;
  String get body => _body;
  String get actionText => _actionText;
  bool get isEnabled => _isEnabled;

  /// Reklam / duyuru metinlerini anlık olarak güncelle
  void updateContent({
    String? headline,
    String? body,
    String? actionText,
    bool? isEnabled,
  }) {
    if (headline != null) _headline = headline;
    if (body != null) _body = body;
    if (actionText != null) _actionText = actionText;
    if (isEnabled != null) _isEnabled = isEnabled;
    notifyListeners();
  }
}
