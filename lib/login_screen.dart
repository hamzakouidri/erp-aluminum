import 'package:database_data/widgets/app_material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/auth_connection_error.dart';
import 'package:database_data/services/supabase_account_service.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/services/legacy_workshop_migration_service.dart';
import 'package:database_data/services/windows_google_sign_in.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'settings/app_settings.dart';
import 'settings/localization.dart';
import 'widgets/password_reset_dialog.dart';

// Explicitly provide the OAuth web client used to request the Google ID
// token. This avoids relying on a generated Android resource, which can be
// missing or stale after a Gradle clean and causes DEVELOPER_ERROR.
const _googleServerClientId =
    '538203167181-18nhgclrpei204tcop0ih09g6pnoc465.apps.googleusercontent.com';

int _readWorkshopMaxUsers(Map<String, dynamic> workshopData) {
  final hasNewLimit = workshopData['maxUsers'] != null;
  final raw = hasNewLimit
      ? workshopData['maxUsers']
      : workshopData['maxWorkers'];
  if (raw == null) return 4; // Legacy default: 3 workers + the manager.
  final parsed = raw is num ? raw.toInt() : int.tryParse(raw.toString()) ?? 4;
  if (parsed == 999) return 999;
  if (hasNewLimit) return parsed.clamp(0, 999).toInt();
  // Keep the meaning of old maxWorkers values when reading old workshops.
  return (parsed + 1).clamp(0, 999).toInt();
}

bool _isWorkshopUser(Map<String, dynamic> data) {
  final role = data['role']?.toString().toLowerCase();
  return role == 'owner' ||
      role == 'manager' ||
      role == 'worker' ||
      role == 'co_manager' ||
      role == 'admin';
}

class _GoogleSignupDetails {
  const _GoogleSignupDetails({
    required this.name,
    required this.workshopName,
    required this.workshopCode,
    required this.isWorker,
  });

  final String name;
  final String workshopName;
  final String workshopCode;
  final bool isWorker;
}

class _GoogleSignupDetailsDialog extends StatefulWidget {
  const _GoogleSignupDetailsDialog({
    required this.language,
    required this.initialName,
    required this.initialWorkshopName,
    required this.initialWorkshopCode,
    required this.initialIsWorker,
  });

  final AppLanguage language;
  final String initialName;
  final String initialWorkshopName;
  final String initialWorkshopCode;
  final bool initialIsWorker;

  @override
  State<_GoogleSignupDetailsDialog> createState() =>
      _GoogleSignupDetailsDialogState();
}

class _GoogleSignupDetailsDialogState
    extends State<_GoogleSignupDetailsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _workshopNameController;
  late final TextEditingController _workshopCodeController;
  late bool _isWorker;
  String _validationMessage = '';

  String _t(String key) => Localization.translate(key, widget.language);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _workshopNameController = TextEditingController(
      text: widget.initialWorkshopName,
    );
    _workshopCodeController = TextEditingController(
      text: widget.initialWorkshopCode,
    );
    _isWorker = widget.initialIsWorker;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _workshopNameController.dispose();
    _workshopCodeController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final workshopValue = _isWorker
        ? _workshopCodeController.text.trim()
        : _workshopNameController.text.trim();
    if (name.isEmpty || workshopValue.isEmpty) {
      setState(() {
        _validationMessage = name.isEmpty
            ? _t('أدخل الاسم الكامل.')
            : _isWorker
            ? _t('أدخل كود الورشة.')
            : _t('أدخل اسم الورشة.');
      });
      return;
    }

    Navigator.pop(
      context,
      _GoogleSignupDetails(
        name: name,
        workshopName: _workshopNameController.text.trim(),
        workshopCode: _workshopCodeController.text.trim().toUpperCase(),
        isWorker: _isWorker,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('أكمل بيانات الحساب')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(_t('مدير ورشة')),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.engineering_outlined),
                    label: Text(_t('عامل')),
                  ),
                ],
                selected: {_isWorker},
                onSelectionChanged: (selection) => setState(() {
                  _isWorker = selection.first;
                  _validationMessage = '';
                }),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _t('الاسم الكامل'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _isWorker
                    ? _workshopCodeController
                    : _workshopNameController,
                textCapitalization: _isWorker
                    ? TextCapitalization.characters
                    : TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _isWorker
                      ? _t('كود الورشة')
                      : _t('اسم الورشة'),
                  prefixIcon: Icon(
                    _isWorker
                        ? Icons.key_outlined
                        : Icons.storefront_outlined,
                  ),
                ),
              ),
              if (_validationMessage.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _validationMessage,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_t('إلغاء')),
        ),
        FilledButton(onPressed: _submit, child: Text(_t('متابعة'))),
      ],
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _workshopNameController = TextEditingController();
  final _auth = AppAuthService();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;
  bool _isLoginMode = true;
  bool _isWorkerSignup = false;
  final _workshopCodeController = TextEditingController();
  final FocusNode _workshopNameFocusNode = FocusNode();
  final FocusNode _workshopCodeFocusNode = FocusNode();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  late AnimationController _animationController;
  late List<Particle> _particles;

  String _t(String key) =>
      Localization.translate(key, context.read<AppSettingsProvider>().language);

  String? _normalizeGmailAddress(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;
    if (!value.contains('@')) value = '$value@gmail.com';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) return null;
    return value;
  }

  String? _emailFromGoogleIdToken(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final email = payload['email']?.toString().trim().toLowerCase() ?? '';
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        return null;
      }
      return email;
    } catch (_) {
      return null;
    }
  }

  String _nameFromGoogleIdToken(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return '';
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return '';
      return (payload['name'] ?? payload['given_name'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  Future<bool> _collectGoogleSignupDetails({String suggestedName = ''}) async {
    final language = context.read<AppSettingsProvider>().language;
    final details = await showDialog<_GoogleSignupDetails>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GoogleSignupDetailsDialog(
        language: language,
        initialName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : suggestedName.trim(),
        initialWorkshopName: _workshopNameController.text.trim(),
        initialWorkshopCode: _workshopCodeController.text.trim(),
        initialIsWorker: _isWorkerSignup,
      ),
    );
    if (details == null || !mounted) return false;

    _nameController.text = details.name;
    _workshopNameController.text = details.workshopName;
    _workshopCodeController.text = details.workshopCode;
    setState(() => _isWorkerSignup = details.isWorker);
    return true;
  }

  bool _requireGmailAddress() {
    final normalized = _normalizeGmailAddress(_emailController.text);
    if (normalized == null) {
      setState(() {
        _errorMessage = 'يرجى إدخال بريد إلكتروني صحيح.';
        _isLoading = false;
      });
      return false;
    }
    _emailController.text = normalized;
    return true;
  }

  @override
  void initState() {
    super.initState();
    final rand = Random();
    _particles = List.generate(20, (index) {
      return Particle(
        x: rand.nextDouble(),
        y: rand.nextDouble(),
        speed: 0.001 + rand.nextDouble() * 0.003,
        size: 3.0 + rand.nextDouble() * 9.0,
        opacity: 0.05 + rand.nextDouble() * 0.15,
        angle: rand.nextDouble() * 2 * pi,
      );
    });

    // Repaint only the decorative layer. Rebuilding the complete login form
    // on every animation tick made text entry and scrolling janky on phones.
    _animationController =
        AnimationController(vsync: this, duration: const Duration(seconds: 15))
          ..repeat();
  }

  String _getFriendlyErrorMessage(Object e) {
    if (e.toString().contains('WORKSHOP_USER_LIMIT_REACHED')) {
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      return switch (lang) {
        AppLanguage.arabic =>
          'عذرًا، اكتمل عدد المستخدمين المسموح به لهذه الورشة. يُرجى التواصل مع مدير الورشة.',
        AppLanguage.french =>
          'Le nombre maximal d’utilisateurs autorisés pour cet atelier est atteint. Veuillez contacter le responsable de l’atelier.',
        AppLanguage.english =>
          'This workshop has reached its user limit. Please contact the workshop manager.',
      };
    }
    if (e is AppAuthException) {
      final code = e.code.toLowerCase().trim();
      final msg = e.message.toLowerCase();
      final connectionMessage = authConnectionErrorMessage(code, msg);
      if (connectionMessage != null) {
        return _t(connectionMessage);
      }
      if (code.contains('invalid') || msg.contains('invalid login')) {
        return _t(
          'بيانات الدخول غير صحيحة، يرجى التأكد من البريد وكلمة المرور.',
        );
      }
      if (code.contains('not-found') || msg.contains('not found')) {
        return _t('لم يتم العثور على حساب بهذا البريد، يرجى إنشاء حساب جديد.');
      }
      if (code.contains('already') || msg.contains('already registered')) {
        return _t('هذا البريد الإلكتروني مسجل لدينا بالفعل، جرب تسجيل الدخول.');
      }
      if (code.contains('confirmed') || msg.contains('confirm')) {
        return _t(
          'تم إنشاء الحساب. يرجى تأكيد البريد الإلكتروني ثم تسجيل الدخول.',
        );
      }
      if (code.contains('weak') || msg.contains('weak password')) {
        return _t('كلمة المرور ضعيفة جداً، يرجى استخدام 6 أحرف أو أكثر.');
      }
      return _t(e.message);
    }
    if (e is FirebaseAuthException) {
      final code = e.code.replaceAll('auth/', '').toLowerCase().trim();
      final msg = (e.message ?? '').toLowerCase();

      if (code == 'invalid-email' || msg.contains('invalid email')) {
        return _t('البريد الإلكتروني غير صالح، يرجى كتابته بشكل صحيح.');
      }
      if (code == 'user-disabled' || msg.contains('user disabled')) {
        return _t('تم تعطيل هذا الحساب من قبل الإدارة.');
      }
      if (code == 'user-not-found' || msg.contains('user not found')) {
        return _t(
          'لم يتم العثور على حساب بهذا البريد، يرجى التأكد أو إنشاء حساب جديد.',
        );
      }
      if (code == 'wrong-password' || msg.contains('wrong password')) {
        return _t('كلمة المرور غير صحيحة، يرجى المحاولة مرة أخرى.');
      }
      if (code == 'invalid-credential' ||
          code == 'invalid_login_credentials' ||
          msg.contains('invalid credential') ||
          msg.contains('invalid login credentials')) {
        return _t(
          'بيانات الدخول غير صحيحة، يرجى التأكد من البريد وكلمة المرور.',
        );
      }
      if (code == 'email-already-in-use' ||
          msg.contains('email already in use')) {
        return _t('هذا البريد الإلكتروني مسجل لدينا بالفعل، جرب تسجيل الدخول.');
      }
      if (code == 'weak-password' || msg.contains('weak password')) {
        return _t('كلمة المرور ضعيفة جداً، يرجى استخدام 6 أحرف أو أكثر.');
      }
      if (code == 'operation-not-allowed' ||
          msg.contains('operation not allowed')) {
        return _t(
          'طريقة تسجيل الدخول بالبريد غير مفعلة في Firebase Console. يرجى الذهاب إلى Authentication وتفعيل Email/Password.',
        );
      }
      final connectionMessage = authConnectionErrorMessage(code, msg);
      if (connectionMessage != null) {
        return _t(connectionMessage);
      }
      if (code == 'too-many-requests' || msg.contains('too many requests')) {
        return _t(
          'تمت محاولة الدخول عدة مرات بشكل خاطئ. يرجى الانتظار قليلاً ثم المحاولة.',
        );
      }
      if (code == 'internal-error' ||
          code == 'channel-error' ||
          msg.contains('internal error')) {
        return _t(
          'خطأ في خادم الفايربيس (An internal error has occurred).\n'
          'السبب الشائع: إما كلمة المرور غير صحيحة، أو خدمة Email/Password غير مفعلة في Firebase Console -> Authentication -> Get Started.',
        );
      }
      if (msg.contains('configuration not found')) {
        return _t(
          'إعدادات المصادقة غير موجودة: يرجى تفعيل البريد الإلكتروني (Email/Password) في Firebase Console.',
        );
      }
      return '${_t('حدث خطأ')}: ${e.message}';
    }
    final errorText = e.toString().toLowerCase();
    if (errorText.contains('account_not_registered_use_create_account')) {
      return _t(
        'هذا البريد غير مسجل. انتقل إلى إنشاء حساب وأكمل بيانات الورشة أولاً.',
      );
    }
    if (errorText.contains('workshop_invite_required')) {
      return _t(
        'هذا البريد غير مدعو إلى الورشة. اطلب من مدير الورشة إضافته أولاً.',
      );
    }
    if (errorText.contains('workshop_not_found')) {
      return _t('كود الورشة غير صحيح أو الورشة غير موجودة.');
    }
    if (errorText.contains('workshop_name_required')) {
      return _t('اسم الورشة مطلوب لإنشاء حساب المدير.');
    }
    if (errorText.contains('workshop_code_required')) {
      return _t('كود الورشة مطلوب لإنشاء حساب العامل.');
    }
    if (errorText.contains('person_name_required')) {
      return _t('الاسم الكامل مطلوب قبل إنشاء الحساب.');
    }
    if (errorText.contains('workshop_name_already_exists')) {
      return _t('اسم الورشة محجوز وموجود مسبقاً! يرجى اختيار اسم آخر فريد.');
    }
    if (errorText.contains('prepare_workshop_signup')) {
      return _t(
        'حماية إنشاء الحساب غير مفعلة على Supabase. طبّق ملف signup_admission_hook.sql أولاً.',
      );
    }
    if (errorText.contains('workshop name already exists') ||
        errorText.contains('name already exists')) {
      return _t('اسم الورشة محجوز وموجود مسبقاً! يرجى اختيار اسم آخر فريد.');
    }
    final connectionMessage = authConnectionErrorMessage('', errorText);
    if (connectionMessage != null) {
      return _t(connectionMessage);
    }
    return '${_t('حدث خطأ')}: $e';
  }

  void _resetPassword() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PasswordResetDialog(
        initialEmail: _emailController.text.trim(),
        onSuccess: (newPassword) {
          _passwordController.text = newPassword;
          _confirmPasswordController.text = newPassword;
          setState(() {
            _errorMessage = '';
          });
        },
      ),
    );
  }

  Future<void> _syncSupabasePasswordSession() async {
    // Supabase is now the authentication session itself. This method remains
    // as a small compatibility hook for older call sites.
    SupabaseWorkshopSyncService().start();
  }

  Future<void> _syncSupabaseGoogleSession({
    required String? idToken,
    required String? accessToken,
  }) async {
    if (idToken == null || idToken.trim().isEmpty) return;
    SupabaseWorkshopSyncService().start();
  }

  Future<void> _saveSupabaseAccountContext(
    SupabaseAccountSnapshot account,
  ) async {
    if (!_hasUsableWorkshopMembership(account)) {
      throw const AppAuthException(
        'account-not-configured',
        'هذا الحساب غير مرتبط بورشة صالحة.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    // Keep the person's account name separate from the workshop name. The
    // latter is used for document headers, while the former is used by
    // "Entered by" and "Modified by" fields.
    final signedInUser = AppAuthService().currentUser;
    final displayName = signedInUser?.displayName?.trim() ?? '';
    final email = signedInUser?.email?.trim() ?? account.email.trim();
    final accountDisplayName = displayName.isNotEmpty
        ? displayName
        : (email.contains('@') ? email.split('@').first.trim() : email);
    if (accountDisplayName.isNotEmpty) {
      await prefs.setString('user_display_name', accountDisplayName);
    }
    await prefs.setString('workshop_code', account.workshopCode);
    await prefs.setString('selected_supabase_workshop_id', account.workshopId);
    await prefs.setString(
      'supabase_workshop_uuid_${account.workshopCode}',
      account.workshopId,
    );
    final accountName = account.workshopName.trim();
    final accountCode = account.workshopCode.trim();
    if (accountName.isNotEmpty && accountName != accountCode) {
      await prefs.setString('workshop_name', accountName);
    } else if ((prefs.getString('workshop_name') ?? '').trim() == accountCode) {
      await prefs.remove('workshop_name');
    }
    await prefs.setString('user_role', account.role);
    await prefs.setString('permissions_json', jsonEncode(account.permissions));

    // Authentication and membership are already valid at this point. Move
    // the root UI immediately instead of making login wait for database sync;
    // a slow/failed sync used to leave the login page visible until restart
    // even though Supabase had persisted a valid session.
    _auth.publishCurrentSession();
    unawaited(
      CloudSyncService()
          .init()
          .then((_) => SupabaseWorkshopSyncService().start())
          .catchError((error) {
            debugPrint('Post-login synchronization startup failed: $error');
          }),
    );
  }

  bool _hasUsableWorkshopMembership(SupabaseAccountSnapshot? account) {
    if (account == null) return false;
    if (account.isApplicationAdminWorkspace) return true;
    return account.userId.trim().isNotEmpty &&
        account.workshopId.trim().isNotEmpty &&
        account.workshopCode.trim().isNotEmpty;
  }

  Future<bool> _rejectUnconfiguredAccount() async {
    var authRowDeleted = true;
    try {
      // The server RPC deletes only auth users that have no workshop
      // membership, so a valid account cannot be removed accidentally.
      await SupabaseAccountService().deleteCurrentUnconfiguredAuthUser();
    } catch (error) {
      authRowDeleted = false;
      debugPrint('Unconfigured account cleanup skipped: $error');
    }
    SupabaseAccountService().invalidateCurrentAccountCache();
    await CloudSyncService().clearCachedWorkshopContext();
    await _auth.signOut();
    return authRowDeleted;
  }

  /// Completes the one-time bridge after the old Firebase identity has been
  /// verified. Existing workshop codes stay unchanged, so all old members
  /// can be invited into the same Supabase workshop.
  Future<SupabaseAccountSnapshot> _completeLegacyWorkshopMigration(
    LegacyWorkshopContext legacy,
  ) async {
    final workshopSync = SupabaseWorkshopSyncService();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workshop_code', legacy.workshopCode);

    if (legacy.isManager) {
      // Read the backup before claiming the workshop so an older Firebase
      // installation that kept the display name only in its profile snapshot
      // can still provide the real name to Supabase.
      final legacyBackup = await CloudSyncService().readLegacyWorkshopBackup(
        legacy.legacyWorkshopId,
      );
      final migratedName = _legacyDisplayName(legacy, legacyBackup);
      if (migratedName.isNotEmpty && migratedName != legacy.workshopCode) {
        await prefs.setString('workshop_name', migratedName);
      } else {
        await prefs.remove('workshop_name');
      }

      await workshopSync.claimLegacyWorkshopOwner(
        code: legacy.workshopCode,
        name: migratedName,
        legacyOwnerEmail: legacy.email,
      );

      if (legacyBackup != null && legacyBackup.isNotEmpty) {
        await CloudSyncService().publishLegacyWorkshopBackup(legacyBackup);
        // The profile is metadata, not a business table, so persist its
        // display name explicitly for every device in the workshop.
        if (migratedName.isNotEmpty && migratedName != legacy.workshopCode) {
          await workshopSync.saveWorkshopProfile({
            'workshop_name': migratedName,
          });
        }
      } else {
        // Some old installations have only a complete local database and no
        // Firestore snapshot. Preserve that data by publishing the local
        // workshop after the claim; an empty local database is harmless.
        try {
          await workshopSync.uploadFullWorkshopData();
        } catch (error) {
          debugPrint('No local legacy workshop data to publish: $error');
        }
      }

      // Workers are migrated by email. If they do not yet have a Supabase
      // account, this creates a pending invite; their first login consumes it.
      for (final member in legacy.members) {
        try {
          await workshopSync.updateMemberPermissionsByEmail(
            email: member.email,
            role: member.role,
            permissions: {...member.permissions, 'isBlocked': member.blocked},
          );
        } catch (error) {
          debugPrint(
            'Legacy member invite skipped for ${member.email}: $error',
          );
        }
      }
    } else {
      // A worker can join only after the manager has claimed the workshop and
      // created the email invite. This prevents a worker from claiming a code.
      final ready = await workshopSync.ensureStarted(
        timeout: const Duration(seconds: 20),
      );
      if (!ready) {
        throw const AppAuthException(
          'legacy-worker-not-invited',
          'تم العثور على الحساب القديم، لكن لم تتم دعوته إلى الورشة بعد. يجب على المدير ترحيل الورشة أولاً.',
        );
      }
    }

    final account = await SupabaseAccountService().loadCurrentAccount();
    if (account == null) {
      throw const AppAuthException(
        'legacy-membership-not-created',
        'تم إنشاء حساب Supabase، لكن تعذر إنشاء عضوية الورشة القديمة.',
      );
    }
    await _saveSupabaseAccountContext(account);
    return account;
  }

  String _legacyDisplayName(
    LegacyWorkshopContext legacy,
    Map<String, dynamic>? backup,
  ) {
    String clean(dynamic value) => value?.toString().trim() ?? '';
    final direct = clean(legacy.workshopName);
    if (direct.isNotEmpty && direct != legacy.workshopCode) return direct;

    String? findNestedName(dynamic value) {
      if (value is Map) {
        for (final field in const [
          'workshop_name',
          'workshopName',
          'workshop_display_name',
        ]) {
          final candidate = clean(value[field]);
          if (candidate.isNotEmpty && candidate != legacy.workshopCode) {
            return candidate;
          }
        }
        for (final nested in value.values) {
          final candidate = findNestedName(nested);
          if (candidate != null) return candidate;
        }
      } else if (value is List) {
        for (final nested in value) {
          final candidate = findNestedName(nested);
          if (candidate != null) return candidate;
        }
      }
      return null;
    }

    if (backup != null) {
      for (final key in const [
        '__WorkshopProfile',
        'WorkshopProfile',
        'workshop_profile',
      ]) {
        final raw = backup[key];
        final rows = raw is List ? raw : [raw];
        for (final row in rows) {
          if (row is! Map) continue;
          for (final field in const [
            'workshop_name',
            'workshopName',
            'name',
            'title',
          ]) {
            final value = clean(row[field]);
            if (value.isNotEmpty && value != legacy.workshopCode) return value;
          }
        }
      }

      // Some very old backups wrapped the profile inside another object.
      // Walk only profile-name fields so a client or product name can never
      // be mistaken for the workshop name.
      final nestedName = findNestedName(backup);
      if (nestedName != null) return nestedName;
    }
    return '';
  }

  bool _isSyntheticApplicationAdminAccount(
    AppAuthUser user,
    SupabaseAccountSnapshot? account,
  ) {
    return account != null &&
        account.role == 'admin' &&
        account.workshopId == user.uid &&
        account.workshopCode == user.uid;
  }

  bool _needsWorkshopNameRepair(SupabaseAccountSnapshot account) {
    final name = account.workshopName.trim();
    final code = account.workshopCode.trim();
    return name.isEmpty || (code.isNotEmpty && name == code);
  }

  Future<AppAuthUser> _createOrSignInSupabasePasswordAccount({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (error) {
      // The account may already have been created by an earlier interrupted
      // migration. Reuse it instead of creating another identity.
      try {
        return await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<bool> _tryLegacyPasswordMigration() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return false;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    AppAuthUser? legacyUser;
    try {
      legacyUser = await _auth.signInLegacyFirebaseWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (_) {
      return false;
    }

    try {
      final legacy = await LegacyWorkshopMigrationService()
          .readCurrentUserContext();
      if (legacy == null) {
        await _auth.signOutLegacyFirebase();
        return false;
      }
      await SupabaseAccountService().prepareWorkshopSignup(
        email: email,
        personName: legacyUser.displayName?.trim().isNotEmpty == true
            ? legacyUser.displayName!.trim()
            : email.split('@').first,
        worker: !legacy.isManager,
        workshopName: legacy.workshopName,
        workshopCode: legacy.workshopCode,
      );
      await _createOrSignInSupabasePasswordAccount(
        email: email,
        password: password,
      );
      await _completeLegacyWorkshopMigration(legacy);
      await _auth.signOutLegacyFirebase();
      debugPrint(
        'Legacy password workshop migrated: ${legacy.workshopCode}, '
        'firebaseUid=${legacyUser.uid}',
      );
      return true;
    } catch (_) {
      await _auth.signOutLegacyFirebase();
      rethrow;
    }
  }

  Future<SupabaseAccountSnapshot?> _tryLegacyGoogleWorkshopMigration({
    required String idToken,
    String? accessToken,
  }) async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return null;
    }
    try {
      await _auth.signInLegacyFirebaseWithGoogleToken(
        idToken: idToken,
        accessToken: accessToken,
      );
      final legacy = await LegacyWorkshopMigrationService()
          .readCurrentUserContext();
      if (legacy == null) return null;
      return await _completeLegacyWorkshopMigration(legacy);
    } catch (error) {
      debugPrint('Legacy Google workshop migration skipped: $error');
      return null;
    } finally {
      await _auth.signOutLegacyFirebase();
    }
  }

  /// Keeps the root gate on this screen until the flow has finished
  /// validating (or rejecting) the new session. See
  /// [AppAuthService.beginInteractiveSignIn].
  Future<void> _withAuthHold(Future<void> Function() flow) async {
    _auth.beginInteractiveSignIn();
    try {
      await flow();
    } finally {
      _auth.endInteractiveSignIn();
    }
  }

  Future<void> _login() => _withAuthHold(_loginFlow);

  Future<void> _loginFlow() async {
    if (!_requireGmailAddress()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      // The login screen can be reached after another account signed out on
      // the same device. Clear the previous workshop identity before loading
      // the new user's membership; otherwise a cached code/UUID can win the
      // first sync cycle.
      await CloudSyncService().clearCachedWorkshopContext();
      AppAuthUser user;
      try {
        user = await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } catch (supabaseError) {
        // Old Firebase accounts are bridged once on mobile platforms.
        if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
          final migrated = await _tryLegacyPasswordMigration();
          if (migrated) return;
        }
        throw supabaseError;
      }
      var account = await SupabaseAccountService().loadCurrentAccount();
      if (account == null ||
          _isSyntheticApplicationAdminAccount(user, account)) {
        if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
          final migrated = await _tryLegacyPasswordMigration();
          if (migrated) return;
          account = await SupabaseAccountService().loadCurrentAccount();
        }
      }
      if (!_hasUsableWorkshopMembership(account)) {
        final authRowDeleted = await _rejectUnconfiguredAccount();
        if (!authRowDeleted) {
          throw const AppAuthException(
            'orphan-auth-delete-failed',
            'الحساب غير مرتبط بورشة، وتعذر حذفه من Supabase Authentication. يجب تطبيق ملف delete_orphan_auth_accounts.sql على Supabase.',
          );
        }
        throw const AppAuthException(
          'account-not-configured',
          'لا يمكن الدخول: هذا البريد غير مرتبط بأي ورشة. أنشئ ورشة أو اطلب دعوة صالحة من مدير الورشة.',
        );
      }
      var verifiedAccount = account!;
      if (verifiedAccount.role == 'admin' &&
          _needsWorkshopNameRepair(verifiedAccount)) {
        // Older migrations could transfer all business rows but miss the
        // workshop profile. Retry the legacy read once while the user has
        // supplied the old manager credentials, without blocking normal login
        // if the old Firebase account is no longer available.
        final repaired = await _tryLegacyPasswordMigration();
        if (repaired) {
          verifiedAccount =
              await SupabaseAccountService().loadCurrentAccount() ??
              verifiedAccount;
        }
      }
      if (verifiedAccount.blocked) {
        await _auth.signOut();
        throw const AppAuthException(
          'user-disabled',
          'عذراً، تم إيقاف هذا الحساب من قبل مدير الورشة.',
        );
      }

      await _saveSupabaseAccountContext(verifiedAccount);

      debugPrint(
        'LOGIN SYNC: uid=${user.uid}, '
        'workshopId=${CloudSyncService().workshopId}',
      );
      // Firebase auth state changes will handle transitioning the screen automatically
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getFriendlyErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _errorMessage = _getFriendlyErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  Future<void> _register() => _withAuthHold(_registerFlow);

  Future<void> _registerFlow() async {
    if (!_requireGmailAddress()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    var unconfiguredAuthUser = false;
    try {
      // Registration may follow a previous account on the same device.
      // Never let its cached workshop identity participate in this account's
      // first membership lookup.
      await CloudSyncService().clearCachedWorkshopContext();
      final workshopName = _workshopNameController.text.trim();
      final workshopCode =
          _workshopCodeController.text.trim().toUpperCase();
      final personName = _nameController.text.trim();
      if (personName.isEmpty) {
        throw const AppAuthException(
          'name-required',
          'يرجى إدخال الاسم الكامل.',
        );
      }
      if (!_isWorkerSignup && workshopName.isEmpty) {
        throw const AppAuthException(
          'workshop-name-required',
          'يرجى إدخال اسم المصنع أو الورشة.',
        );
      }
      if (_isWorkerSignup && workshopCode.isEmpty) {
        throw const AppAuthException(
          'workshop-code-required',
          'يرجى إدخال كود الورشة.',
        );
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        throw const AppAuthException(
          'password-mismatch',
          'كلمتا المرور غير متطابقتين. يرجى التأكد.',
        );
      }

      // Authorize this exact email before touching Supabase Auth. The
      // Before User Created hook consumes this short-lived permit; login
      // attempts never create one and therefore cannot create new users.
      await SupabaseAccountService().prepareWorkshopSignup(
        email: _emailController.text,
        personName: personName,
        worker: _isWorkerSignup,
        workshopName: workshopName,
        workshopCode: workshopCode,
      );

      final user = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      unconfiguredAuthUser = true;
      await _auth.updateProfile(
        displayName: personName,
      );

      final prefs = await SharedPreferences.getInstance();
      final code = _isWorkerSignup ? workshopCode : _generateJoinCode();
      await prefs.setString('workshop_code', code);
      if (!_isWorkerSignup) {
        await prefs.setString('workshop_name', workshopName);
        await SupabaseWorkshopSyncService().createWorkshopForCurrentUser(
          joinCode: code,
          workshopName: workshopName,
        );
      }
      final ready = await SupabaseWorkshopSyncService().ensureStarted(
        timeout: const Duration(seconds: 20),
      );
      if (!ready) {
        throw const AppAuthException(
          'workshop-not-configured',
          'تعذر ربط الحساب بالورشة. تأكد من كود الورشة أو من دعوة المدير.',
        );
      }
      final account = await SupabaseAccountService().loadCurrentAccount();
      if (!_hasUsableWorkshopMembership(account) ||
          account!.userId != user.uid) {
        throw const AppAuthException(
          'membership-not-created',
          'تم إنشاء الحساب، لكن لم يتم إنشاء عضوية الورشة.',
        );
      }
      final verifiedAccount = account!;
      await prefs.setString(
        'workshop_code',
        verifiedAccount.workshopCode,
      );
      await prefs.setString('workshop_name', verifiedAccount.workshopName);
      await prefs.setString('user_role', verifiedAccount.role);
      await prefs.setString(
        'permissions_json',
        jsonEncode(verifiedAccount.permissions),
      );
      unconfiguredAuthUser = false;
      SupabaseWorkshopSyncService().start();
      _auth.publishCurrentSession();
    } catch (error) {
      Object? authCleanupError;
      if (unconfiguredAuthUser) {
        try {
          await SupabaseAccountService().deleteCurrentUnconfiguredAuthUser();
        } catch (cleanupError) {
          authCleanupError = cleanupError;
          debugPrint('Unconfigured email account cleanup failed: $cleanupError');
        }
        try {
          await _auth.signOut();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _errorMessage = authCleanupError == null
              ? _getFriendlyErrorMessage(error)
              : 'فشل ربط الحساب بالورشة، وتعذر حذف البريد من Supabase Authentication. يجب تطبيق ملف delete_orphan_auth_accounts.sql على Supabase.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Legacy Firebase registration retained only as a rollback reference.
  Future<void> _registerLegacy() async {
    if (!_requireGmailAddress()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    if (!_isWorkerSignup && _workshopNameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال اسم المصنع أو الورشة.';
        _isLoading = false;
      });
      return;
    }

    if (_isWorkerSignup && _workshopCodeController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال كود الورشة.';
        _isLoading = false;
      });
      return;
    }

    // تفريغ حقول كلمة المرور عند عدم التطابق لتحسين تجربة المستخدم
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'كلمتا المرور غير متطابقتين. يرجى التأكد.';
        _passwordController.clear();
        _confirmPasswordController.clear();
        _isLoading = false;
      });
      return;
    }

    if (!_isWorkerSignup) {
      final isTaken = await _isWorkshopNameTaken(
        _workshopNameController.text.trim(),
      );
      if (isTaken) {
        setState(() {
          _errorMessage =
              'اسم الورشة محجوز وموجود مسبقاً! يرجى اختيار اسم آخر فريد.';
          _isLoading = false;
        });
        return;
      }
    }

    AppAuthUser? userCredential;
    bool isNewAuthUser = false;
    try {
      userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      isNewAuthUser = true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          userCredential = await _auth.signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
          await _auth.signOut();
          setState(() {
            _errorMessage =
                'هذا البريد الإلكتروني مسجل بالفعل. يرجى التوجه لتسجيل الدخول.';
            _isLoading = false;
          });
          return;
        } catch (signInErr) {
          setState(() {
            _errorMessage =
                'هذا الحساب موجود مسبقاً، ولكن كلمة المرور غير صحيحة لتفعيله من جديد.';
            _isLoading = false;
          });
          return;
        }
      } else {
        setState(() {
          _errorMessage = e.message ?? 'حدث خطأ في التسجيل';
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ: $e';
        _isLoading = false;
      });
      return;
    }

    String? targetWorkshopId;
    String? workshopNameForWorker;
    String? registrationWorkshopCode;

    if (_isWorkerSignup) {
      final code = _workshopCodeController.text.trim();
      registrationWorkshopCode = code;
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('workshops')
            .where('joinCode', isEqualTo: code)
            .limit(1)
            .get();

        if (querySnapshot.docs.isEmpty) {
          if (isNewAuthUser) {
            await _auth.signOut();
          } else {
            await _auth.signOut();
          }
          setState(() {
            _errorMessage = 'كود الورشة غير صحيح أو الورشة غير موجودة.';
            _isLoading = false;
          });
          return;
        }

        final workshopData =
            querySnapshot.docs.first.data() as Map<String, dynamic>? ?? {};
        targetWorkshopId = querySnapshot.docs.first.id;
        workshopNameForWorker = workshopData['name'] as String?;

        final maxUsers = _readWorkshopMaxUsers(workshopData);

        if (maxUsers != 999) {
          final workersSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('workshopId', isEqualTo: targetWorkshopId)
              .get();

          int currentUsers = 0;
          for (var doc in workersSnapshot.docs) {
            final d = doc.data() as Map<String, dynamic>? ?? {};
            if (_isWorkshopUser(d)) {
              currentUsers++;
            }
          }

          if (currentUsers >= maxUsers) {
            if (isNewAuthUser) {
              await _auth.signOut();
            } else {
              await _auth.signOut();
            }
            setState(() {
              _errorMessage =
                  'نعتذر، لقد وصلت هذه الورشة للحد الأقصى المسموح به من المستخدمين ($maxUsers). يرجى مراجعة مدير الورشة لترقية اشتراكه.';
              _isLoading = false;
            });
            return;
          }
        }
      } catch (e) {
        if (isNewAuthUser) {
          await _auth.signOut();
        } else {
          await _auth.signOut();
        }
        setState(() {
          _errorMessage = 'حدث خطأ أثناء التحقق من الكود: $e';
          _isLoading = false;
        });
        return;
      }
    }

    try {
      final uid = userCredential!.uid;

      String? logoUrl;
      if (!_isWorkerSignup) {
        final encodedName = Uri.encodeComponent(
          _workshopNameController.text.trim(),
        );
        logoUrl =
            'https://ui-avatars.com/api/?name=$encodedName&background=random&color=fff&size=256&font-size=0.4&bold=true';
      }

      if (_isWorkerSignup) {
        int currentUserCount = 0;
        try {
          final workersSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('workshopId', isEqualTo: targetWorkshopId)
              .get();
          currentUserCount = workersSnapshot.docs.where((doc) {
            return _isWorkshopUser(doc.data());
          }).length;
        } catch (_) {}

        final defaultPerms = {
          'view_clients': true,
          'create_clients': false,
          'view_orders': true,
          'create_orders': false,
          'view_client_details': true,
          'view_order_details': true,
          'view_my_tasks': true,
          'view_my_accreditations': true,
          'view_subscription': false,
          'isBlocked': false,
        };

        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': _emailController.text.trim(),
          'role': 'worker',
          'workshopId': targetWorkshopId,
          'workshopName': workshopNameForWorker,
          'displayName': _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : 'المستخدم رقم ${currentUserCount + 1}',
          'permissions': defaultPerms,
          'permissions_json': jsonEncode(defaultPerms),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        final joinCode = _generateJoinCode();
        registrationWorkshopCode = joinCode;
        // Create workshop doc
        await FirebaseFirestore.instance
            .collection('workshops')
            .doc(uid)
            .set({
              'name': _workshopNameController.text.trim(),
              'managerUid': uid,
              'joinCode': joinCode,
              'maxUsers': 4,
              'maxSystems': 999,
              'maxProfiles': 999,
              'createdAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 10));

        // Create user doc - تم الحفاظ على إعدادات التجربة كما طلبت (-1)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({
              'email': _emailController.text.trim(),
              'role': 'manager',
              'workshopId': uid,
              'workshopName': _workshopNameController.text.trim(),
              'displayName': _nameController.text.trim().isNotEmpty
                  ? _nameController.text.trim()
                  : 'مدير الورشة',
              'logoUrl': logoUrl,
              'joinCode': joinCode,
              'createdAt': FieldValue.serverTimestamp(),
              'trialEndDate': DateTime.now()
                  .add(const Duration(days: -1))
                  .toIso8601String(),
              'isTrialActive': false,
              'subscriptionStatus': 'trialing',
            })
            .timeout(const Duration(seconds: 10));

        // Auto-download global catalog for new workshop
        try {
          await CloudSyncService().init();
          await CloudSyncService().downloadGlobalCatalog().timeout(
            const Duration(seconds: 30),
          );
        } catch (e) {
          debugPrint('Failed to auto-download global catalog: $e');
        }
      }

      // The Supabase workshop membership is the source of truth. The
      // Firestore writes above are kept only as a migration bridge for old
      // installations and are not used by the app gate anymore.
      final prefs = await SharedPreferences.getInstance();
      final code = registrationWorkshopCode?.trim() ?? '';
      if (code.isEmpty) {
        await _auth.signOut();
        throw const AppAuthException(
          'workshop-code-missing',
          'تعذر إنشاء كود الورشة.',
        );
      }
      await prefs.setString('workshop_code', code);
      if (!_isWorkerSignup) {
        await prefs.setString(
          'workshop_name',
          _workshopNameController.text.trim(),
        );
      }
      final ready = await SupabaseWorkshopSyncService().ensureStarted(
        timeout: const Duration(seconds: 20),
      );
      if (!ready) {
        await _auth.signOut();
        throw const AppAuthException(
          'workshop-not-configured',
          'تعذر ربط الحساب بالورشة في Supabase.',
        );
      }

      await CloudSyncService().init();
      SupabaseWorkshopSyncService().start();

      // Firebase auth state changes will handle transitioning the screen automatically
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getFriendlyErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _isWorkshopNameTaken(String name) async {
    try {
      final nameCheck = await FirebaseFirestore.instance
          .collection('workshops')
          .where('name', isEqualTo: name)
          .get()
          .timeout(const Duration(seconds: 8));
      return nameCheck.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking workshop name: $e');
      try {
        final usersCheck = await FirebaseFirestore.instance
            .collection('users')
            .where('workshopName', isEqualTo: name)
            .get()
            .timeout(const Duration(seconds: 5));
        return usersCheck.docs.any((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          return data?['role'] == 'manager';
        });
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> _signInWithGoogle() => _withAuthHold(_signInWithGoogleFlow);

  Future<void> _signInWithGoogleFlow() async {
    final usesDirectWindowsOAuth =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    // Google verifies the email first. New users then choose manager/worker
    // and complete their workshop identity before Supabase creates auth.users.
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    var unconfiguredGoogleSession = false;
    try {
      // Google may switch accounts without recreating the Flutter singletons.
      // Clear the previous account's local workshop hint before OAuth starts.
      await CloudSyncService().clearCachedWorkshopContext();
      AppAuthUser user;
      String? idToken;
      String? accessToken;
      if (usesDirectWindowsOAuth) {
        if (!_isLoginMode) {
          // For registration we must know the selected Google email before
          // Supabase creates auth.users, so the admission hook can validate
          // the workshop form without asking the user to type an email.
          final tokens = await const WindowsGoogleSignIn().signIn();
          idToken = tokens.idToken;
          accessToken = tokens.accessToken;
          final googleEmail = _emailFromGoogleIdToken(idToken);
          if (googleEmail == null) {
            throw const AppAuthException(
              'google-email-missing',
              'لم يُرجع حساب Google بريداً إلكترونياً صالحاً.',
            );
          }
          final completed = await _collectGoogleSignupDetails(
            suggestedName: _nameFromGoogleIdToken(idToken),
          );
          if (!completed) return;
          await SupabaseAccountService().prepareWorkshopSignup(
            email: googleEmail,
            personName: _nameController.text.trim(),
            worker: _isWorkerSignup,
            workshopName: _workshopNameController.text.trim(),
            workshopCode: _workshopCodeController.text.trim().toUpperCase(),
          );
          user = await _auth.signInWithGoogleIdToken(
            idToken: idToken,
            accessToken: accessToken,
          );
        } else {
          try {
            user = await const WindowsGoogleSignIn().signInWithSupabase();
          } on WindowsGoogleSignInException {
            rethrow;
          } catch (supabaseOAuthError) {
            debugPrint(
              'Windows Supabase OAuth failed: $supabaseOAuthError. Attempting direct Google desktop flow...',
            );
            try {
              final tokens = await const WindowsGoogleSignIn().signIn();
              idToken = tokens.idToken;
              accessToken = tokens.accessToken;
              user = await _auth.signInWithGoogleIdToken(
                idToken: idToken,
                accessToken: accessToken,
              );
            } catch (_) {
              throw supabaseOAuthError;
            }
          }
        }
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
      } else {
        // Clear the plugin's cached Google account so the chooser is shown
        // instead of silently reusing the previous email.
        try {
          await GoogleSignIn(serverClientId: _googleServerClientId).signOut();
        } catch (_) {}
        final googleUser = await GoogleSignIn(
          serverClientId: _googleServerClientId,
        ).signIn();
        if (googleUser == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        final googleAuth = await googleUser.authentication;
        idToken = googleAuth.idToken;
        accessToken = googleAuth.accessToken;
        if (idToken == null || idToken.trim().isEmpty) {
          throw const AppAuthException(
            'google-token-missing',
            'لم يتم الحصول على رمز Google صالح.',
          );
        }

        // Only account creation receives a short-lived permit. A normal login
        // deliberately skips this call, so Supabase's Before User Created hook
        // rejects an unknown Google email instead of inserting auth.users.
        if (!_isLoginMode) {
          final completed = await _collectGoogleSignupDetails(
            suggestedName: googleUser.displayName ?? '',
          );
          if (!completed) return;
          await SupabaseAccountService().prepareWorkshopSignup(
            email: googleUser.email,
            personName: _nameController.text.trim(),
            worker: _isWorkerSignup,
            workshopName: _workshopNameController.text.trim(),
            workshopCode: _workshopCodeController.text.trim().toUpperCase(),
          );
        }

        user = await _auth.signInWithGoogleIdToken(
          idToken: idToken,
          accessToken: accessToken,
        );
      }
      unconfiguredGoogleSession = true;
      // Google can switch the Supabase session without recreating the Flutter
      // singletons. Reset the old workshop context before resolving this
      // Google account's membership.
      CloudSyncService().reset();
      var account = await SupabaseAccountService().loadCurrentAccount();
      if (account != null &&
          !_isSyntheticApplicationAdminAccount(user, account)) {
        unconfiguredGoogleSession = false;
      }
      if (_isLoginMode) {
        if (account == null ||
            _isSyntheticApplicationAdminAccount(user, account)) {
          if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
            account = await _tryLegacyGoogleWorkshopMigration(
              idToken: idToken!,
              accessToken: accessToken,
            );
          }
          if (account == null) {
            // Google OAuth may create the Auth row before membership lookup.
            // Remove that orphan immediately; an account without a workshop
            // must never remain in Supabase Authentication.
            try {
              await SupabaseAccountService()
                  .deleteCurrentUnconfiguredAuthUser();
            } catch (cleanupError) {
              debugPrint('Orphan Google account cleanup failed: $cleanupError');
            }
            await _auth.signOut();
            throw const AppAuthException(
              'account-not-configured',
              'لم يتم العثور على حساب مرتبط بورشة. إذا كنت مستخدماً جديداً، يرجى التبديل إلى "إنشاء حساب" للتسجيل.',
            );
          }
        }
        if (account.role == 'admin' &&
            _needsWorkshopNameRepair(account) &&
            !kIsWeb &&
            defaultTargetPlatform != TargetPlatform.windows) {
          final repaired = await _tryLegacyGoogleWorkshopMigration(
            idToken: idToken!,
            accessToken: accessToken,
          );
          if (repaired != null) account = repaired;
        }
        if (account.blocked) {
          final isPendingApproval = account.role == 'worker' &&
              account.permissions['is_rejected'] != true &&
              (account.permissions['is_pending'] == true ||
                  account.permissions['is_approved'] == false ||
                  (account.permissions['view_clients'] != true &&
                      account.permissions['view_orders'] != true));
          if (!isPendingApproval) {
            await _auth.signOut();
            throw const AppAuthException(
              'user-disabled',
              'عذراً، تم إيقاف هذا الحساب من قبل مدير الورشة.',
            );
          }
        }
      } else {
        if (account != null) {
          await _auth.signOut();
          throw const AppAuthException(
            'already-registered',
            'هذا البريد الإلكتروني مسجل بالفعل. توجه إلى تسجيل الدخول.',
          );
        }
        final prefs = await SharedPreferences.getInstance();
        final code = _isWorkerSignup
            ? _workshopCodeController.text.trim().toUpperCase()
            : _generateJoinCode();
        if (_isWorkerSignup && code.isEmpty) {
          throw const AppAuthException(
            'workshop-code-required',
            'يرجى إدخال كود الورشة.',
          );
        }
        await prefs.setString('workshop_code', code);
        if (!_isWorkerSignup) {
          final name = _workshopNameController.text.trim();
          if (name.isEmpty) {
            throw const AppAuthException(
              'workshop-name-required',
              'يرجى إدخال اسم المصنع أو الورشة.',
            );
          }
          await prefs.setString('workshop_name', name);
          await SupabaseWorkshopSyncService().createWorkshopForCurrentUser(
            joinCode: code,
            workshopName: name,
          );
        }
        final ready = await SupabaseWorkshopSyncService().ensureStarted(
          timeout: const Duration(seconds: 20),
        );
        if (!ready) {
          throw const AppAuthException(
            'workshop-not-configured',
            'تعذر ربط الحساب بالورشة. تأكد من كود الورشة أو من دعوة المدير.',
          );
        }
        account = await SupabaseAccountService().loadCurrentAccount();
      }

      if (account == null) {
        throw const AppAuthException(
          'membership-not-created',
          'تمت المصادقة، لكن لم يتم إنشاء عضوية الورشة.',
        );
      }
      if (!_isLoginMode) {
        await _auth.updateProfile(displayName: _nameController.text.trim());
      }
      unconfiguredGoogleSession = false;
      await _saveSupabaseAccountContext(account);
      SupabaseWorkshopSyncService().start();
      _auth.publishCurrentSession();
      debugPrint('Google Supabase login completed for ${user.email}');
    } on WindowsGoogleSignInException catch (error) {
      if (mounted) setState(() => _errorMessage = error.userMessage);
    } catch (error) {
      if (unconfiguredGoogleSession) {
        try {
          // OAuth creates an auth.users row as soon as an email is selected.
          // Remove it when workshop creation/joining did not complete, so the
          // account can never remain registered without a workshop.
          await SupabaseAccountService().deleteCurrentUnconfiguredAuthUser();
        } catch (cleanupError) {
          debugPrint('Unconfigured Google account cleanup failed: $cleanupError');
        }
        try {
          await _auth.signOut();
        } catch (_) {}
      }
      if (mounted)
        setState(() => _errorMessage = _getFriendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Legacy Firebase/Firestore Google flow retained as a rollback reference.
  Future<void> _signInWithGoogleLegacy() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 1. Validation check for signup before authentication
      if (!_isLoginMode) {
        if (!_isWorkerSignup && _workshopNameController.text.trim().isEmpty) {
          setState(() {
            _errorMessage = 'يرجى إدخال اسم المصنع أو الورشة.';
            _isLoading = false;
          });
          return;
        }

        if (!_isWorkerSignup) {
          final isTaken = await _isWorkshopNameTaken(
            _workshopNameController.text.trim(),
          );
          if (isTaken) {
            setState(() {
              _errorMessage =
                  'اسم الورشة محجوز وموجود مسبقاً! يرجى اختيار اسم آخر فريد.';
              _isLoading = false;
            });
            return;
          }
        }

        if (_isWorkerSignup && _workshopCodeController.text.trim().isEmpty) {
          setState(() {
            _errorMessage = 'يرجى إدخال كود الورشة.';
            _isLoading = false;
          });
          return;
        }
      }

      // 2. Trigger Google Sign-In. The mobile implementation remains exactly
      // the same; Windows uses the system browser and Supabase OAuth callback.
      AppAuthUser user;
      String? googleIdToken;
      String? googleAccessToken;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        user = await const WindowsGoogleSignIn().signInWithSupabase();
      } else {
        final GoogleSignInAccount? googleUser = await GoogleSignIn(
          serverClientId: _googleServerClientId,
        ).signIn();
        if (googleUser == null) {
          // User cancelled the sign-in.
          setState(() {
            _isLoading = false;
          });
          return;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        googleIdToken = googleAuth.idToken;
        googleAccessToken = googleAuth.accessToken;

        if (googleIdToken == null || googleIdToken.trim().isEmpty) {
          throw const AppAuthException(
            'google-token-missing',
            'لم يتم الحصول على رمز Google صالح.',
          );
        }
        user = await _auth.signInWithGoogleIdToken(
          idToken: googleIdToken,
          accessToken: googleAccessToken,
        );
      }

      final uid = user.uid;
      final email = user.email ?? '';

      // Supabase owns account existence, membership and blocking. Firebase
      // is not consulted here, so Google and password login follow one path.
      var account = await SupabaseAccountService().loadCurrentAccount();
      if (_isLoginMode) {
        if (account == null) {
          await _auth.signOut();
          throw const AppAuthException(
            'account-not-configured',
            'لم يتم العثور على حساب مرتبط بورشة. أنشئ الحساب أولاً.',
          );
        }
        if (account.blocked) {
          final isPendingApproval = account.role == 'worker' &&
              account.permissions['is_rejected'] != true &&
              (account.permissions['is_pending'] == true ||
                  account.permissions['is_approved'] == false ||
                  (account.permissions['view_clients'] != true &&
                      account.permissions['view_orders'] != true));
          if (!isPendingApproval) {
            await _auth.signOut();
            throw const AppAuthException(
              'user-disabled',
              'عذراً، تم إيقاف هذا الحساب من قبل مدير الورشة.',
            );
          }
        }
      } else {
        if (account != null) {
          await _auth.signOut();
          throw const AppAuthException(
            'already-registered',
            'هذا البريد الإلكتروني مسجل بالفعل. توجه إلى تسجيل الدخول.',
          );
        }

        final prefs = await SharedPreferences.getInstance();
        final code = _isWorkerSignup
            ? _workshopCodeController.text.trim()
            : _generateJoinCode();
        final workshopName = _isWorkerSignup
            ? ''
            : _workshopNameController.text.trim();
        await prefs.setString('workshop_code', code);
        if (workshopName.isNotEmpty) {
          await prefs.setString('workshop_name', workshopName);
          if (!_isWorkerSignup) {
            await SupabaseWorkshopSyncService().createWorkshopForCurrentUser(
              joinCode: code,
              workshopName: workshopName,
            );
          }
        }
        final ready = await SupabaseWorkshopSyncService().ensureStarted(
          timeout: const Duration(seconds: 20),
        );
        if (!ready) {
          await _auth.signOut();
          throw const AppAuthException(
            'workshop-not-configured',
            'تعذر ربط الحساب بالورشة. تأكد من كود الورشة أو من دعوة المدير.',
          );
        }
        account = await SupabaseAccountService().loadCurrentAccount();
        if (account == null) {
          await _auth.signOut();
          throw const AppAuthException(
            'membership-not-created',
            'تمت المصادقة، لكن لم يتم إنشاء عضوية الورشة.',
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workshop_code', account!.workshopCode);
      await prefs.setString('workshop_name', account.workshopName);
      await prefs.setString('user_role', account.role);
      await prefs.setString(
        'permissions_json',
        jsonEncode(account.permissions),
      );
      SupabaseWorkshopSyncService().start();
      return;

      // 4. Firestore checking and logic
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (_isLoginMode) {
        // --- LOGIN MODE ---
        if (isApplicationAdminEmail(email)) {
          // Admin account check/auto-create
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'email': email,
            'role': 'admin',
            'subscriptionStatus': 'active',
            'isBlocked': false,
            'workshopId': user.uid,
          }, SetOptions(merge: true));
        } else {
          if (!doc.exists) {
            // User does not exist, so they must register first!
            await _auth.signOut();
            await _signOutGoogleProviderIfSupported();
            setState(() {
              _errorMessage =
                  'لم يتم العثور على حساب مسجل لهذا البريد الإلكتروني. يرجى تبديل الوضع وإنشاء حساب جديد أولاً.';
              _isLoading = false;
            });
            return;
          }

          if (doc.data()?['isBlocked'] == true) {
            await _auth.signOut();
            await _signOutGoogleProviderIfSupported();
            setState(() {
              _errorMessage =
                  'عذراً، هذا الحساب محذوف أو تم إيقافه من قبل المدير.';
              _isLoading = false;
            });
            return;
          }
        }
      } else {
        // --- REGISTRATION MODE ---
        if (doc.exists) {
          // Account already exists in Firestore!
          setState(() {
            _errorMessage =
                'هذا البريد الإلكتروني مسجل بالفعل. يرجى التوجه لتسجيل الدخول.';
            _isLoading = false;
          });
          return;
        }

        // Proceed to register
        String? targetWorkshopId;
        String? workshopNameForWorker;

        if (_isWorkerSignup) {
          final code = _workshopCodeController.text.trim();
          final querySnapshot = await FirebaseFirestore.instance
              .collection('workshops')
              .where('joinCode', isEqualTo: code)
              .limit(1)
              .get();

          if (querySnapshot.docs.isEmpty) {
            await _auth.signOut();
            await _signOutGoogleProviderIfSupported();
            setState(() {
              _errorMessage = 'كود الورشة غير صحيح أو الورشة غير موجودة.';
              _isLoading = false;
            });
            return;
          }

          final workshopData = querySnapshot.docs.first.data();
          targetWorkshopId = querySnapshot.docs.first.id;
          workshopNameForWorker = workshopData['name'] as String?;

          final maxUsers = _readWorkshopMaxUsers(workshopData);

          int currentUsers = 0;
          var userCountRead = false;
          try {
            final workersSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .where('workshopId', isEqualTo: targetWorkshopId)
                .get();

            currentUsers = workersSnapshot.docs.where((doc) {
              final d = doc.data();
              return _isWorkshopUser(d);
            }).length;
            userCountRead = true;
          } catch (e) {
            debugPrint('Failed to count workers: $e');
          }

          if (maxUsers != 999) {
            if (!userCountRead) {
              await _auth.signOut();
              await _signOutGoogleProviderIfSupported();
              setState(() {
                _errorMessage =
                    'تعذر التحقق من عدد المستخدمين حالياً. يرجى المحاولة مرة أخرى.';
                _isLoading = false;
              });
              return;
            }
            if (currentUsers >= maxUsers) {
              await _auth.signOut();
              await _signOutGoogleProviderIfSupported();
              setState(() {
                _errorMessage =
                    'نعتذر، لقد وصلت هذه الورشة للحد الأقصى المسموح به من المستخدمين ($maxUsers). يرجى مراجعة مدير الورشة لترقية اشتراكه.';
                _isLoading = false;
              });
              return;
            }
          }

          final defaultPerms = {
            'view_clients': true,
            'create_clients': false,
            'view_orders': true,
            'create_orders': false,
            'view_client_details': true,
            'view_order_details': true,
            'view_my_tasks': true,
            'view_my_accreditations': true,
            'view_subscription': false,
            'isBlocked': false,
          };

          // Create Worker User
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'email': email,
            'role': 'worker',
            'workshopId': targetWorkshopId,
            'workshopName': workshopNameForWorker,
            'displayName':
                user.displayName ?? 'المستخدم رقم ${currentUsers + 1}',
            'permissions': defaultPerms,
            'permissions_json': jsonEncode(defaultPerms),
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Manager Signup
          final joinCode = _generateJoinCode();
          final workshopName = _workshopNameController.text.trim();
          final logoUrl =
              'https://ui-avatars.com/api/?name=${Uri.encodeComponent(workshopName)}&background=random&color=fff&size=256&font-size=0.4&bold=true';

          // Create workshop doc
          await FirebaseFirestore.instance
              .collection('workshops')
              .doc(uid)
              .set({
                'name': workshopName,
                'managerUid': uid,
                'joinCode': joinCode,
                'maxUsers': 4,
                'maxSystems': 999,
                'maxProfiles': 999,
                'createdAt': FieldValue.serverTimestamp(),
              });

          // Create user doc
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'email': email,
            'role': 'manager',
            'workshopId': uid,
            'workshopName': workshopName,
            'displayName': user.displayName ?? 'مدير الورشة',
            'logoUrl': logoUrl,
            'joinCode': joinCode,
            'createdAt': FieldValue.serverTimestamp(),
            'trialEndDate': DateTime.now()
                .add(const Duration(days: -1))
                .toIso8601String(),
            'isTrialActive': false,
            'subscriptionStatus': 'trialing',
          });

          // Auto-download global catalog
          try {
            await CloudSyncService().init();
            await CloudSyncService().downloadGlobalCatalog().timeout(
              const Duration(seconds: 30),
            );
          } catch (e) {
            debugPrint('Failed to auto-download global catalog: $e');
          }
        }
      }

      await _syncSupabaseGoogleSession(
        idToken: googleIdToken,
        accessToken: googleAccessToken,
      );

      // Firebase auth state changes will handle transitioning the screen automatically
    } on WindowsGoogleSignInException catch (e) {
      setState(() {
        _errorMessage = e.userMessage;
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getFriendlyErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء الاتصال بـ Google: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOutGoogleProviderIfSupported() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return;
    }
    await _auth.signOutGoogleSession();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _workshopNameController.dispose();
    _workshopCodeController.dispose();
    _workshopNameFocusNode.dispose();
    _workshopCodeFocusNode.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Floating Particles background
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: ParticlePainter(_particles, _animationController),
                ),
              ),
            ),

            // Login Form
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 48.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Floating Glowing Emblem Logo (Without outer square box)
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        final pulse =
                            sin(_animationController.value * 2 * pi) * 0.05;
                        return Transform.scale(
                          scale: 1.0 + pulse,
                          child: SizedBox(
                            width: 120,
                            height: 120,
                            child: Image.asset(
                              'assets/images/warshati_logo_glowing.png',
                              fit: BoxFit.contain,
                              errorBuilder: (ctx, err, stack) {
                                return Image.asset(
                                  'assets/images/app_icon.png',
                                  fit: BoxFit.contain,
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      Localization.translate('ورشتي', settings.language),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      Localization.translate(
                        'نظام إدارة وتسيير ورش الألمنيوم الذكي',
                        settings.language,
                      ),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Frosted Glassmorphism Card
                    CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.enter): () {
                          if (!_isLoading) {
                            if (_isLoginMode) {
                              _login();
                            } else {
                              _register();
                            }
                          }
                        },
                        const SingleActivator(
                          LogicalKeyboardKey.numpadEnter,
                        ): () {
                          if (!_isLoading) {
                            if (_isLoginMode) {
                              _login();
                            } else {
                              _register();
                            }
                          }
                        },
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.0),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                          child: Container(
                            padding: const EdgeInsets.all(28.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(24.0),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.12),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _isLoginMode
                                      ? Localization.translate(
                                          'تسجيل الدخول',
                                          lang,
                                        )
                                      : Localization.translate(
                                          'إنشاء حساب جديد',
                                          lang,
                                        ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                if (!_isLoginMode) ...[
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 10,
                                    children: [
                                      ChoiceChip(
                                        label: Text(
                                          Localization.translate(
                                            'إنشاء ورشة (مدير)',
                                            lang,
                                          ),
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        selected: !_isWorkerSignup,
                                        selectedColor: Colors.blueAccent,
                                        backgroundColor: Colors.white,
                                        labelStyle: TextStyle(
                                          color: !_isWorkerSignup
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                        onSelected: (val) {
                                          setState(() {
                                            _isWorkerSignup = !val;
                                          });
                                        },
                                      ),
                                      ChoiceChip(
                                        label: Text(
                                          Localization.translate(
                                            'الانضمام إلى ورشة موجودة',
                                            lang,
                                          ),
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        selected: _isWorkerSignup,
                                        selectedColor: Colors.blueAccent,
                                        backgroundColor: Colors.white,
                                        labelStyle: TextStyle(
                                          color: _isWorkerSignup
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                        onSelected: (val) {
                                          setState(() {
                                            _isWorkerSignup = val;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  if (!_isWorkerSignup) ...[
                                    TextField(
                                      controller: _workshopNameController,
                                      focusNode: _workshopNameFocusNode,
                                      textInputAction: TextInputAction.next,
                                      onSubmitted: (_) =>
                                          _workshopCodeFocusNode.requestFocus(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Cairo',
                                      ),
                                      decoration: InputDecoration(
                                        labelText: Localization.translate(
                                          'اسم المصنع / الورشة',
                                          lang,
                                        ),
                                        labelStyle: const TextStyle(
                                          color: Colors.white70,
                                          fontFamily: 'Cairo',
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(
                                          0.04,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.storefront,
                                          color: Colors.white60,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.12,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Colors.blueAccent,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    TextField(
                                      controller: _workshopCodeController,
                                      focusNode: _workshopCodeFocusNode,
                                      textInputAction: TextInputAction.next,
                                      onSubmitted: (_) =>
                                          _nameFocusNode.requestFocus(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Cairo',
                                      ),
                                      decoration: InputDecoration(
                                        labelText: Localization.translate(
                                          'كود الورشة (ضروري)',
                                          lang,
                                        ),
                                        labelStyle: const TextStyle(
                                          color: Colors.white70,
                                          fontFamily: 'Cairo',
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(
                                          0.04,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.qr_code,
                                          color: Colors.white60,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.12,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Colors.blueAccent,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                ],

                                if (!_isLoginMode) ...[
                                  TextField(
                                    controller: _nameController,
                                    focusNode: _nameFocusNode,
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) =>
                                        _emailFocusNode.requestFocus(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Cairo',
                                    ),
                                    decoration: InputDecoration(
                                      labelText: Localization.translate(
                                        'الاسم الكامل',
                                        lang,
                                      ),
                                      labelStyle: const TextStyle(
                                        color: Colors.white70,
                                        fontFamily: 'Cairo',
                                      ),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.04),
                                      prefixIcon: const Icon(
                                        Icons.person_outline,
                                        color: Colors.white60,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.white.withOpacity(0.12),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Colors.blueAccent,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                TextField(
                                  controller: _emailController,
                                  focusNode: _emailFocusNode,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _passwordFocusNode.requestFocus(),
                                  keyboardType: TextInputType.emailAddress,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.deny(
                                      RegExp(r'\s'),
                                    ),
                                  ],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cairo',
                                  ),
                                  decoration: InputDecoration(
                                    labelText: Localization.translate(
                                      'البريد الإلكتروني',
                                      lang,
                                    ),
                                    hintText: 'name@gmail.com',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.3),
                                      fontFamily: 'Cairo',
                                    ),
                                    labelStyle: const TextStyle(
                                      color: Colors.white70,
                                      fontFamily: 'Cairo',
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.04),
                                    prefixIcon: const Icon(
                                      Icons.email_outlined,
                                      color: Colors.white60,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.12),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Colors.blueAccent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!_isLoginMode) ...[
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    child: Text(
                                      Localization.translate(
                                        '⚠️ من الأفضل التسجيل ببريد إلكتروني حقيقي لتتمكن من استرجاع كلمة المرور في حال نسيانها.',
                                        lang,
                                      ),
                                      style: TextStyle(
                                        color: Colors.amber.shade300,
                                        fontSize: 11,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),

                                TextField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocusNode,
                                  textInputAction: _isLoginMode
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                                  onSubmitted: (_) {
                                    if (_isLoginMode) {
                                      if (!_isLoading) _login();
                                    } else {
                                      _confirmPasswordFocusNode.requestFocus();
                                    }
                                  },
                                  obscureText: _obscurePassword,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cairo',
                                  ),
                                  decoration: InputDecoration(
                                    labelText: Localization.translate(
                                      'كلمة المرور',
                                      lang,
                                    ),
                                    labelStyle: const TextStyle(
                                      color: Colors.white70,
                                      fontFamily: 'Cairo',
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.04),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline,
                                      color: Colors.white60,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.12),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Colors.blueAccent,
                                        width: 2,
                                      ),
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: Colors.white60,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                if (_isLoginMode) ...[
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: _resetPassword,
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(50, 30),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        Localization.translate(
                                          'نسيت كلمة المرور؟',
                                          lang,
                                        ),
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),

                                if (!_isLoginMode) ...[
                                  TextField(
                                    controller: _confirmPasswordController,
                                    focusNode: _confirmPasswordFocusNode,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) {
                                      if (!_isLoading) _register();
                                    },
                                    obscureText: _obscurePassword,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Cairo',
                                    ),
                                    decoration: InputDecoration(
                                      labelText: Localization.translate(
                                        'تأكيد كلمة المرور',
                                        lang,
                                      ),
                                      labelStyle: const TextStyle(
                                        color: Colors.white70,
                                        fontFamily: 'Cairo',
                                      ),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.04),
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: Colors.white60,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.white.withOpacity(0.12),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Colors.blueAccent,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],

                                if (_errorMessage.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.12),
                                      border: Border.all(
                                        color: Colors.red.withOpacity(0.3),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.error_outline,
                                          color: Colors.redAccent,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _errorMessage,
                                            style: const TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                if (_isLoading)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8.0,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const CircularProgressIndicator(
                                            color: Colors.blueAccent,
                                          ),
                                          const SizedBox(height: 10),
                                          TextButton.icon(
                                            onPressed: () {
                                              if (!kIsWeb &&
                                                  defaultTargetPlatform ==
                                                      TargetPlatform.windows) {
                                                WindowsGoogleSignIn
                                                    .cancelActiveSignIn();
                                              }
                                              if (mounted) {
                                                setState(() {
                                                  _isLoading = false;
                                                });
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.white70,
                                            ),
                                            label: Text(
                                              Localization.translate(
                                                'إلغاء',
                                                lang,
                                              ),
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                color: Colors.white70,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ElevatedButton(
                                        onPressed: _isLoginMode
                                            ? _login
                                            : _register,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          elevation: 4,
                                        ),
                                        child: Text(
                                          _isLoginMode
                                              ? Localization.translate(
                                                  'تسجيل الدخول',
                                                  lang,
                                                )
                                              : Localization.translate(
                                                  'إنشاء حساب',
                                                  lang,
                                                ),
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      OutlinedButton(
                                        onPressed: _signInWithGoogle,
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          side: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.2,
                                            ),
                                            width: 1.5,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          backgroundColor: Colors.white
                                              .withOpacity(0.08),
                                          foregroundColor: Colors.white,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SvgPicture.asset(
                                              'assets/images/google_g_logo.svg',
                                              width: 22,
                                              height: 22,
                                              fit: BoxFit.contain,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              _isLoginMode
                                                  ? Localization.translate(
                                                      'الدخول باستخدام Google',
                                                      lang,
                                                    )
                                                  : Localization.translate(
                                                      'التسجيل باستخدام Google',
                                                      lang,
                                                    ),
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _isLoginMode = !_isLoginMode;
                                            _errorMessage = '';
                                          });
                                        },
                                        child: Text(
                                          _isLoginMode
                                              ? Localization.translate(
                                                  'ليس لديك حساب؟ إنشاء حساب جديد',
                                                  lang,
                                                )
                                              : Localization.translate(
                                                  'لديك حساب بالفعل؟ تسجيل الدخول',
                                                  lang,
                                                ),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Particle Effect classes for Premium UI Animation
// ─────────────────────────────────────────────────────────────────────────────
class Particle {
  double x;
  double y;
  double speed;
  double size;
  double opacity;
  double angle;

  Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.angle,
  });
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final Animation<double> animation;

  ParticlePainter(this.particles, this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var p in particles) {
      final travel = animation.value * 900 * p.speed;
      final animatedY = (p.y - travel) % 1.1;
      final animatedX =
          (p.x + sin(p.angle + animation.value * 2 * pi) * 0.018) % 1.0;
      paint.color = Colors.white.withValues(alpha: p.opacity);
      canvas.drawCircle(
        Offset(animatedX * size.width, animatedY * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) =>
      oldDelegate.particles != particles || oldDelegate.animation != animation;
}
