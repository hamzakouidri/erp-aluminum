import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const accountCachePrefix = 'supabase_account_cache_v1_';

Map<String, dynamic>? readOfflineAccount(SharedPreferences prefs, String userId) {
  if (userId.isEmpty) return null;
  final raw = prefs.getString('$accountCachePrefix$userId');
  if (raw == null || raw.isEmpty) return null;
  try {
    final value = jsonDecode(raw);
    if (value is! Map || value['userId'] != userId) return null;
    return Map<String, dynamic>.from(value);
  } on FormatException {
    return null;
  }
}
