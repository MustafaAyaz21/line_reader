import 'package:flutter/foundation.dart';

import '../../features/translation/services/gemini_translation_service.dart';
import 'settings_repository.dart';

typedef GeminiVerifierFactory = GeminiTranslationService Function();

/// Kayıtlı Gemini API anahtarının gerçek doğrulama durumu.
enum ApiKeyStatus {
  /// Hiç anahtar girilmemiş (varsayılan ücretsiz servis kullanılır).
  none,

  /// Anahtar kayıtlı ancak henüz gerçek bir Gemini isteğiyle doğrulanmadı.
  unverified,

  /// Gerçek bir Gemini API isteğiyle doğrulandı ve aktif.
  valid,

  /// Gemini API anahtarı reddetti (HTTP 400/401/403 vb.).
  invalid,
}

/// Kullanıcının uygulama içinden girdiği isteğe bağlı Gemini API anahtarını
/// ve gerçek doğrulama durumunu yönetir.
class ApiKeyController extends ChangeNotifier {
  ApiKeyController(
    this._repository, {
    GeminiTranslationService? verifier,
    GeminiVerifierFactory? verifierFactory,
  })  : _verifierFactory = verifierFactory ?? _createDefaultVerifier,
        _verifier = verifier ??
            (verifierFactory ?? _createDefaultVerifier)(),
        _ownsVerifier = verifier == null;

  static GeminiTranslationService _createDefaultVerifier() {
    return GeminiTranslationService(apiKeyProvider: () => null);
  }

  final SettingsRepository _repository;
  final GeminiVerifierFactory? _verifierFactory;

  GeminiTranslationService? _verifier;
  bool? _ownsVerifier;

  String? _apiKey;
  ApiKeyStatus? _status;
  String? _lastErrorMessage;
  bool _isDisposed = false;

  String? get apiKey => _apiKey;
  String? get lastErrorMessage => _lastErrorMessage;

  bool get hasApiKey => _apiKey != null && _apiKey!.trim().isNotEmpty;

  ApiKeyStatus get status =>
      _status ?? (hasApiKey ? ApiKeyStatus.unverified : ApiKeyStatus.none);

  bool get isVerified => status == ApiKeyStatus.valid && hasApiKey;
  bool get isInvalid => status == ApiKeyStatus.invalid && hasApiKey;

  /// Yalnızca geçersiz olarak işaretlenmemiş bir anahtar varsa Gemini denenir.
  bool get shouldAttemptGemini => hasApiKey && status != ApiKeyStatus.invalid;

  /// Hot Reload veya boş/null parametrede dahi her zaman geçerli bir
  /// `GeminiTranslationService` örneği döndürür.
  GeminiTranslationService _resolveVerifier() {
    final existing = _verifier;
    if (existing != null) return existing;

    final factory = _verifierFactory ?? _createDefaultVerifier;
    final created = factory();
    _verifier = created;
    _ownsVerifier = true;
    return created;
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_ownsVerifier ?? false) {
      _verifier?.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final stored = await _repository.getGeminiApiKey();
      _apiKey = stored;
      _status = (stored != null && stored.isNotEmpty)
          ? ApiKeyStatus.unverified
          : ApiKeyStatus.none;
      _lastErrorMessage = null;
      _safeNotifyListeners();
    } catch (error) {
      debugPrint('[ApiKeyController] API anahtari okunamadi: $error');
    }
  }

  /// Anahtarı kaydetmeden önce gerçek bir Gemini çağrısıyla test eder.
  Future<GeminiTestResult> testConnection(String rawKey) async {
    final trimmed = rawKey.trim();
    try {
      final result = await _resolveVerifier().testConnection(trimmed);

      if (hasApiKey && _apiKey == trimmed) {
        if (result.isSuccess) {
          markVerified();
        } else if (!result.isNetworkError) {
          markInvalid(result.message);
        }
      }

      return result;
    } catch (error, stackTrace) {
      debugPrint(
        '[ApiKeyController] Baglanti testi sirasinda hata: $error\n$stackTrace',
      );
      return const GeminiTestResult(
        isSuccess: false,
        message: 'Gemini bağlantısı test edilemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  /// Anahtarı gerçek Gemini isteğiyle doğrulayıp yalnızca geçerliyse (veya
  /// internet yokken doğrulanmamış olarak) kaydeder; geçersiz anahtarı
  /// "aktif" olarak kaydetmez ve hiçbir durumda Unhandled Exception fırlatmaz.
  Future<GeminiTestResult> verifyAndSaveApiKey(String rawKey) async {
    final trimmed = rawKey.trim();
    if (trimmed.isEmpty) {
      try {
        await deleteApiKey();
        return const GeminiTestResult(
          isSuccess: true,
          message: 'Gemini API anahtarı silindi.',
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[ApiKeyController] Anahtar silinirken hata: $error\n$stackTrace',
        );
        return const GeminiTestResult(
          isSuccess: false,
          message: 'API anahtarı silinirken bir sorun oluştu.',
        );
      }
    }

    try {
      final result = await _resolveVerifier().testConnection(trimmed);

      if (result.isSuccess) {
        await _repository.saveGeminiApiKey(trimmed);
        _apiKey = trimmed;
        _status = ApiKeyStatus.valid;
        _lastErrorMessage = null;
        _safeNotifyListeners();
        return result;
      }

      if (result.isNetworkError) {
        await _repository.saveGeminiApiKey(trimmed);
        _apiKey = trimmed;
        _status = ApiKeyStatus.unverified;
        _lastErrorMessage = result.message;
        _safeNotifyListeners();
        return result;
      }

      // Geçersiz anahtar: kaydedilen mevcut anahtar buysa geçersiz işaretle,
      // yeni rastgele metni "aktif" sayma.
      if (_apiKey == trimmed) {
        _status = ApiKeyStatus.invalid;
        _lastErrorMessage = result.message;
        _safeNotifyListeners();
      }
      return result;
    } catch (error, stackTrace) {
      debugPrint(
        '[ApiKeyController] Anahtar dogrulama/kaydetme hatasi: '
        '$error\n$stackTrace',
      );
      return const GeminiTestResult(
        isSuccess: false,
        message:
            'API anahtarı doğrulanırken veya kaydedilirken bir sorun oluştu.',
      );
    }
  }

  /// Gerçek bir çeviri isteği Gemini'den başarıyla döndüğünde çağrılır.
  void markVerified() {
    if (!hasApiKey) return;
    if (status == ApiKeyStatus.valid && _lastErrorMessage == null) return;
    _status = ApiKeyStatus.valid;
    _lastErrorMessage = null;
    _safeNotifyListeners();
  }

  /// Gerçek bir çeviri isteğinde Gemini anahtarı reddettiğinde çağrılır.
  void markInvalid(String message) {
    if (!hasApiKey) return;
    _status = ApiKeyStatus.invalid;
    _lastErrorMessage = message;
    _safeNotifyListeners();
  }

  Future<void> deleteApiKey() async {
    try {
      await _repository.deleteGeminiApiKey();
      _apiKey = null;
      _status = ApiKeyStatus.none;
      _lastErrorMessage = null;
      _safeNotifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        '[ApiKeyController] API anahtari silme hatasi: $error\n$stackTrace',
      );
      rethrow;
    }
  }
}
