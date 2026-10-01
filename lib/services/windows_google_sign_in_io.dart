import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart' show AppAuthUser;

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

/// Helper to reliably launch URLs on Windows without shell argument escaping
/// bugs or unwanted Windows Explorer folder popups.
Future<bool> openWindowsBrowserUrl(String url) async {
  // 1. Primary: PowerShell Start-Process with explicit single quotes.
  // This guarantees special query parameters like &, =, ?, # are never treated
  // as shell operators or environment variables.
  try {
    final safeUrl = url.replaceAll("'", "''");
    final psResult = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      "Start-Process -FilePath '$safeUrl'",
    ]);
    if (psResult.exitCode == 0) return true;
  } catch (_) {}

  // 2. Secondary: rundll32 FileProtocolHandler
  try {
    final fallback = await Process.run('rundll32.exe', [
      'url.dll,FileProtocolHandler',
      url,
    ]);
    if (fallback.exitCode == 0) return true;
  } catch (_) {}

  // 3. Fallback: cmd /c start
  try {
    final escaped = url.replaceAll('&', '^&');
    final result = await Process.run('cmd.exe', ['/c', 'start', '', escaped]);
    if (result.exitCode == 0) return true;
  } catch (_) {}

  // 4. Fallback: url_launcher
  try {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {}

  return false;
}

/// Browser-based Google OAuth for the Windows desktop application.
///
/// Google account selection is performed by the user's default browser. The
/// callback is accepted only from a temporary loopback server.
class WindowsGoogleSignIn {
  const WindowsGoogleSignIn();

  static const _desktopClientId = String.fromEnvironment(
    'GOOGLE_WINDOWS_OAUTH_CLIENT_ID',
    defaultValue:
        '538203167181-3jmaiq8p7lkhveoptno2h9r94pvs0c1q.apps.googleusercontent.com',
  );

  static const _desktopClientSecret = String.fromEnvironment(
    'GOOGLE_WINDOWS_OAUTH_CLIENT_SECRET',
    defaultValue: '',
  );

  static const _authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _callbackTimeout = Duration(minutes: 3);

  /// Signs in directly using Supabase OAuth on Windows.
  ///
  /// This leverages the Web Google OAuth client already registered and
  /// authorized in the Supabase backend project, avoiding any client-secret
  /// exposure or missing-secret errors on desktop.
  Future<AppAuthUser> signInWithSupabase() async {
    HttpServer? callbackServer;
    try {
      callbackServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );

      final redirectUri =
          'http://127.0.0.1:${callbackServer.port}/google-oauth-callback';

      final authClient = supabase.Supabase.instance.client.auth;
      final oauthRes = await authClient.getOAuthSignInUrl(
        provider: supabase.OAuthProvider.google,
        redirectTo: redirectUri,
      );

      final opened = await openWindowsBrowserUrl(oauthRes.url);
      if (!opened) {
        throw const WindowsGoogleSignInException(
          'تعذر فتح المتصفح لتسجيل الدخول عبر Google.',
        );
      }

      final completer = Completer<AppAuthUser>();

      callbackServer.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (path == '/favicon.ico') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (path == '/google-oauth-callback') {
          final code = request.uri.queryParameters['code'];
          final error = request.uri.queryParameters['error'];
          final errorDescription =
              request.uri.queryParameters['error_description'];

          if (error != null) {
            await _finishHtmlResponse(
              request,
              success: false,
              message: errorDescription ?? 'تم إلغاء تسجيل الدخول.',
            );
            if (!completer.isCompleted) {
              completer.completeError(
                WindowsGoogleSignInException(
                  error == 'access_denied'
                      ? 'تم إلغاء تسجيل الدخول.'
                      : (errorDescription ?? 'تعذر تسجيل الدخول عبر Google.'),
                ),
              );
            }
            return;
          }

          if (code != null && code.isNotEmpty) {
            try {
              await authClient.exchangeCodeForSession(code);
              final user = authClient.currentUser;
              if (user != null) {
                await _finishHtmlResponse(request, success: true);
                if (!completer.isCompleted) {
                  completer.complete(
                    AppAuthUser(
                      uid: user.id,
                      email: user.email,
                      displayName: user.userMetadata?['full_name'] as String? ??
                          user.userMetadata?['name'] as String?,
                    ),
                  );
                }
                return;
              }
            } catch (e) {
              debugPrint('Code exchange direct error: $e');
            }
          }

          // Return an HTML page that reads either URL fragment (#) or search (?)
          // and forwards to /complete-auth
          request.response.headers.contentType = ContentType.html;
          request.response.write('''<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>تسجيل الدخول</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0F2027; color: #fff; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .box { background: #1B2C34; padding: 36px 40px; border-radius: 16px; border: 1px solid rgba(255,255,255,0.1); text-align: center; max-width: 420px; box-shadow: 0 8px 32px rgba(0,0,0,0.4); }
    h2 { margin-top: 0; color: #64B5F6; font-size: 22px; }
    p { color: #CFD8DC; font-size: 15px; line-height: 1.6; }
    .spinner { border: 3px solid rgba(255,255,255,0.1); border-top: 3px solid #64B5F6; border-radius: 50%; width: 36px; height: 36px; animation: spin 1s linear infinite; margin: 0 auto 20px; }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="box" id="box">
    <div class="spinner" id="spinner"></div>
    <h2 id="title">جاري استكمال تسجيل الدخول...</h2>
    <p id="msg">يرجى الانتظار لحظات للتحقق من حسابك.</p>
  </div>
  <script>
    const hash = window.location.hash;
    const search = window.location.search;
    const payload = hash ? ('?' + hash.substring(1)) : search;
    fetch('/complete-auth' + payload)
      .then(res => res.json())
      .then(data => {
        document.getElementById('spinner').style.display = 'none';
        if (data.success) {
          document.getElementById('title').style.color = '#81C784';
          document.getElementById('title').innerText = 'تم تسجيل الدخول بنجاح!';
          document.getElementById('msg').innerText = 'يمكنك الآن العودة إلى التطبيق، وإغلاق هذه الصفحة.';
          setTimeout(() => { try { window.close(); } catch(e){} }, 2000);
        } else {
          document.getElementById('title').style.color = '#E57373';
          document.getElementById('title').innerText = 'لم يكتمل تسجيل الدخول';
          document.getElementById('msg').innerText = data.error || 'حدث خطأ غير متوقع.';
        }
      })
      .catch(() => {
        document.getElementById('spinner').style.display = 'none';
        document.getElementById('title').style.color = '#E57373';
        document.getElementById('title').innerText = 'تعذر الاتصال بالتطبيق';
        document.getElementById('msg').innerText = 'يرجى المحاولة مجدداً من التطبيق.';
      });
  </script>
</body>
</html>''');
          await request.response.close();
          return;
        }

        if (path == '/complete-auth') {
          final q = request.uri.queryParameters;
          final error = q['error'];
          final errorDescription = q['error_description'];
          final code = q['code'];
          final refreshToken = q['refresh_token'];
          final accessToken = q['access_token'];

          request.response.headers.contentType = ContentType.json;

          if (error != null) {
            request.response.write(
              jsonEncode({'success': false, 'error': errorDescription ?? error}),
            );
            await request.response.close();
            if (!completer.isCompleted) {
              completer.completeError(
                WindowsGoogleSignInException(
                  errorDescription ?? 'تعذر تسجيل الدخول عبر Google.',
                ),
              );
            }
            return;
          }

          try {
            if (code != null && code.isNotEmpty) {
              await authClient.exchangeCodeForSession(code);
            } else if (refreshToken != null && refreshToken.isNotEmpty) {
              await authClient.setSession(
                refreshToken,
                accessToken: accessToken,
              );
            } else {
              await authClient.getSessionFromUrl(request.uri);
            }

            final user = authClient.currentUser;
            if (user != null) {
              request.response.write(jsonEncode({'success': true}));
              await request.response.close();
              if (!completer.isCompleted) {
                completer.complete(
                  AppAuthUser(
                    uid: user.id,
                    email: user.email,
                    displayName: user.userMetadata?['full_name'] as String? ??
                        user.userMetadata?['name'] as String?,
                  ),
                );
              }
              return;
            }
          } catch (e) {
            debugPrint('Failed to set Supabase session on Windows: $e');
            request.response.write(
              jsonEncode({'success': false, 'error': e.toString()}),
            );
            await request.response.close();
            if (!completer.isCompleted) {
              completer.completeError(
                const WindowsGoogleSignInException(
                  'تعذر حفظ جلسة الدخول في التطبيق.',
                ),
              );
            }
            return;
          }

          request.response.write(
            jsonEncode({'success': false, 'error': 'لم يتم العثور على بيانات الجلسة.'}),
          );
          await request.response.close();
          if (!completer.isCompleted) {
            completer.completeError(
              const WindowsGoogleSignInException('لم يتم استلام بيانات الجلسة.'),
            );
          }
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      return await completer.future.timeout(_callbackTimeout);
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
    } catch (e) {
      if (e is WindowsGoogleSignInException) rethrow;
      debugPrint('Windows Supabase Google SignIn error: $e');
      throw const WindowsGoogleSignInException(
        'حدث خطأ أثناء تسجيل الدخول عبر Google. حاول مرة أخرى.',
      );
    } finally {
      if (callbackServer != null) {
        await callbackServer.close(force: true);
      }
    }
  }

  /// Direct PKCE OAuth flow with Google token endpoint.
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
          'prompt': 'select_account',
        },
      );

      final opened = await openWindowsBrowserUrl(authorizationUri.toString());
      if (!opened) {
        throw const WindowsGoogleSignInException(
          'تعذر فتح المتصفح لتسجيل الدخول عبر Google.',
        );
      }

      HttpRequest? request;
      String? authorizationCode;
      String? receivedState;
      String? oauthError;

      await for (final req in callbackServer.timeout(_callbackTimeout)) {
        final path = req.uri.path;
        if (path == '/favicon.ico') {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          continue;
        }

        request = req;
        receivedState = req.uri.queryParameters['state'];
        authorizationCode = req.uri.queryParameters['code'];
        oauthError = req.uri.queryParameters['error'];
        break;
      }

      if (request == null) {
        throw const WindowsGoogleSignInException(
          'لم يتم استلام رد من المتصفح لتسجيل الدخول.',
        );
      }

      if (oauthError != null || authorizationCode == null) {
        await _finishHtmlResponse(request, success: false);
        if (oauthError == 'access_denied') {
          throw const WindowsGoogleSignInException('تم إلغاء تسجيل الدخول.');
        }
        throw const WindowsGoogleSignInException(
          'لم يكتمل تسجيل الدخول عبر Google. حاول مرة أخرى.',
        );
      }

      if (!_sameText(receivedState, state)) {
        await _finishHtmlResponse(request, success: false);
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
          if (_desktopClientSecret.isNotEmpty)
            'client_secret': _desktopClientSecret,
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
        await _finishHtmlResponse(
          request,
          success: false,
          message: userMessage,
        );
        throw WindowsGoogleSignInException(userMessage);
      }

      if (idToken == null || idToken.isEmpty) {
        await _finishHtmlResponse(request, success: false);
        throw const WindowsGoogleSignInException(
          'لم تُرجع Google بيانات الهوية المطلوبة لتسجيل الدخول. حاول مرة أخرى.',
        );
      }

      await _finishHtmlResponse(request, success: true);
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

  static Future<void> _finishHtmlResponse(
    HttpRequest request, {
    required bool success,
    String? message,
  }) async {
    request.response.headers.contentType = ContentType.html;
    final text = message ??
        (success
            ? 'يمكنك الآن العودة إلى التطبيق، وإغلاق هذه الصفحة.'
            : 'أغلق هذه الصفحة وحاول من التطبيق مرة أخرى.');
    final title = success ? 'تم تسجيل الدخول بنجاح!' : 'لم يكتمل تسجيل الدخول';
    final titleColor = success ? '#81C784' : '#E57373';
    request.response.write('''<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>$title</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0F2027; color: #fff; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .box { background: #1B2C34; padding: 36px 40px; border-radius: 16px; border: 1px solid rgba(255,255,255,0.1); text-align: center; max-width: 420px; box-shadow: 0 8px 32px rgba(0,0,0,0.4); }
    h2 { margin-top: 0; color: $titleColor; font-size: 22px; }
    p { color: #CFD8DC; font-size: 15px; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="box">
    <h2>$title</h2>
    <p>$text</p>
  </div>
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
