import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/settings/app_settings.dart';
import 'dart:math' as math;

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
      };
}

class SupabaseAccountService {
  SupabaseAccountService._();

  static final SupabaseAccountService _instance = SupabaseAccountService._();

  factory SupabaseAccountService() => _instance;

  SupabaseClient get _client => Supabase.instance.client;

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

  Future<SupabaseAccountSnapshot?> loadCurrentAccount() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final admin = await _client
        .from('app_admins')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();
    final isApplicationAdmin =
        admin != null || isApplicationAdminEmail(user.email);

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
      Map<String, dynamic>? selectedMember;
      Map<String, dynamic>? selectedWorkshop;

      for (final member in membershipRows) {
        final workshop = workshopById[member['workshop_id'].toString()];
        if (workshop == null) continue;
        final workshopCode = workshop['code']?.toString().trim() ?? '';
        final workshopJoinCode =
            workshop['join_code']?.toString().trim() ?? '';
        if (preferredCode.isNotEmpty &&
            (workshop['id']?.toString() == preferredCode ||
                workshopCode == preferredCode ||
                workshopJoinCode == preferredCode)) {
          selectedMember = member;
          selectedWorkshop = workshop;
          break;
        }
      }

      // A normal worker/manager has one membership. For an app administrator
      // with several memberships, use the most recently returned one when no
      // previous workshop choice exists; the next load will persist that code.
      if (selectedMember == null) {
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

    if (isApplicationAdmin) {
      // Some migrated owners have the real workshop but no corresponding
      // membership row yet. Resolve the owned workshop before falling back to
      // the synthetic application-admin account, otherwise its user UUID can
      // leak into the workshop-code field.
      try {
        final ownedWorkshop = await _client
            .from('workshops')
            .select('id,code,name,join_code')
            .eq('owner_uid', user.id)
            .limit(1)
            .maybeSingle();
        if (ownedWorkshop != null) {
          return _buildWorkshopSnapshot(
            user: user,
            workshop: Map<String, dynamic>.from(ownedWorkshop),
            role: 'admin',
            permissions: const <String, dynamic>{},
            blocked: false,
          );
        }
      } catch (_) {
        // Keep the synthetic admin fallback for older/incomplete schemas.
      }
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
    final subscription = await _client
        .from('workshop_subscriptions')
        .select(
          'status,plan_type,starts_at,ends_at,max_users,max_systems,max_profiles',
        )
        .eq('workshop_id', workshopId)
        .maybeSingle();

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
        'set_my_workshop_join_code',
      ]) {
        final nested = _shortPublicCode(value[key]);
        if (nested.isNotEmpty) return nested;
      }
    }
    if (value is List && value.length == 1) {
      return _shortPublicCode(value.first);
    }
    final code = value?.toString().trim() ?? '';
    return RegExp(r'^[A-Za-z0-9]{1,7}$').hasMatch(code) ? code : '';
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
    return code;
  }

  Future<String> _resolveDisplayName({
    required String workshopId,
    required String workshopCode,
    required String storedName,
  }) async {
    String clean(dynamic value) => value?.toString().trim() ?? '';
    final directName = clean(storedName);
    if (directName.isNotEmpty && directName != workshopCode) {
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
        if (profileName.isNotEmpty && profileName != workshopCode) {
          return profileName;
        }
      }
    } catch (_) {
      // RLS or an older schema can omit the optional profile row.
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedName = clean(prefs.getString('workshop_name'));
    if (cachedName.isNotEmpty && cachedName != workshopCode) {
      return cachedName;
    }
    // A workshop code is an identifier, not a display name. Keep the name
    // empty so the UI can show a neutral fallback instead of duplicating the
    // technical code as the workshop title.
    return directName == workshopCode ? '' : directName;
  }

  Future<List<Map<String, dynamic>>> fetchAdminWorkshops() async {
    final rows = await _client.rpc('list_admin_workshops');
    if (rows is! List) return <Map<String, dynamic>>[];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
