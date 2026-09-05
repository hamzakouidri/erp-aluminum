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
  const AppAuthUser({
    required this.uid,
    required this.email,
    this.displayName,
  });

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

  factory AppAuthService() => _instance;

  /// Single switch for the authentication backend.
  static const AuthBackend backend = AuthBackend.supabase;

  supabase.GoTrueClient get _supabaseAuth =>
      supabase.Supabase.instance.client.auth;

  firebase.FirebaseAuth get _firebaseAuth => firebase.FirebaseAuth.instance;

  bool get usesSupabase => backend == AuthBackend.supabase;

  AppAuthUser? get currentUser {
    if (usesSupabase) {
      return _fromSupabaseUser(_supabaseAuth.currentUser);
    }
    return _fromFirebaseUser(_firebaseAuth.currentUser);
  }

  Stream<AppAuthUser?> get authStateChanges {
    if (usesSupabase) {
      return _supabaseAuth.onAuthStateChange.map(
        (state) => _fromSupabaseUser(state.session?.user),
      );
    }
    return _firebaseAuth.authStateChanges().map(_fromFirebaseUser);
  }

  Future<AppAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      if (usesSupabase) {
        final response = await _supabaseAuth.signInWithPassword(
          email: email.trim(),
          password: password,
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
    try {
      if (usesSupabase) {
        await _supabaseAuth.resetPasswordForEmail(email.trim());
      } else {
        await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
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

  Future<void> signOutLegacyFirebase() => _firebaseAuth.signOut();

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

    // Supabase can surface a transport failure as a plain ClientException,
    // SocketException, or TimeoutException instead of an AuthException.
    // Normalize those failures so the login screen can show a localized,
    // user-friendly offline message rather than the technical exception.
    final errorText = error.toString().toLowerCase();
    if (errorText.contains('socketexception') ||
        errorText.contains('failed host lookup') ||
        errorText.contains('connection refused') ||
        errorText.contains('connection reset') ||
        errorText.contains('connection closed') ||
        errorText.contains('network is unreachable') ||
        errorText.contains('network request failed') ||
        errorText.contains('networkerror') ||
        errorText.contains('fetch failed') ||
        errorText.contains('failed to fetch') ||
        errorText.contains('xmlhttprequest error') ||
        errorText.contains('offline') ||
        errorText.contains('clientexception') ||
        errorText.contains('timed out') ||
        errorText.contains('timeout')) {
      return const AppAuthException(
        'network-request-failed',
        'التطبيق غير متصل بالإنترنت، يرجى فحص الإنترنت.',
      );
    }
    if (error is supabase.AuthException) {
      return AppAuthException(error.statusCode ?? 'auth-error', error.message);
    }
    if (error is firebase.FirebaseAuthException) {
      return AppAuthException(error.code, error.message ?? error.code);
    }
    return error;
  }
}
