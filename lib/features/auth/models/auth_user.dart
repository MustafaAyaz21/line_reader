/// Kullanıcının hangi yöntemle oturum açtığını belirtir.
enum AuthProviderType {
  google,
  email,
}

/// Uygulama oturum durumu.
enum AuthSessionStatus {
  /// İlk yükleme sürüyor.
  loading,

  /// Henüz giriş yapılmadı ve misafir devamı seçilmedi.
  unauthenticated,

  /// Misafir modu aktif (günlük 40 kelime çeviri hakkı).
  guest,

  /// Gmail (Google) veya E-posta hesabı ile giriş yapılmış (sınırsız çeviri).
  authenticated,
}

/// Oturum açmış kullanıcı profil bilgisi.
class AppAuthUser {
  const AppAuthUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    required this.provider,
    this.emailVerified = true,
  });

  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final AuthProviderType provider;
  final bool emailVerified;

  String get effectiveName {
    final name = displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final atIndex = email.indexOf('@');
    return atIndex > 0 ? email.substring(0, atIndex) : email;
  }

  AppAuthUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    AuthProviderType? provider,
    bool? emailVerified,
  }) {
    return AppAuthUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      provider: provider ?? this.provider,
      emailVerified: emailVerified ?? this.emailVerified,
    );
  }
}

/// Kimlik doğrulama işlemi sonucu.
class AuthActionResult {
  const AuthActionResult.success({this.user, this.message})
      : isSuccess = true,
        isCancelled = false,
        errorCode = null;

  const AuthActionResult.cancelled()
      : isSuccess = false,
        isCancelled = true,
        user = null,
        errorCode = 'cancelled',
        message = null;

  const AuthActionResult.failure({
    required this.message,
    this.errorCode,
  })  : isSuccess = false,
        isCancelled = false,
        user = null;

  final bool isSuccess;
  final bool isCancelled;
  final AppAuthUser? user;
  final String? errorCode;
  final String? message;
}
