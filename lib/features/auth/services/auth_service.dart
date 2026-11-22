import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/auth_user.dart';

/// Kimlik doğrulama arka ucu soyutlaması (Firebase Auth + test sahteleri için).
abstract class AuthBackend {
  bool get isConfigured;

  Future<void> initialize();

  AppAuthUser? get currentUser;

  Stream<AppAuthUser?> get authStateChanges;

  Future<AuthActionResult> signInWithGoogle();

  Future<AuthActionResult> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthActionResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthActionResult> sendPasswordResetEmail(String email);

  /// Kayıtlı kullanıcı için kısa ömürlü imzalı Firebase ID Token döndürür.
  Future<String?> getIdToken();

  Future<void> signOut();
}

/// Firebase Authentication + Google Sign-In tabanlı kimlik doğrulama servisi.
///
/// `google-services.json` henüz eklenmemişse uygulamayı çökertmeden güvenli
/// biçimde devre dışı kalır ve kullanıcıya anlaşılır yönlendirme mesajı döner.
class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const <String>['email']);

  final GoogleSignIn _googleSignIn;
  bool _isConfigured = false;
  bool _initialized = false;

  @override
  bool get isConfigured => _isConfigured;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _isConfigured = Firebase.apps.isNotEmpty;
    } catch (error) {
      debugPrint(
        '[FirebaseAuthBackend] Firebase yapilandirilamadi (google-services.json eksik olabilir): $error',
      );
      _isConfigured = false;
    }
  }

  @override
  AppAuthUser? get currentUser {
    if (!_isConfigured) return null;
    try {
      final user = FirebaseAuth.instance.currentUser;
      return user == null ? null : _mapFirebaseUser(user);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<AppAuthUser?> get authStateChanges {
    if (!_isConfigured) {
      return const Stream<AppAuthUser?>.empty();
    }
    try {
      return FirebaseAuth.instance.authStateChanges().map(
            (user) => user == null ? null : _mapFirebaseUser(user),
          );
    } catch (_) {
      return const Stream<AppAuthUser?>.empty();
    }
  }

  AppAuthUser _mapFirebaseUser(User user) {
    final isGoogle = user.providerData.any(
      (info) => info.providerId == 'google.com',
    );
    return AppAuthUser(
      uid: user.uid,
      email: (user.email ?? '').trim(),
      displayName: user.displayName,
      photoUrl: user.photoURL,
      provider: isGoogle ? AuthProviderType.google : AuthProviderType.email,
    );
  }

  @override
  Future<AuthActionResult> signInWithGoogle() async {
    await initialize();
    if (!_isConfigured) {
      return const AuthActionResult.failure(
        errorCode: 'not_configured',
        message:
            'Firebase hesabı henüz yapılandırılmadı. Şimdilik Misafir olarak devam edebilirsiniz.',
      );
    }

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return const AuthActionResult.cancelled();
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        return const AuthActionResult.failure(
          errorCode: 'missing_token',
          message: 'Google kimlik doğrulama belirteci alınamadı.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        return const AuthActionResult.failure(
          errorCode: 'null_user',
          message: 'Google girişi tamamlanamadı.',
        );
      }

      return AuthActionResult.success(user: _mapFirebaseUser(user));
    } on FirebaseAuthException catch (error) {
      return AuthActionResult.failure(
        errorCode: error.code,
        message: _mapFirebaseError(error.code),
      );
    } on PlatformException catch (error) {
      debugPrint('[FirebaseAuthBackend] Google Sign-In platform hatasi: $error');
      return AuthActionResult.failure(
        errorCode: error.code,
        message: 'Google ile giriş yapılamadı (${error.code}).',
      );
    } catch (error) {
      debugPrint('[FirebaseAuthBackend] Google Sign-In hatasi: $error');
      return const AuthActionResult.failure(
        errorCode: 'unknown',
        message: 'Google ile giriş sırasında beklenmeyen bir hata oluştu.',
      );
    }
  }

  @override
  Future<AuthActionResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await initialize();
    if (!_isConfigured) {
      return const AuthActionResult.failure(
        errorCode: 'not_configured',
        message:
            'Firebase hesabı henüz yapılandırılmadı. Şimdilik Misafir olarak devam edebilirsiniz.',
      );
    }

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return const AuthActionResult.failure(
          errorCode: 'null_user',
          message: 'Giriş tamamlanamadı.',
        );
      }
      return AuthActionResult.success(user: _mapFirebaseUser(user));
    } on FirebaseAuthException catch (error) {
      return AuthActionResult.failure(
        errorCode: error.code,
        message: _mapFirebaseError(error.code),
      );
    } catch (error) {
      debugPrint('[FirebaseAuthBackend] Email giris hatasi: $error');
      return const AuthActionResult.failure(
        errorCode: 'unknown',
        message: 'E-posta ile giriş sırasında bir hata oluştu.',
      );
    }
  }

  @override
  Future<AuthActionResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await initialize();
    if (!_isConfigured) {
      return const AuthActionResult.failure(
        errorCode: 'not_configured',
        message:
            'Firebase hesabı henüz yapılandırılmadı. Şimdilik Misafir olarak devam edebilirsiniz.',
      );
    }

    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return const AuthActionResult.failure(
          errorCode: 'null_user',
          message: 'Hesap oluşturulamadı.',
        );
      }

      final trimmedName = displayName?.trim() ?? '';
      if (trimmedName.isNotEmpty) {
        try {
          await user.updateDisplayName(trimmedName);
          await user.reload();
        } catch (_) {}
      }

      final refreshed = FirebaseAuth.instance.currentUser ?? user;
      return AuthActionResult.success(user: _mapFirebaseUser(refreshed));
    } on FirebaseAuthException catch (error) {
      return AuthActionResult.failure(
        errorCode: error.code,
        message: _mapFirebaseError(error.code),
      );
    } catch (error) {
      debugPrint('[FirebaseAuthBackend] Email kayit hatasi: $error');
      return const AuthActionResult.failure(
        errorCode: 'unknown',
        message: 'Kayıt sırasında bir hata oluştu.',
      );
    }
  }

  @override
  Future<AuthActionResult> sendPasswordResetEmail(String email) async {
    await initialize();
    if (!_isConfigured) {
      return const AuthActionResult.failure(
        errorCode: 'not_configured',
        message: 'Firebase hesabı henüz yapılandırılmadı.',
      );
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return const AuthActionResult.success(
        message: 'Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.',
      );
    } on FirebaseAuthException catch (error) {
      return AuthActionResult.failure(
        errorCode: error.code,
        message: _mapFirebaseError(error.code),
      );
    } catch (_) {
      return const AuthActionResult.failure(
        errorCode: 'unknown',
        message: 'Şifre sıfırlama isteği gönderilemedi.',
      );
    }
  }

  @override
  Future<String?> getIdToken() async {
    if (!_isConfigured) return null;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (error) {
      debugPrint('[FirebaseAuthBackend] ID token alma hatasi: $error');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    if (!_isConfigured) return;
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  static String _mapFirebaseError(String code) {
    return switch (code) {
      'invalid-email' => 'Geçersiz e-posta adresi.',
      'user-disabled' => 'Bu hesap devre dışı bırakılmış.',
      'user-not-found' => 'Bu e-posta ile kayıtlı kullanıcı bulunamadı.',
      'wrong-password' ||
      'invalid-credential' =>
        'E-posta veya şifre hatalı.',
      'email-already-in-use' => 'Bu e-posta adresi zaten kayıtlı.',
      'weak-password' => 'Şifre en az 6 karakter olmalıdır.',
      'too-many-requests' =>
        'Çok fazla deneme yapıldı. Lütfen biraz sonra tekrar deneyin.',
      'network-request-failed' =>
        'İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.',
      'account-exists-with-different-credential' =>
        'Bu e-posta başka bir giriş yöntemiyle kayıtlı.',
      _ => 'İşlem tamamlanamadı ($code).',
    };
  }
}
