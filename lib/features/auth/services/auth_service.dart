import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

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

  /// Mevcut kullanıcıya e-posta doğrulama bağlantısı gönderir.
  Future<AuthActionResult> sendEmailVerification() async =>
      const AuthActionResult.success();

  /// Sunucudan güncel kullanıcı bilgisini (özellikle `emailVerified`) yeniler.
  Future<AppAuthUser?> reloadCurrentUser() async => currentUser;

  /// Kayıtlı kullanıcı için kısa ömürlü imzalı Firebase ID Token döndürür.
  Future<String?> getIdToken({bool forceRefresh = false});

  /// E-posta adresinin hangi sağlayıcılarla kayıtlı olduğunu sorgular.
  Future<List<String>> fetchSignInMethodsForEmail(String email) async =>
      const <String>[];

  /// Kullanıcının profil görünen ismini günceller.
  Future<void> updateDisplayName(String displayName) async {}

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

  static const FirebaseOptions _webFirebaseOptions = FirebaseOptions(
    apiKey: 'AIzaSyBrQ51YPgXYTYXb07TZoZoof8jDWwkznRc',
    appId: '1:334618302580:android:cf037968b48d28cf839921',
    messagingSenderId: '334618302580',
    projectId: 'line-reader-e2e00',
    authDomain: 'line-reader-e2e00.firebaseapp.com',
    storageBucket: 'line-reader-e2e00.firebasestorage.app',
  );

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          await Firebase.initializeApp(options: _webFirebaseOptions);
        } else {
          await Firebase.initializeApp();
        }
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
      emailVerified: isGoogle || user.emailVerified,
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
      if (kIsWeb) {
        final provider = GoogleAuthProvider()..addScope('email');
        final userCredential = await FirebaseAuth.instance
            .signInWithPopup(provider)
            .timeout(
              const Duration(seconds: 40),
              onTimeout: () => throw TimeoutException('Google sign in timed out'),
            );
        final user = userCredential.user;
        if (user == null) {
          return const AuthActionResult.cancelled();
        }
        return AuthActionResult.success(user: _mapFirebaseUser(user));
      }

      final googleUser = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 40),
        onTimeout: () => null,
      );
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
    } on TimeoutException {
      debugPrint('[FirebaseAuthBackend] Google Sign-In zaman asimi / iptal.');
      return const AuthActionResult.cancelled();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request') {
        debugPrint('[FirebaseAuthBackend] Google popup kullanici tarafindan kapatildi.');
        return const AuthActionResult.cancelled();
      }
      return AuthActionResult.failure(
        errorCode: error.code,
        message: _mapFirebaseError(error.code),
      );
    } on PlatformException catch (error) {
      if (error.code == 'network_error' || error.code == 'sign_in_canceled') {
        return const AuthActionResult.cancelled();
      }
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
  Future<AuthActionResult> sendEmailVerification() async {
    await initialize();
    if (!_isConfigured) {
      return const AuthActionResult.failure(
        errorCode: 'not_configured',
        message: 'Firebase hesabı henüz yapılandırılmadı.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const AuthActionResult.failure(
        errorCode: 'no_user',
        message: 'Doğrulanacak aktif kullanıcı bulunamadı.',
      );
    }
    const continueUrls = <String>[
      'https://linereaderr.netlify.app/verified',
      'https://line-reader.pages.dev/verified',
    ];
    for (final url in continueUrls) {
      try {
        await user.sendEmailVerification(
          ActionCodeSettings(
            url: url,
            handleCodeInApp: false,
          ),
        );
        return const AuthActionResult.success(
          message: 'Doğrulama bağlantısı e-posta adresinize gönderildi.',
        );
      } catch (_) {}
    }

    // Authorized domains henüz eklenmediyse standart doğrulama maili gönder.
    try {
      await user.sendEmailVerification();
      return const AuthActionResult.success(
        message: 'Doğrulama bağlantısı e-posta adresinize gönderildi.',
      );
    } on FirebaseAuthException catch (error) {
      return AuthActionResult.failure(
        errorCode: error.code,
        message: _mapFirebaseError(error.code),
      );
    } catch (_) {
      return const AuthActionResult.failure(
        errorCode: 'verification_send_failed',
        message: 'Doğrulama e-postası gönderilemedi. Biraz sonra tekrar deneyin.',
      );
    }
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    await initialize();
    if (!_isConfigured) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updateDisplayName(displayName.trim());
        await user.reload();
      }
    } catch (_) {}
  }

  @override
  Future<AppAuthUser?> reloadCurrentUser() async {
    await initialize();
    if (!_isConfigured) return null;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      return refreshed == null ? null : _mapFirebaseUser(refreshed);
    } catch (_) {
      return currentUser;
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

    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      return const AuthActionResult.failure(
        errorCode: 'invalid-email',
        message: 'Lütfen geçerli bir e-posta adresi girin.',
      );
    }

    try {
      // 1) Öncelikle Cloudflare Worker + Resend üzerinden özel tasarımlı HTML şablonuyla göndermeyi dene
      final customSuccess = await _trySendCustomPasswordResetEmail(cleanEmail);
      if (customSuccess) {
        return const AuthActionResult.success(
          message: 'Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.',
        );
      }
    } catch (_) {}

    // 2) Yedek: Firebase Auth yerleşik e-posta gönderimi
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: cleanEmail);
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

  Future<bool> _trySendCustomPasswordResetEmail(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://linereader-ai.xreasayaz21.workers.dev/auth/password-reset'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'email': email,
              'lang': 'tr',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['ok'] == true) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (!_isConfigured) return null;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken(forceRefresh);
    } catch (error) {
      debugPrint('[FirebaseAuthBackend] ID token alma hatasi: $error');
      return null;
    }
  }

  @override
  Future<List<String>> fetchSignInMethodsForEmail(String email) async {
    if (!_isConfigured) return const <String>[];
    try {
      final methods = await FirebaseAuth.instance
          .fetchSignInMethodsForEmail(email.trim().toLowerCase());
      return methods;
    } catch (error) {
      debugPrint('[FirebaseAuthBackend] fetchSignInMethodsForEmail hatasi: $error');
      return const <String>[];
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
        'Bu e-posta adresi e-posta ve şifre ile kayıtlıdır. Lütfen e-posta ve şifrenizle giriş yapın.',
      'popup-closed-by-user' ||
      'cancelled-popup-request' =>
        'Google giriş penceresi kapatıldı.',
      'popup-blocked' =>
        'Tarayıcı açılır pencereyi (pop-up) engelledi. Lütfen izin verip tekrar deneyin.',
      'unauthorized-domain' =>
        'Bu alan adı Firebase Yetkili Alan Adları listesinde henüz ekli değil.',
      _ => 'İşlem tamamlanamadı ($code).',
    };
  }
}
