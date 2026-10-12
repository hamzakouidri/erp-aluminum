import 'auth_service.dart' show AppAuthUser;

/// This fallback keeps web builds free of dart:io imports.
class WindowsGoogleAuthTokens {
  const WindowsGoogleAuthTokens({
    required this.idToken,
    this.accessToken,
  });

  final String idToken;
  final String? accessToken;
}

class WindowsGoogleSignInException implements Exception {
  const WindowsGoogleSignInException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}
class WindowsGoogleSignIn {
  const WindowsGoogleSignIn();

  static void cancelActiveSignIn() {}

  Future<WindowsGoogleAuthTokens> signIn() {
    throw const WindowsGoogleSignInException(
      'تسجيل الدخول عبر Google من Windows غير متاح على هذه المنصة.',
    );
  }

  Future<AppAuthUser> signInWithSupabase() {
    throw const WindowsGoogleSignInException(
      'تسجيل الدخول عبر Google من Windows غير متاح على هذه المنصة.',
    );
  }
}
