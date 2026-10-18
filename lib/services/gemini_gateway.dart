import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The one way the app talks to Gemini.
///
/// By default requests go through the `gemini-proxy` Supabase Edge Function
/// (supabase/functions/gemini-proxy), which holds the API key on the server,
/// checks that the caller belongs to a workshop and applies a daily limit,
/// so no key ships with or is stored in the app. A user who entered their
/// own key in the settings calls Gemini directly with it.
class GeminiGateway {
  GeminiGateway({String personalKey = '', http.Client? client})
    : personalKey = personalKey.trim(),
      _client = client ?? http.Client();

  /// The key the user entered in the settings, if any.
  final String personalKey;
  final http.Client _client;

  static const _api = 'https://generativelanguage.googleapis.com/v1beta';
  static const _function = 'gemini-proxy';
  static const personalKeyPreference = 'app_gemini_api_key';

  bool get usesServer => personalKey.isEmpty;

  /// The gateway for the user's current settings.
  static Future<GeminiGateway> current({http.Client? client}) async {
    var key = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      key = prefs.getString(personalKeyPreference)?.trim() ?? '';
    } catch (_) {}
    return GeminiGateway(personalKey: key, client: client);
  }

  /// The raw models list, or null when it cannot be read.
  Future<Map<String, dynamic>?> listModels() async {
    try {
      if (usesServer) {
        final response = await Supabase.instance.client.functions
            .invoke(_function, body: {'op': 'models'})
            .timeout(const Duration(seconds: 20));
        return _asMap(response.data);
      }
      final response = await _client
          .get(
            Uri.parse('$_api/models?pageSize=200'),
            headers: {'x-goog-api-key': personalKey},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _asMap(utf8.decode(response.bodyBytes));
    } catch (error) {
      debugPrint('Gemini models not listed: $error');
      return null;
    }
  }

  /// Sends a generateContent [body] to [model]. Throws [GeminiException]
  /// with the HTTP status on failure.
  Future<Map<String, dynamic>> generate(
    String model,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (usesServer) {
      try {
        final response = await Supabase.instance.client.functions
            .invoke(
              _function,
              body: {'op': 'generate', 'model': model, 'body': body},
            )
            .timeout(timeout);
        final data = _asMap(response.data);
        if (data == null) throw GeminiException(response.status, 'empty');
        return data;
      } on FunctionException catch (error) {
        throw GeminiException(error.status, error.details?.toString() ?? '');
      }
    }
    final response = await _client
        .post(
          Uri.parse('$_api/models/$model:generateContent'),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': personalKey,
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw GeminiException(response.statusCode, response.body);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// The text of the first candidate, without thought parts.
  static String textOf(Map<String, dynamic> response) {
    final candidate = (response['candidates'] as List?)?.firstOrNull as Map?;
    final parts = (candidate?['content'] as Map?)?['parts'] as List? ?? [];
    return parts
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text']?.toString() ?? '')
        .join()
        .trim();
  }

  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return null;
  }
}

class GeminiException implements Exception {
  GeminiException(this.status, this.details);

  final int status;
  final String details;

  /// The server's daily limit for this user was reached.
  bool get isQuota => status == 429;

  @override
  String toString() => 'Gemini HTTP $status $details';
}
