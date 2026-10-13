import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/settings/app_settings.dart';
import 'dart:math' as math;

import 'app_admin_status_service.dart';
import 'offline_account_cache.dart';

/// The account/workshop record used by the application gate.
///
/// Authentication, membership and subscription are intentionally read from
/// Supabase in one place.  This prevents individual screens from silently
/// falling back to a Firebase user document.
class SupabaseAccountSnapshot {
  const SupabaseAccountSnapshot({
    required this.userId,
    required this.email,
    required this.role,
    required this.workshopId,
    required this.workshopCode,
    required this.workshopName,
    required this.permissions,
    required this.blocked,
    required this.subscription,
  });

  final String userId;
  final String email;
  final String role;
  final String workshopId;
  final String workshopCode;
  final String workshopName;
  final Map<String, dynamic> permissions;
  final bool blocked;
  final Map<String, dynamic> subscription;

  /// The global application-admin workspace is not a customer workshop and
  /// therefore has no row in `workshop_subscriptions`.
  bool get isApplicationAdminWorkspace =>
      role == 'admin' &&
      workshopCode.isEmpty &&
      workshopId.isNotEmpty &&
      workshopId == userId;

  Map<String, dynamic> get subscriptionData => {
    ...subscription,
    'subscriptionStatus': subscription['status'],
    'subscriptionType': subscription['plan_type'],
    'subscriptionStartDate': subscription['starts_at'],
    'subscriptionEndDate': subscription['ends_at'],
    'maxUsers': subscription['max_users'],
    'maxSystems': subscription['max_systems'],
    'maxProfiles': subscription['max_profiles'],
    'role': role,
    'workshopId': workshopId,
    'workshopName': workshopName,
    'joinCode': workshopCode,
    'email': email,
    'isBlocked': blocked,
    'isApplicationAdminWorkspace': isApplicationAdminWorkspace,
  };

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'email': email,
    'role': role,
    'workshopId': workshopId,
    'workshopCode': workshopCode,
    'workshopName': workshopName,
    'permissions': permissions,
    'blocked': blocked,
    'subscription': subscription,
  };
}

class SupabaseAccountService {
  SupabaseAccountService._();

  static final SupabaseAccountService _instance = SupabaseAccountService._();

  factory SupabaseAccountService() => _instance;

  SupabaseClient get _client => Supabase.instance.client;

  static const Duration _accountCacheDuration = Duration(minutes: 2);
  SupabaseAccountSnapshot? _cachedAccount;
  String? _cachedAccountUserId;
  DateTime? _cachedAccountAt;
  Future<SupabaseAccountSnapshot?>? _accountLoadInFlight;
  String? _accountLoadUserId;

  void invalidateCurrentAccountCache() {
    _cachedAccount = null;
    _cachedAccountUserId = null;
    _cachedAccountAt = null;
  }

  Future<void> prepareWorkshopSignup({
    required String email,
    required String personName,
    required bool worker,
    String workshopName = '',
    String workshopCode = '',
  }) async {
    final admitted = await _client.rpc(
      'prepare_workshop_signup',
      params: {
        'requested_email': email.trim().toLowerCase(),
        'requested_kind': worker ? 'worker' : 'manager',
        'requested_person_name': personName.trim(),
        'requested_workshop_name': workshopName.trim(),
        'requested_workshop_code': workshopCode.trim(),
      },
    );
    if (admitted != true) {
      throw StateError('تعذر اعتماد بيانات إنشاء الحساب.');
    }
  }

  /// Removes an OAuth account created by Auth when workshop registration was
  /// not completed. The RPC refuses deletion for configured users.
  Future<void> deleteCurrentUnconfiguredAuthUser() async {
    try {
      final deleted = await _client.rpc('delete_current_orphan_auth_user');
      if (deleted != true) {
        throw StateError('Supabase Auth orphan was not deleted.');
      }
    } catch (primaryError) {
      // Compatibility with databases that have catalog_sync.sql but have not
      // yet applied delete_orphan_auth_accounts.sql.
      try {
        await _client.rpc('delete_unconfigured_auth_user');
      } catch (legacyError) {
        throw StateError(
          'تعذر حذف الحساب غير المرتبط من Supabase Authentication. '
          'طبّق supabase/delete_orphan_auth_accounts.sql. '
          'Primary: $primaryError; legacy: $legacyError',
        );
      }
    } finally {
      invalidateCurrentAccountCache();
    }
  }

  Future<void> setSubscriptionForOwnerUid({
    required String ownerUid,
    required String status,
    required String planType,
    DateTime? endsAt,
    int? maxUsers,
    int? maxSystems,
    int? maxProfiles,
  }) async {
    final workshop = await _client
        .from('workshops')
        .select('id')
        .eq('owner_uid', ownerUid)
        .maybeSingle();
    final workshopId = workshop?['id']?.toString() ?? '';
    if (workshopId.isEmpty) {
      throw Exception('لم يتم العثور على ورشة Supabase لهذا المدير.');
    }

    final current = await _client
        .from('workshop_subscriptions')
        .select('max_users,max_systems,max_profiles')
        .eq('workshop_id', workshopId)
        .maybeSingle();
    await _client.rpc(
      'admin_set_workshop_subscription',
      params: {
        'target_workshop_id': workshopId,
        'new_status': status,
        'new_plan_type': planType,
        'new_ends_at': endsAt?.toUtc().toIso8601String(),
        'new_max_users': maxUsers ?? current?['max_users'] ?? 4,
        'new_max_systems': maxSystems ?? current?['max_systems'] ?? 999,
        'new_max_profiles': maxProfiles ?? current?['max_profiles'] ?? 999,
      },
    );
  }

  /// Updates the subscription for the exact workshop row selected by the
  /// application administrator.  Admin listings can contain more than one
  /// workshop for the same owner, so resolving by owner_uid is ambiguous.
  Future<void> setSubscriptionForWorkshopId({
    required String workshopId,
    required String status,
    required String planType,
    DateTime? endsAt,
    int? maxUsers,
    int? maxSystems,
    int? maxProfiles,
  }) async {
    final cleanId = workshopId.trim();
    if (cleanId.isEmpty) {
      throw Exception('معرّف الورشة غير موجود.');
    }

    final current = await _client
        .from('workshop_subscriptions')
        .select('max_users,max_systems,max_profiles')
        .eq('workshop_id', cleanId)
        .maybeSingle();
    await _client.rpc(
      'admin_set_workshop_subscription',
      params: {
        'target_workshop_id': cleanId,
        'new_status': status,
        'new_plan_type': planType,
        'new_ends_at': endsAt?.toUtc().toIso8601String(),
        'new_max_users': maxUsers ?? current?['max_users'] ?? 4,
        'new_max_systems': maxSystems ?? current?['max_systems'] ?? 999,
        'new_max_profiles': maxProfiles ?? current?['max_profiles'] ?? 999,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchAdminWorkshopMembers(
    String workshopCode,
  ) async {
    final code = workshopCode.trim();
    if (code.isEmpty) return <Map<String, dynamic>>[];
    try {
      final result = await _client.rpc(
        'list_workshop_members',
        params: {'target_code': code},
      );
      if (result is List) {
        return result
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
      }
    } catch (e) {
      print('list_workshop_members RPC note: $e');
    }

    try {
      List<dynamic> ws;
      try {
        ws = await _client
            .from('workshops')
            .select('id')
            .or('id.eq.$code,code.eq.$code,join_code.eq.$code')
            .limit(1);
      } catch (_) {
        ws = await _client
            .from('workshops')
            .select('id')
            .or('id.eq.$code,code.eq.$code')
            .limit(1);
      }
      if (ws.isNotEmpty && ws.first is Map) {
        final wId = ws.first['id']?.toString() ?? '';
        if (wId.isNotEmpty) {
          final members = await _client
              .from('workshop_members')
              .select('user_id,role,permissions,blocked,updated_at')
              .eq('workshop_id', wId);
          return members
              .whereType<Map>()
              .map(
                (row) => {
                  'user_id': row['user_id'],
                  'email': '',
                  'role': row['role'] ?? 'worker',
                  'permissions':
                      row['permissions'] ?? const <String, dynamic>{},
                  'blocked': row['blocked'] == true,
                  'is_pending': false,
                  'updated_at': row['updated_at'],
                },
              )
              .toList(growable: false);
        }
      }
    } catch (_) {}

    return <Map<String, dynamic>>[];
  }

  Future<void> updateAdminWorkshopMember({
    required String workshopCode,
    required String email,
    required String role,
    required Map<String, dynamic> permissions,
    required bool blocked,
  }) async {
    final code = workshopCode.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (code.isEmpty || cleanEmail.isEmpty) {
      throw Exception('كود الورشة وبريد العامل مطلوبان.');
    }
    await _client.rpc(
      'update_workshop_member_permissions',
      params: {
        'target_code': code,
        'member_email': cleanEmail,
        'member_role': role,
        'member_permissions': permissions,
        'member_blocked': blocked,
      },
    );
  }

  Future<SupabaseAccountSnapshot?> loadCurrentAccount({
    bool forceRefresh = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final cachedAt = _cachedAccountAt;
    if (!forceRefresh &&
        _cachedAccountUserId == user.id &&
        _cachedAccount != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _accountCacheDuration) {
      return _cachedAccount;
    }

    final activeLoad = _accountLoadInFlight;
    // A forced refresh bypasses stale cached data, but it should still join an
    // identical request that is already running instead of duplicating it.
    if (activeLoad != null && _accountLoadUserId == user.id) return activeLoad;

    final load = _loadCurrentAccountFromServer(user);
    _accountLoadInFlight = load;
    _accountLoadUserId = user.id;
    try {
      final account = await load;
      if (_client.auth.currentUser?.id == user.id) {
        _cachedAccount = account;
        _cachedAccountUserId = user.id;
        _cachedAccountAt = DateTime.now();
        if (account != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await saveOfflineAccount(prefs, account.toMap());
          } catch (_) {}
        }
      }
      return account;
    } catch (e) {
      // If server request fails (e.g. offline/network timeout), attempt to recover from offline cache
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedMap = readOfflineAccount(prefs, user.id);
        if (cachedMap != null) {
          final recovered = _snapshotFromMap(cachedMap);
          _cachedAccount = recovered;
          _cachedAccountUserId = user.id;
          _cachedAccountAt = DateTime.now();
          return recovered;
        }
      } catch (_) {}
      rethrow;
    } finally {
      if (identical(_accountLoadInFlight, load)) {
        _accountLoadInFlight = null;
        _accountLoadUserId = null;
      }
    }
  }

  SupabaseAccountSnapshot _snapshotFromMap(Map<String, dynamic> map) {
    Map<String, dynamic> objectMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    return SupabaseAccountSnapshot(
      userId: map['userId']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      role: map['role']?.toString() ?? 'worker',
      workshopId: map['workshopId']?.toString() ?? '',
      workshopCode: map['workshopCode']?.toString() ?? '',
      workshopName: map['workshopName']?.toString() ?? '',
      permissions: objectMap(map['permissions']),
      blocked: map['blocked'] == true,
      subscription: objectMap(map['subscription']),
    );
  }

  Future<SupabaseAccountSnapshot?> _loadCurrentAccountFromServer(
    User user,
  ) async {
    final isApplicationAdmin = await AppAdminStatusService.instance
        .isCurrentUserAdmin();

    final memberships = await _client
        .from('workshop_members')
        .select('workshop_id,role,permissions,blocked')
        .eq('user_id', user.id);

    // An application administrator can also be the owner of a real
    // workshop. The old implementation returned the synthetic "إدارة
    // التطبيق" account before checking memberships, which made the dashboard
    // open an empty workshop and hid the owner's orders. Prefer the selected
    // real workshop whenever one exists.
    final membershipRows = memberships
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => (row['workshop_id']?.toString() ?? '').isNotEmpty)
        .toList(growable: false);

    // A saved workshop code is only a hint for the join RPC. It is not proof
    // of membership. The old fallback fabricated a worker snapshot from that
    // local value, which could show a deleted/orphaned worker or attach a new
    // login to another phone's previous workshop. Normal users must have a
    // real workshop_members row created by ensure_my_workshop.

    if (membershipRows.isNotEmpty) {
      final workshopIds = membershipRows
          .map((row) => row['workshop_id'].toString())
          .toList(growable: false);
      List<dynamic> workshops;
      try {
        workshops = await _client
            .from('workshops')
            .select('id,code,name,join_code')
            .inFilter('id', workshopIds);
      } catch (_) {
        // Keep older projects readable until the join_code migration is run.
        workshops = await _client
            .from('workshops')
            .select('id,code,name')
            .inFilter('id', workshopIds);
      }
      final workshopById = <String, Map<String, dynamic>>{
        for (final row in workshops.whereType<Map>())
          row['id'].toString(): Map<String, dynamic>.from(row),
      };

      final prefs = await SharedPreferences.getInstance();
      final preferredCode = (prefs.getString('workshop_code') ?? '').trim();
      final preferredWorkshopId =
          (prefs.getString('selected_supabase_workshop_id') ?? '').trim();
      Map<String, dynamic>? selectedMember;
      Map<String, dynamic>? selectedWorkshop;

      for (final member in membershipRows) {
        final workshop = workshopById[member['workshop_id'].toString()];
        if (workshop == null) continue;
        final workshopCode = workshop['code']?.toString().trim() ?? '';
        final workshopJoinCode = workshop['join_code']?.toString().trim() ?? '';
        if ((preferredWorkshopId.isNotEmpty &&
                workshop['id']?.toString() == preferredWorkshopId) ||
            (preferredCode.isNotEmpty &&
                (workshop['id']?.toString() == preferredCode ||
                    workshopCode == preferredCode ||
                    workshopJoinCode == preferredCode))) {
          selectedMember = member;
          selectedWorkshop = workshop;
          break;
        }
      }

      // A normal worker/manager has one membership. For an app administrator
      // with several memberships, use the most recently returned one when no
      // previous workshop choice exists; the next load will persist that code.
      if (selectedMember == null && !isApplicationAdmin) {
        for (final member in membershipRows) {
          final workshop = workshopById[member['workshop_id'].toString()];
          if (workshop != null) {
            selectedMember = member;
            selectedWorkshop = workshop;
            break;
          }
        }
      }

      if (selectedMember != null && selectedWorkshop != null) {
        await prefs.setString(
          'selected_supabase_workshop_id',
          selectedWorkshop['id'].toString(),
        );
        return _buildWorkshopSnapshot(
          user: user,
          workshop: selectedWorkshop,
          role: isApplicationAdmin
              ? 'admin'
              : selectedMember['role']?.toString() ?? 'worker',
          permissions: selectedMember['permissions'],
          blocked: selectedMember['blocked'] == true,
        );
      }
    }

    // If the user owns a workshop (registered as manager or migrated) but does not
    // have an explicit workshop_members row, resolve their owned workshop.
    try {
      final ownedWorkshop = await _client
          .from('workshops')
          .select('id,code,name,join_code')
          .eq('owner_uid', user.id)
          .limit(1)
          .maybeSingle();
      if (ownedWorkshop != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'selected_supabase_workshop_id',
          ownedWorkshop['id'].toString(),
        );
        return _buildWorkshopSnapshot(
          user: user,
          workshop: Map<String, dynamic>.from(ownedWorkshop),
          role: isApplicationAdmin ? 'admin' : 'manager',
          permissions: const <String, dynamic>{},
          blocked: false,
        );
      }
    } catch (e) {
      debugPrint('Owned workshop lookup fallback skipped: $e');
    }

    if (isApplicationAdmin) {
      // The application administrator is global and may not have a
      // workshop_members row. When a workshop was selected explicitly on the
      // admin screen, resolve that selected workshop without fabricating a
      // worker membership.
      final selectedAdminWorkshop =
          await loadSelectedApplicationAdminWorkshop();
      if (selectedAdminWorkshop != null) return selectedAdminWorkshop;

      return SupabaseAccountSnapshot(
        userId: user.id,
        email: user.email ?? '',
        role: 'admin',
        workshopId: user.id,
        workshopCode: '',
        workshopName: 'إدارة التطبيق',
        permissions: const <String, dynamic>{},
        blocked: false,
        subscription: const <String, dynamic>{
          'status': 'active',
          'plan_type': 'lifetime',
        },
      );
    }

    return null;
  }

  Future<SupabaseAccountSnapshot> _buildWorkshopSnapshot({
    required User user,
    required Map<String, dynamic> workshop,
    required String role,
    required dynamic permissions,
    required bool blocked,
  }) async {
    final workshopId = workshop['id']?.toString() ?? '';
    // `code` is the internal identifier in the current schema, while
    // `join_code` is the short value workers enter.  Older migrated rows can
    // still have the public value in `code`, so use it only when it really is
    // a short public code; never expose a UUID in the UI.
    final workshopCode = _firstPublicCode(
      workshop['join_code'],
      workshop['code'],
    );
    final workshopName = await _resolveDisplayName(
      workshopId: workshopId,
      workshopCode: workshopCode,
      storedName: workshop['name']?.toString() ?? '',
    );
    Map<String, dynamic>? subscription;
    try {
      final sub = await _client
          .from('workshop_subscriptions')
          .select(
            'status,plan_type,starts_at,ends_at,max_users,max_systems,max_profiles',
          )
          .eq('workshop_id', workshopId)
          .maybeSingle();
      if (sub != null) {
        subscription = Map<String, dynamic>.from(sub);
      }
    } catch (e) {
      debugPrint('Error fetching workshop_subscriptions for $workshopId: $e');
    }

    return SupabaseAccountSnapshot(
      userId: user.id,
      email: user.email ?? '',
      role: role,
      workshopId: workshopId,
      workshopCode: workshopCode,
      workshopName: workshopName,
      permissions: permissions is Map
          ? Map<String, dynamic>.from(permissions)
          : const <String, dynamic>{},
      blocked: blocked,
      subscription: subscription == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(subscription),
    );
  }

  String _shortPublicCode(dynamic value) {
    if (value is Map) {
      for (final key in const [
        'join_code',
        'joinCode',
        'code',
        'result',
        'data',
        'set_my_workshop_join_code',
      ]) {
        final nested = _shortPublicCode(value[key]);
        if (nested.isNotEmpty) return nested;
      }
    }
    if (value is List && value.length == 1) {
      return _shortPublicCode(value.first);
    }
    final code = value?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    // Keep legacy public codes such as "BGRSC 202" valid, while rejecting
    // UUIDs and other internal identifiers from the user-facing UI.
    final validPublicCode = RegExp(
      r'^[A-Za-z0-9]{2,8}(?:[ -][A-Za-z0-9]{1,8})?$',
    ).hasMatch(code);
    return validPublicCode ? code : '';
  }

  String _firstPublicCode(dynamic primary, dynamic fallback) {
    final primaryCode = _shortPublicCode(primary);
    if (primaryCode.isNotEmpty) return primaryCode;
    return _shortPublicCode(fallback);
  }

  /// Creates the short worker-facing code on the actual Supabase workshop.
  ///
  /// The RPC is preferred because workshop managers are not allowed to update
  /// the workshops table directly by the normal RLS policy.  The direct update
  /// fallback keeps this working for the application administrator on older
  /// installations where the RPC migration has not yet been applied.
  Future<String> createWorkshopJoinCode() async {
    final account = await loadCurrentAccount();
    if (account == null || account.workshopId.isEmpty) {
      throw Exception('لم يتم العثور على الورشة الحالية في Supabase.');
    }

    // A workshop join code is a persistent identity shared by every device.
    // Opening the drawer or pressing "create" again must never rotate an
    // existing code, otherwise devices that cached the previous value can
    // resolve a different workshop on their next launch.
    final existingCode = _shortPublicCode(account.workshopCode);
    if (existingCode.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workshop_code', existingCode);
      await prefs.setString(
        'selected_supabase_workshop_id',
        account.workshopId,
      );
      return existingCode;
    }

    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = math.Random.secure();
    final requestedCode = String.fromCharCodes(
      Iterable.generate(
        6,
        (_) => characters.codeUnitAt(random.nextInt(characters.length)),
      ),
    );

    String? resultCode;
    Object? rpcError;
    try {
      final result = await _client.rpc(
        'set_my_workshop_join_code',
        params: {
          'target_workshop_id': account.workshopId,
          'requested_code': requestedCode,
        },
      );
      resultCode = _shortPublicCode(result);
    } catch (error) {
      rpcError = error;
    }

    if (_shortPublicCode(resultCode).isEmpty) {
      // The RPC is installed by the optional management migration.  For the
      // application administrator, the existing RLS policy already permits
      // this direct update, so preserve compatibility with older databases.
      try {
        final updated = await _client
            .from('workshops')
            .update({'join_code': requestedCode})
            .eq('id', account.workshopId)
            .select('join_code')
            .maybeSingle();
        resultCode = _shortPublicCode(updated?['join_code']);
      } catch (error) {
        throw Exception(
          'تعذر إنشاء كود الورشة في Supabase. '
          'طبّق ملف workshop_join_code_management.sql على قاعدة Supabase. '
          'RPC: ${rpcError ?? 'غير متاح'}، التحديث: $error',
        );
      }
    }

    final code = _shortPublicCode(resultCode);
    if (code.isEmpty) {
      throw Exception('تعذر حفظ كود الورشة في Supabase.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workshop_code', code);
    await prefs.setString('selected_supabase_workshop_id', account.workshopId);
    return code;
  }

  Future<String> _resolveDisplayName({
    required String workshopId,
    required String workshopCode,
    required String storedName,
  }) async {
    String clean(dynamic value) => value?.toString().trim() ?? '';
    bool isUsableName(String value) =>
        value.isNotEmpty &&
        value != workshopCode &&
        value != 'ورشة النجارة' &&
        value != 'ورشة الألمنيوم';
    final directName = clean(storedName);
    if (isUsableName(directName)) {
      return directName;
    }

    // During the legacy migration the workshop row can contain the code
    // while the real human-readable name is stored in the synced profile.
    try {
      final row = await _client
          .from('workshop_sync_rows')
          .select('payload')
          .eq('workshop_id', workshopId)
          .eq('table_name', '__WorkshopProfile')
          .eq('row_id', 'current')
          .maybeSingle();
      final payload = row?['payload'];
      if (payload is Map) {
        final profileName = clean(payload['workshop_name']);
        if (isUsableName(profileName)) {
          return profileName;
        }
      }
    } catch (_) {
      // RLS or an older schema can omit the optional profile row.
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedName = clean(prefs.getString('workshop_name'));
    if (isUsableName(cachedName)) {
      return cachedName;
    }
    // A workshop code is an identifier, not a display name. Keep the name
    // empty so the UI can show a neutral fallback instead of duplicating the
    // technical code as the workshop title.
    return isUsableName(directName) ? directName : '';
  }

  Future<List<Map<String, dynamic>>> fetchAdminWorkshops() async {
    final rows = await _client.rpc('list_admin_workshops');
    if (rows is! List) return <Map<String, dynamic>>[];

    // Return all workshops so the application administrator can inspect,
    // manage subscriptions, and configure their own workshop alongside clients.
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<SupabaseAccountSnapshot?> loadSelectedApplicationAdminWorkshop({
    String? code,
    String? name,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null ||
        !(isApplicationAdminEmail(user.email) ||
            await _isCurrentUserApplicationAdmin())) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final selectedCode = (code ?? prefs.getString('workshop_code') ?? '')
        .trim();
    final preferredWorkshopId = code == null
        ? (prefs.getString('selected_supabase_workshop_id') ?? '').trim()
        : '';
    if (selectedCode.isEmpty && preferredWorkshopId.isEmpty) return null;
    if (code != null && code.trim().isNotEmpty) {
      await prefs.setString('workshop_code', selectedCode);
    }
    if (name != null && name.trim().isNotEmpty) {
      await prefs.setString('workshop_name', name.trim());
    }

    final rows = await _client.rpc('list_admin_workshops');
    if (rows is! List) return null;
    Map<String, dynamic>? selected;
    for (final raw in rows.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final rowCode = row['code']?.toString().trim() ?? '';
      final workshopId = row['workshop_id']?.toString().trim() ?? '';
      if ((preferredWorkshopId.isNotEmpty &&
              workshopId == preferredWorkshopId) ||
          rowCode == selectedCode ||
          workshopId == selectedCode) {
        selected = row;
        break;
      }
    }
    if (selected == null) return null;

    final workshopId = selected['workshop_id']?.toString().trim() ?? '';
    final publicCode = selected['code']?.toString().trim() ?? '';
    if (workshopId.isEmpty || publicCode.isEmpty) return null;
    await prefs.setString('selected_supabase_workshop_id', workshopId);
    await prefs.setString('workshop_code', publicCode);
    return _buildWorkshopSnapshot(
      user: user,
      workshop: {
        'id': workshopId,
        'code': publicCode,
        'join_code': publicCode,
        'name': selected['name']?.toString() ?? '',
      },
      role: 'admin',
      permissions: const <String, dynamic>{},
      blocked: false,
    );
  }

  Future<bool> _isCurrentUserApplicationAdmin() async {
    return AppAdminStatusService.instance.isCurrentUserAdmin();
  }
}
