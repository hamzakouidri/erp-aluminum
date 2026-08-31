import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Google tokens returned by the Windows browser sign-in flow.
class WindowsGoogleAuthTokens {
  const WindowsGoogleAuthTokens({
    required this.idToken,
    this.accessToken,
  });

  final String idToken;
  final String? accessToken;
}

/// A safe, localized error that can be shown on the login screen.
class WindowsGoogleSignInException implements Exception {
  const WindowsGoogleSignInException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

/// Browser-based Google OAuth for the Windows desktop application.
///
/// Google account selection is performed by the user's default browser. The
/// callback is accepted only from a temporary loopback server, is protected by
/// a one-time state value and uses PKCE for the authorization-code exchange.
class WindowsGoogleSignIn {
  const WindowsGoogleSignIn();

  /// Set this at build time from the Google Cloud OAuth client of type
  /// "Desktop app". A Web or Android OAuth client must not be used here.
  /// A build-time value still takes precedence, allowing a different Windows
  /// OAuth client to be used for a separate release environment.
  static const _desktopClientId = String.fromEnvironment(
    'GOOGLE_WINDOWS_OAUTH_CLIENT_ID',
    defaultValue:
        '538203167181-3jmaiq8p7lkhveoptno2h9r94pvs0c1q.apps.googleusercontent.com',
  );

  static const _authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _callbackTimeout = Duration(minutes: 3);

  Future<WindowsGoogleAuthTokens> signIn() async {
    if (_desktopClientId.isEmpty) {
      throw const WindowsGoogleSignInException(
        'لم يُجهّز تسجيل Google لنسخة Windows بعد. أضف معرّف OAuth من نوع '
        'Desktop app عند بناء نسخة الكمبيوتر.',
      );
    }

    HttpServer? callbackServer;
    try {
      callbackServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );

      final state = _randomUrlSafeValue();
      final codeVerifier = _randomUrlSafeValue(length: 64);
      final codeChallenge = _base64UrlNoPadding(
        sha256.convert(ascii.encode(codeVerifier)).bytes,
      );
      final redirectUri = Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: callbackServer.port,
        path: '/google-oauth-callback',
      );
      final authorizationUri = Uri.parse(_authorizationEndpoint).replace(
        queryParameters: {
          'client_id': _desktopClientId,
          'redirect_uri': redirectUri.toString(),
          'response_type': 'code',
          'scope': 'openid email profile',
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          // Always show the Google account chooser in the browser.
          'prompt': 'select_account',
        },
      );

      final opened = await launchUrl(
        authorizationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const WindowsGoogleSignInException(
          'تعذر فتح المتصفح لتسجيل الدخول عبر Google.',
        );
      }

      final request = await callbackServer.first.timeout(_callbackTimeout);
      final callback = request.uri;
      final receivedState = callback.queryParameters['state'];
      final authorizationCode = callback.queryParameters['code'];
      final oauthError = callback.queryParameters['error'];

      if (oauthError != null || authorizationCode == null) {
        await _finishBrowserResponse(request, success: false);
        if (oauthError == 'access_denied') {
          throw const WindowsGoogleSignInException('تم إلغاء تسجيل الدخول.');
        }
        throw const WindowsGoogleSignInException(
          'لم يكتمل تسجيل الدخول عبر Google. حاول مرة أخرى.',
        );
      }

      if (!_sameText(receivedState, state)) {
        await _finishBrowserResponse(request, success: false);
        throw const WindowsGoogleSignInException(
          'تعذر التحقق من جلسة تسجيل الدخول. حاول مرة أخرى.',
        );
      }

      final tokenResponse = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'client_id': _desktopClientId,
          'code': authorizationCode,
          'code_verifier': codeVerifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri.toString(),
        },
      ).timeout(const Duration(seconds: 30));

      final body = _readJson(tokenResponse.body);
      final idToken = body['id_token'] as String?;
      final accessToken = body['access_token'] as String?;
      if (tokenResponse.statusCode != 200) {
        final errorCode = body['error']?.toString().trim();
        final errorDescription = body['error_description']?.toString().trim();
        debugPrint(
          'Windows Google OAuth token exchange failed: '
          'HTTP ${tokenResponse.statusCode}, error=$errorCode, '
          'description=$errorDescription',
        );
        final userMessage = _tokenExchangeErrorMessage(errorCode);
        await _finishBrowserResponse(
          request,
          success: false,
          failureMessage: userMessage,
        );
        throw WindowsGoogleSignInException(userMessage);
      }

      // Supabase verifies the Google ID token. The access token is useful but
      // not required for the ID-token sign-in flow and can be absent in an
      // otherwise valid OpenID Connect response.
      if (idToken == null || idToken.isEmpty) {
        debugPrint(
          'Windows Google OAuth token exchange completed without an ID token.',
        );
        await _finishBrowserResponse(request, success: false);
        throw const WindowsGoogleSignInException(
          'لم تُرجع Google بيانات الهوية المطلوبة لتسجيل الدخول. حاول مرة أخرى.',
        );
      }

      await _finishBrowserResponse(request, success: true);
      return WindowsGoogleAuthTokens(
        idToken: idToken,
        accessToken: accessToken,
      );
    } on WindowsGoogleSignInException {
      rethrow;
    } on TimeoutException {
      throw const WindowsGoogleSignInException(
        'انتهت مهلة تسجيل الدخول. حاول مرة أخرى.',
      );
    } on SocketException {
      throw const WindowsGoogleSignInException(
        'تعذر الاتصال بـ Google. تحقق من الإنترنت ثم حاول مرة أخرى.',
      );
    } catch (_) {
      throw const WindowsGoogleSignInException(
        'حدث خطأ أثناء تسجيل الدخول عبر Google. حاول مرة أخرى.',
      );
    } finally {
      if (callbackServer != null) {
        await callbackServer.close(force: true);
      }
    }
  }

  static Map<String, dynamic> _readJson(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _tokenExchangeErrorMessage(String? errorCode) {
    switch (errorCode) {
      case 'invalid_client':
        return 'إعداد تطبيق Windows في Google غير صحيح. تحقق من معرّف تطبيق الكمبيوتر ثم أعد تشغيل التطبيق.';
      case 'redirect_uri_mismatch':
        return 'إعداد عنوان العودة لتسجيل Google غير متوافق. أعد تشغيل التطبيق ثم حاول مرة أخرى.';
      case 'invalid_grant':
        return 'انتهت صلاحية رمز تسجيل Google قبل التحقق. أعد المحاولة واضغط الدخول مرة واحدة فقط.';
      case 'unauthorized_client':
        return 'رفضت Google عميل Windows. تحقق أن نوع عميل OAuth هو (Desktop app)، ثم أعد تشغيل التطبيق.';
      case 'invalid_request':
        return 'رفضت Google طلب التحقق الخاص بنسخة Windows. أغلق التطبيق كلياً وأعد تشغيله ثم حاول مرة واحدة.';
      default:
        final safeCode = errorCode == null || errorCode.isEmpty
            ? 'unknown'
            : errorCode;
        return 'تعذر إتمام التحقق من Google (OAuth: $safeCode).';
    }
  }

  static Future<void> _finishBrowserResponse(
    HttpRequest request, {
    required bool success,
    String? failureMessage,
  }) async {
    request.response.headers.contentType = ContentType.html;
    final message = success
        ? 'يمكنك العودة إلى التطبيق الآن.'
        : (failureMessage ?? 'أغلق هذه الصفحة وحاول من التطبيق مرة أخرى.');
    request.response.write('''
<!doctype html>
<html lang="ar" dir="rtl">
  <head><meta charset="utf-8"><title>تسجيل الدخول</title></head>
  <body style="font-family: sans-serif; padding: 2rem; text-align: center;">
    <h2>${success ? 'تم تسجيل الدخول بنجاح' : 'لم يكتمل تسجيل الدخول'}</h2>
    <p>$message</p>
  </body>
</html>''');
    await request.response.close();
  }

  static String _randomUrlSafeValue({int length = 32}) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return _base64UrlNoPadding(bytes);
  }

  static String _base64UrlNoPadding(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static bool _sameText(String? first, String second) {
    if (first == null || first.length != second.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
    }
    return difference == 0;
  }
}
