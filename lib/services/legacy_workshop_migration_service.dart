import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;

/// The identity and workshop information that existed before the move to
/// Supabase. Firebase IDs are intentionally kept as text here: they are not
/// valid foreign keys for Supabase auth.users.
class LegacyWorkshopContext {
  const LegacyWorkshopContext({
    required this.legacyUserId,
    required this.legacyWorkshopId,
    required this.email,
    required this.role,
    required this.workshopCode,
    required this.workshopName,
    required this.permissions,
    required this.blocked,
    required this.members,
  });

  final String legacyUserId;
  final String legacyWorkshopId;
  final String email;
  final String role;
  final String workshopCode;
  final String workshopName;
  final Map<String, dynamic> permissions;
  final bool blocked;
  final List<LegacyWorkshopMember> members;

  bool get isManager => role == 'manager' || legacyWorkshopId == legacyUserId;
}

class LegacyWorkshopMember {
  const LegacyWorkshopMember({
    required this.email,
    required this.role,
    required this.permissions,
    required this.blocked,
  });

  final String email;
  final String role;
  final Map<String, dynamic> permissions;
  final bool blocked;
}

/// Reads the old Firebase records without modifying them. The migration is
/// deliberately read-only on Firebase so the old workshop remains a rollback
/// source until the manager verifies the Supabase copy.
class LegacyWorkshopMigrationService {
  LegacyWorkshopMigrationService._();

  static final LegacyWorkshopMigrationService _instance =
      LegacyWorkshopMigrationService._();

  factory LegacyWorkshopMigrationService() => _instance;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<LegacyWorkshopContext?> readCurrentUserContext({
    firebase.User? user,
  }) async {
    final firebaseUser = user ?? firebase.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;

    final userSnapshot = await _firestore
        .collection('users')
        .doc(firebaseUser.uid)
        .get()
        .timeout(const Duration(seconds: 15));
    final userData = userSnapshot.data();
    if (!userSnapshot.exists || userData == null) return null;

    final rawRole = userData['role']?.toString().toLowerCase().trim() ?? '';
    final role = rawRole == 'admin' ? 'manager' : (rawRole.isEmpty ? 'worker' : rawRole);
    var legacyWorkshopId = userData['workshopId']?.toString().trim() ?? '';
    if (legacyWorkshopId.isEmpty && (role == 'manager' || role == 'owner')) {
      legacyWorkshopId = firebaseUser.uid;
    }
    if (legacyWorkshopId.isEmpty) return null;

    var workshopData = <String, dynamic>{};
    final workshopSnapshot = await _firestore
        .collection('workshops')
        .doc(legacyWorkshopId)
        .get()
        .timeout(const Duration(seconds: 15));
    if (workshopSnapshot.exists && workshopSnapshot.data() != null) {
      workshopData = Map<String, dynamic>.from(workshopSnapshot.data()!);
    }

    // A few early versions kept the workshop under the manager UID while the
    // user document held a different/empty workshopId.
    if (workshopData.isEmpty && legacyWorkshopId != firebaseUser.uid) {
      final managerWorkshop = await _firestore
          .collection('workshops')
          .doc(firebaseUser.uid)
          .get()
          .timeout(const Duration(seconds: 15));
      if (managerWorkshop.exists && managerWorkshop.data() != null) {
        legacyWorkshopId = firebaseUser.uid;
        workshopData = Map<String, dynamic>.from(managerWorkshop.data()!);
      }
    }

    final code = (workshopData['joinCode'] ??
            workshopData['code'] ??
            userData['joinCode'] ??
            legacyWorkshopId)
        .toString()
        .trim();
    if (code.isEmpty) return null;

    final name = (workshopData['name'] ??
            workshopData['workshopName'] ??
            workshopData['displayName'] ??
            workshopData['title'] ??
            userData['workshopName'] ??
            userData['workshop_name'] ??
            '')
        .toString()
        .trim();
    final permissions = _readMap(userData['permissions']);
    final members = <LegacyWorkshopMember>[];
    if (role == 'manager' || legacyWorkshopId == firebaseUser.uid) {
      final memberSnapshot = await _firestore
          .collection('users')
          .where('workshopId', isEqualTo: legacyWorkshopId)
          .get()
          .timeout(const Duration(seconds: 20));
      for (final document in memberSnapshot.docs) {
        if (document.id == firebaseUser.uid) continue;
        final data = document.data();
        final email = (data['email'] ?? '').toString().trim().toLowerCase();
        if (email.isEmpty) continue;
        members.add(
          LegacyWorkshopMember(
            email: email,
            role: _normalizeRole(data['role']?.toString()),
            permissions: _readMap(data['permissions']),
            blocked: data['isBlocked'] == true || data['blocked'] == true,
          ),
        );
      }
    }

    return LegacyWorkshopContext(
      legacyUserId: firebaseUser.uid,
      legacyWorkshopId: legacyWorkshopId,
      email: (userData['email'] ?? firebaseUser.email ?? '')
          .toString()
          .trim()
          .toLowerCase(),
      role: role,
      workshopCode: code,
      workshopName: name,
      permissions: permissions,
      blocked: userData['isBlocked'] == true || userData['blocked'] == true,
      members: List.unmodifiable(members),
    );
  }

  static Map<String, dynamic> _readMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _normalizeRole(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'owner':
      case 'manager':
      case 'co_manager':
      case 'admin':
      case 'worker':
        return raw!.toLowerCase().trim();
      default:
        return 'worker';
    }
  }
}
