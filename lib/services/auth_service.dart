import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// The authentication provider used by the application.
///
/// Keep this switch in one place. Supabase is the production path; changing
/// it to [AuthBackend.firebase] re-enables the legacy Firebase Auth path
/// without requiring edits across the application.
enum AuthBackend { supabase, firebase }

class AppAuthUser {
  const AppAuthUser({required this.uid, required this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;
}

class AppAuthException implements Exception {
  const AppAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class AppAuthService {
  AppAuthService._();

  static final AppAuthService _instance = AppAuthService._();
  Stream<AppAuthUser?>? _cachedAuthStateChanges;

  /// While the login screen is still validating a new session (Google
  /// signup, workshop join, membership lookup), the provider's raw sign-in
  /// event must not switch the root gate to the application. Doing so
  /// disposed the login screen mid-flow and let the subscription gate delete
  /// the not-yet-linked account as an orphan.
  int _interactiveSignInDepth = 0;

  void beginInteractiveSignIn() => _interactiveSignInDepth++;

  /// Releases the hold. A session that survived the flow is published; a
  /// failed flow has already signed out, so nothing is emitted.
  void endInteractiveSignIn() {
    if (_interactiveSignInDepth > 0) _interactiveSignInDepth--;
    if (_interactiveSignInDepth == 0 && currentUser != null) {
      publishCurrentSession();
    }
  }
  final StreamController<AppAuthUser?> _authStateController =
      StreamController<AppAuthUser?>.broadcast(sync: true);

  factory AppAuthService() => _instance;

  /// Single switch for the authentication backend.
  static const AuthBackend backend = AuthBackend.supabase;

  supabase.GoTrueClient get _supabaseAuth =>
      supabase.Supabase.instance.client.auth;

  firebase.FirebaseAuth get _firebaseAuth => firebase.FirebaseAuth.instance;

  bool get usesSupabase => backend == AuthBackend.supabase;

  AppAuthUser? get currentUser {
    if (usesSupabase) {
      final user = _fromSupabaseUser(_supabaseAuth.currentUser);
      // Once Supabase has no current session, never expose a stale user to
      // guards such as SubscriptionChecker. Doing so leaves the signed-out
      // app on a white "you must log in" page instead of LoginScreen.
      return user;
    }
    return _fromFirebaseUser(_firebaseAuth.currentUser);
  }

  Stream<AppAuthUser?> get authStateChanges {
    // Keep one stable broadcast stream and own the bridge to the provider.
    // This lets signOut emit null synchronously, even if the provider's event
    // is delayed or a widget resubscribes while the event is in flight.
    if (_cachedAuthStateChanges != null) return _cachedAuthStateChanges!;
    if (usesSupabase) {
      _supabaseAuth.onAuthStateChange.listen((state) {
        final user = _fromSupabaseUser(state.session?.user);
        if (user != null && _interactiveSignInDepth > 0) return;
        _authStateController.add(user);
      });
    } else {
      _firebaseAuth.authStateChanges().listen((user) {
        final appUser = _fromFirebaseUser(user);
        if (appUser != null && _interactiveSignInDepth > 0) return;
        _authStateController.add(appUser);
      });
    }
    // Replay the provider's current value to every new listener. Supabase can
    // restore (or replace) its local session between reading [currentUser]
    // above MaterialApp and StreamBuilder attaching to this stream. A plain
    // broadcast stream loses that event, leaving the login page visible until
    // the application is restarted.
    return _cachedAuthStateChanges = Stream<AppAuthUser?>.multi(
      (controller) {
        controller.add(currentUser);
        final subscription = _authStateController.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      },
      isBroadcast: true,
    );
  }

  /// Publishes an already validated session to the root authentication gate.
  ///
  /// LoginScreen calls this only after the user's workshop membership and
  /// local context have been loaded, so mobile and desktop transition without
  /// requiring an application restart.
  void publishCurrentSession() {
    _authStateController.add(currentUser);
  }

  Future<AppAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      if (usesSupabase) {
        final response = await _supabaseAuth
            .signInWithPassword(email: email.trim(), password: password)
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw const AppAuthException(
                'network-timeout',
                'انتهت مهلة الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت والمحاولة مرة أخرى.',
              ),
            );
        final user = _fromSupabaseUser(response.user);
        if (user == null) {
          throw const AppAuthException(
            'no-user',
            'تعذر الحصول على حساب Supabase بعد تسجيل الدخول.',
          );
        }
        return user;
      }

      final response = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = _fromFirebaseUser(response.user);
      if (user == null) {
        throw const AppAuthException(
          'no-user',
          'تعذر الحصول على حساب Firebase بعد تسجيل الدخول.',
        );
      }
      return user;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  Future<AppAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      if (usesSupabase) {
        final response = await _supabaseAuth.signUp(
          email: email.trim(),
          password: password,
        );
        final user = _fromSupabaseUser(response.user);
        if (user == null || _supabaseAuth.currentSession == null) {
          throw const AppAuthException(
            'email-not-confirmed',
            'تم إنشاء الحساب، لكن يجب تأكيد البريد الإلكتروني قبل الدخول.',
          );
        }
        return user;
      }

      final response = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = _fromFirebaseUser(response.user);
      if (user == null) {
        throw const AppAuthException(
          'no-user',
          'تعذر الحصول على حساب Firebase بعد إنشاء الحساب.',
        );
      }
      return user;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  Future<AppAuthUser> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    try {
      if (usesSupabase) {
        final response = await _supabaseAuth.signInWithIdToken(
          provider: supabase.OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );
        final user = _fromSupabaseUser(response.user);
        if (user == null) {
          throw const AppAuthException(
            'no-user',
            'تعذر تسجيل الدخول إلى Supabase بواسطة Google.',
          );
        }
        return user;
      }

      final credential = firebase.GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );
      final response = await _firebaseAuth.signInWithCredential(credential);
      final user = _fromFirebaseUser(response.user);
      if (user == null) {
        throw const AppAuthException(
          'no-user',
          'تعذر تسجيل الدخول إلى Firebase بواسطة Google.',
        );
      }
      return user;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final cleanEmail = email.trim();
    try {
      if (usesSupabase) {
        try {
          await _supabaseAuth.resetPasswordForEmail(cleanEmail);
          return;
        } catch (supabaseError) {
          // If Supabase fails (e.g. quota 402 or unconfigured emailer), try Firebase Auth as fallback.
          try {
            await _firebaseAuth.sendPasswordResetEmail(email: cleanEmail);
            return;
          } catch (_) {
            throw _normalizeError(supabaseError);
          }
        }
      } else {
        await _firebaseAuth.sendPasswordResetEmail(email: cleanEmail);
      }
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  /// Verifies an OTP recovery code and sets a new password.
  Future<void> verifyOtpAndResetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    final cleanEmail = email.trim();
    var cleanToken = token.trim();

    // Check if the input is a URL or fragment (from email link or browser address bar)
    String? extractedRefreshToken;
    if (cleanToken.startsWith('http://') ||
        cleanToken.startsWith('https://') ||
        cleanToken.contains('token=') ||
        cleanToken.contains('refresh_token=')) {
      try {
        final uri = Uri.parse(cleanToken);
        if (uri.queryParameters.containsKey('token')) {
          cleanToken = uri.queryParameters['token']!;
        } else if (uri.queryParameters.containsKey('code')) {
          cleanToken = uri.queryParameters['code']!;
        } else if (uri.queryParameters.containsKey('token_hash')) {
          cleanToken = uri.queryParameters['token_hash']!;
        }
        if (uri.fragment.isNotEmpty) {
          final fragmentParams = Uri.splitQueryString(uri.fragment);
          if (fragmentParams.containsKey('refresh_token')) {
            extractedRefreshToken = fragmentParams['refresh_token'];
          } else if (fragmentParams.containsKey('token')) {
            cleanToken = fragmentParams['token']!;
          } else if (fragmentParams.containsKey('code')) {
            cleanToken = fragmentParams['code']!;
          } else if (fragmentParams.containsKey('token_hash')) {
            cleanToken = fragmentParams['token_hash']!;
          }
        }
      } catch (_) {
        final tokenMatch = RegExp(r'[?&#](?:token|code|token_hash)=([^&]+)')
            .firstMatch(cleanToken);
        if (tokenMatch != null) {
          cleanToken = tokenMatch.group(1)!;
        }
        final refreshMatch =
            RegExp(r'[?&#]refresh_token=([^&]+)').firstMatch(cleanToken);
        if (refreshMatch != null) {
          extractedRefreshToken = refreshMatch.group(1);
        }
      }
    }

    try {
      if (usesSupabase) {
        try {
          if (extractedRefreshToken != null &&
              extractedRefreshToken.isNotEmpty) {
            await _supabaseAuth.setSession(extractedRefreshToken);
          } else {
            await _supabaseAuth.verifyOTP(
              email: cleanEmail,
              token: cleanToken,
              type: supabase.OtpType.recovery,
            );
          }
          if (_supabaseAuth.currentUser != null) {
            await _supabaseAuth.updateUser(
              supabase.UserAttributes(password: newPassword),
            );
            return;
          }
        } catch (supabaseError) {
          // Try Firebase confirm if token belongs to Firebase
          try {
            await _firebaseAuth.confirmPasswordReset(
              code: cleanToken,
              newPassword: newPassword,
            );
            return;
          } catch (_) {
            throw _normalizeError(supabaseError);
          }
        }
      } else {
        await _firebaseAuth.confirmPasswordReset(
          code: cleanToken,
          newPassword: newPassword,
        );
      }
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  /// Signs into the legacy Firebase account only for the one-time workshop
  /// migration. The production session remains Supabase after migration.
  Future<AppAuthUser> signInLegacyFirebaseWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      throw const AppAuthException(
        'not-supported',
        'Firebase غير مدعوم على هذه المنصة.',
      );
    }
    try {
      final response = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = _fromFirebaseUser(response.user);
      if (user == null) {
        throw const AppAuthException(
          'legacy-no-user',
          'تعذر العثور على حساب Firebase القديم.',
        );
      }
      return user;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  Future<AppAuthUser> signInLegacyFirebaseWithGoogleToken({
    required String idToken,
    String? accessToken,
  }) async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      throw const AppAuthException(
        'not-supported',
        'Firebase غير مدعوم على هذه المنصة.',
      );
    }
    try {
      final credential = firebase.GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );
      final response = await _firebaseAuth.signInWithCredential(credential);
      final user = _fromFirebaseUser(response.user);
      if (user == null) {
        throw const AppAuthException(
          'legacy-no-user',
          'تعذر العثور على حساب Google القديم في Firebase.',
        );
      }
      return user;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  Future<void> signOutLegacyFirebase() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) return;
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}
  }

  /// GoogleSignIn has no Windows implementation in this project. Supabase
  /// owns the Windows session, so do not call the mobile plugin there.
  Future<void> signOutGoogleSession() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) return;
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Signing out of Supabase/Firebase remains successful even when the
      // optional Google account cache cannot be cleared on a platform.
    }
  }

  Future<void> updateProfile({String? displayName}) async {
    final cleanName = displayName?.trim() ?? '';
    if (cleanName.isEmpty) return;
    if (usesSupabase) {
      await _supabaseAuth.updateUser(
        supabase.UserAttributes(data: {'full_name': cleanName}),
      );
    } else {
      await _firebaseAuth.currentUser?.updateDisplayName(cleanName);
    }
  }

  Future<void> signOut() async {
    // Switch the root auth gate to LoginScreen before network/plugin cleanup.
    // Supabase will emit the same value again when local sign-out completes;
    // duplicate null events are harmless and keep this path deterministic.
    _authStateController.add(null);
    if (usesSupabase) {
      // A global sign-out may wait on the network on Windows. The local
      // session is the one that controls this app's auth gate, so clear it
      // locally and let the auth-state stream switch to LoginScreen
      // immediately even when Supabase is temporarily unreachable.
      await _supabaseAuth.signOut(scope: supabase.SignOutScope.local);
      return;
    }
    await _firebaseAuth.signOut();
    await GoogleSignIn().signOut();
  }

  AppAuthUser? _fromSupabaseUser(supabase.User? user) {
    if (user == null) return null;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return AppAuthUser(
      uid: user.id,
      email: user.email,
      displayName:
          metadata['full_name']?.toString() ?? metadata['name']?.toString(),
    );
  }

  AppAuthUser? _fromFirebaseUser(firebase.User? user) {
    if (user == null) return null;
    return AppAuthUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
    );
  }

  Object _normalizeError(Object error) {
    if (error is AppAuthException) return error;

    // Preserve server status and transport details for accurate UI messages.
    if (error is supabase.AuthException) {
      final code = error.statusCode ?? 'auth-error';
      final msg = error.message.toLowerCase();
      if (code == '402' ||
          msg.contains('exceed_egress_quota') ||
          msg.contains('quota')) {
        return const AppAuthException(
          'quota-exceeded',
          'تم تجاوز حصة نقل البيانات في خادم السحابة (Supabase). يرجى فك الحظر أو ترقية الباقة لاستئناف الخدمة.',
        );
      }
      if (msg.contains('signups not allowed') ||
          msg.contains('signup is disabled') ||
          msg.contains('user signups are disabled')) {
        return const AppAuthException(
          'signup-disabled',
          'إنشاء الحسابات الجديدة متوقف في إعدادات Supabase. يجب تفعيل Allow new users to sign up من Authentication ثم المحاولة مجدداً.',
        );
      }
      if (msg.contains('token has expired') ||
          msg.contains('otp_expired') ||
          code == 'otp_expired') {
        return const AppAuthException(
          'otp-expired',
          'رمز التحقق منتهي الصلاحية، يرجى طلب رمز جديد.',
        );
      }
      if (msg.contains('invalid token') ||
          msg.contains('token is invalid') ||
          code.contains('invalid')) {
        return const AppAuthException(
          'invalid-otp',
          'رمز التحقق غير صحيح، يرجى التأكد من الرمز المدخل والمحاولة مجدداً.',
        );
      }
      return AppAuthException(code, error.message);
    }
    if (error is firebase.FirebaseAuthException) {
      final code = error.code.toLowerCase().trim();
      final msg = (error.message ?? '').toLowerCase();
      if (code == 'expired-action-code' || msg.contains('expired')) {
        return const AppAuthException(
          'otp-expired',
          'انتهت صلاحية رمز أو رابط التحقق، يرجى طلب رمز جديد.',
        );
      }
      if (code == 'invalid-action-code' || msg.contains('invalid')) {
        return const AppAuthException(
          'invalid-otp',
          'رمز أو كود التحقق غير صحيح، يرجى التأكد وإعادة المحاولة.',
        );
      }
      return AppAuthException(error.code, error.message ?? error.code);
    }
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('402') || errStr.contains('exceed_egress_quota')) {
      return const AppAuthException(
        'quota-exceeded',
        'تم تجاوز حصة نقل البيانات في خادم السحابة (Supabase). يرجى فك الحظر أو ترقية الباقة لاستئناف الخدمة.',
      );
    }
    return error;
  }
}
