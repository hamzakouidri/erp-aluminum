/// This fallback keeps web builds free of dart:io imports.
class WindowsGoogleAuthTokens {
  const WindowsGoogleAuthTokens({
    required this.idToken,
    required this.accessToken,
  });

  final String idToken;
  final String accessToken;
}

class WindowsGoogleSignInException implements Exception {
  const WindowsGoogleSignInException(this.userMessage);

  final String userMessage;
}

class WindowsGoogleSignIn {
  Future<WindowsGoogleAuthTokens> signIn() {
    throw const WindowsGoogleSignInException(
      'تسجيل الدخول عبر Google من Windows غير متاح على هذه المنصة.',
    );
  }
}
