import 'package:supabase_flutter/supabase_flutter.dart';

import '../settings/app_settings.dart';

/// Session-level cache for the application-administrator UI flag.
///
/// RLS remains the security authority. This cache only prevents independent
/// Flutter services from repeatedly selecting the same one-row table.
class AppAdminStatusService {
  AppAdminStatusService._();

  static final AppAdminStatusService instance = AppAdminStatusService._();

  static const Duration _cacheDuration = Duration(minutes: 10);

  String? _cachedUserId;
  bool? _cachedValue;
  DateTime? _cachedAt;
  Future<bool>? _inFlight;
  String? _inFlightUserId;

  Future<bool> isCurrentUserAdmin({bool forceRefresh = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      clear();
      return false;
    }

    if (isApplicationAdminEmail(user.email)) {
      _store(user.id, true);
      return true;
    }

    final cachedAt = _cachedAt;
    if (!forceRefresh &&
        _cachedUserId == user.id &&
        _cachedValue != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheDuration) {
      return _cachedValue!;
    }

    final activeLoad = _inFlight;
    if (activeLoad != null && _inFlightUserId == user.id) return activeLoad;

    final load = _readFromServer(user.id);
    _inFlight = load;
    _inFlightUserId = user.id;
    try {
      final value = await load;
      if (Supabase.instance.client.auth.currentUser?.id == user.id) {
        _store(user.id, value);
      }
      return value;
    } finally {
      if (identical(_inFlight, load)) {
        _inFlight = null;
        _inFlightUserId = null;
      }
    }
  }

  Future<bool> _readFromServer(String userId) async {
    final row = await Supabase.instance.client
        .from('app_admins')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  void _store(String userId, bool value) {
    _cachedUserId = userId;
    _cachedValue = value;
    _cachedAt = DateTime.now();
  }

  void clear() {
    _cachedUserId = null;
    _cachedValue = null;
    _cachedAt = null;
    _inFlight = null;
    _inFlightUserId = null;
  }
}
