import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_admin_status_service.dart';

/// Systems the application owner has not published yet (نشر الأنظمة).
///
/// The owner hides a work system or a profile system that is still being
/// developed; for every other user it then counts as switched off, on top
/// of whatever their workshop selected. The workshop's own selection is
/// kept, so publishing the system brings it back as it was. The list lives
/// in Supabase (`app_system_publication`, see supabase/system_publication.sql),
/// where only an application admin may change it, and is cached on the device
/// for offline use. The owner always sees every system.
class SystemPublicationService {
  SystemPublicationService._();

  static final SystemPublicationService instance = SystemPublicationService._();

  static const _table = 'app_system_publication';
  static const _cacheKey = 'unpublished_system_keys';

  static String modeKey(String modeId) => 'mode:$modeId';

  /// A profile is matched by its code, or by its name when it has none: the
  /// catalogue ids are not guaranteed to be equal on every device.
  static String profileKey({String? code, String? name}) {
    final c = (code ?? '').trim();
    return c.isNotEmpty
        ? 'profile:$c'
        : 'profile:${(name ?? '').trim().toLowerCase()}';
  }

  Set<String>? _hidden;

  /// The unpublished keys as last read (from the server or the cache).
  Future<Set<String>> hiddenKeys() async {
    final cached = _hidden;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _hidden = (prefs.getStringList(_cacheKey) ?? const []).toSet();
    } catch (_) {
      return _hidden = <String>{};
    }
  }

  /// True when the signed-in user is the application owner, who sees and
  /// manages every system.
  Future<bool> isOwner() async {
    try {
      return await AppAdminStatusService.instance.isCurrentUserAdmin();
    } catch (_) {
      return false;
    }
  }

  /// Unpublished keys that apply to this user: none for the owner.
  Future<Set<String>> hiddenForCurrentUser() async =>
      await isOwner() ? <String>{} : await hiddenKeys();

  /// Reads the list from the server. Returns true when it changed.
  Future<bool> refresh() async {
    final before = await hiddenKeys();
    try {
      final rows = await Supabase.instance.client
          .from(_table)
          .select('system_key')
          .eq('published', false)
          .timeout(const Duration(seconds: 10));
      final hidden = {for (final row in rows) row['system_key'].toString()};
      _hidden = hidden;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cacheKey, hidden.toList()..sort());
      return !setEquals(before, hidden);
    } catch (error) {
      // Offline, signed out or the table is not installed yet: keep the
      // cached list.
      debugPrint('System publication not refreshed: $error');
      return false;
    }
  }

  /// Publishes or hides [key]. Only the owner can; the server refuses
  /// anyone else.
  Future<void> setPublished(
    String key, {
    required bool published,
    String label = '',
  }) async {
    await Supabase.instance.client.from(_table).upsert({
      'system_key': key,
      'published': published,
      'label': label,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final hidden = {...await hiddenKeys()};
    if (published) {
      hidden.remove(key);
    } else {
      hidden.add(key);
    }
    _hidden = hidden;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cacheKey, hidden.toList()..sort());
  }

  /// Switches off, in the local catalogue, every profile system hidden from
  /// this user, with its series. Nothing changes for the owner.
  Future<void> applyToProfiles(DatabaseExecutor db) async {
    final hidden = await hiddenForCurrentUser();
    await applyHiddenProfiles(db, hidden);
  }

  /// [applyToProfiles] with a given list, inside a caller's transaction.
  static Future<int> applyHiddenProfiles(
    DatabaseExecutor db,
    Set<String> hidden,
  ) async {
    final profileKeys = hidden.where((k) => k.startsWith('profile:')).toSet();
    if (profileKeys.isEmpty) return 0;
    final columns = (await db.rawQuery(
      'PRAGMA table_info(Profile)',
    )).map((c) => c['name'].toString().toLowerCase()).toSet();
    final rows = await db.query(
      'Profile',
      columns: ['id', 'name', if (columns.contains('code')) 'code'],
    );
    var count = 0;
    for (final row in rows) {
      final key = profileKey(
        code: row['code']?.toString(),
        name: row['name']?.toString(),
      );
      if (!profileKeys.contains(key)) continue;
      final id = row['id'];
      await db.update(
        'Profile',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.update(
        'Series',
        {'is_active': 0},
        where: 'profile_id = ?',
        whereArgs: [id],
      );
      count++;
    }
    return count;
  }

  /// The workshop's remote selection as last applied on this device, so a
  /// hidden profile the workshop had chosen stays chosen in what this device
  /// saves back.
  static Future<Map<String, dynamic>> lastWorkshopSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('last_applied_remote_workshop_systems');
      if (raw == null) return const {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }
}
