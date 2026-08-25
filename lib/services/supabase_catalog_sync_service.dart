import 'dart:async';
import 'dart:convert';

import 'package:database_data/sql_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseCatalogSyncService {
  SupabaseCatalogSyncService._internal();

  static final SupabaseCatalogSyncService _instance =
      SupabaseCatalogSyncService._internal();

  factory SupabaseCatalogSyncService() => _instance;

  static const int _maxChunkCharacters = 180000;

  final SqlDatabase _db = SqlDatabase();

  Future<void>? _activeUpload;
  bool _uploadQueued = false;

  String lastCatalogUploadSummary = '';

  SupabaseClient get _client => Supabase.instance.client;

  bool get isSignedIn => _client.auth.currentUser != null;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) {
        throw Exception('تعذر تسجيل الدخول إلى Supabase.');
      }
    } on AuthException catch (error) {
      throw Exception(_describeAuthError(error));
    }
  }

  Future<void> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) {
        throw Exception('تعذر إنشاء حساب Supabase.');
      }
      if (_client.auth.currentUser == null) {
        throw Exception(
          'تم إنشاء الحساب، لكن Supabase يطلب تأكيد البريد قبل الدخول. '
          'عطّل Confirm email مؤقتاً أو أكد البريد ثم أعد المحاولة.',
        );
      }
    } on AuthException catch (error) {
      throw Exception(_describeAuthError(error));
    }
  }

  String _describeAuthError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'البريد أو كلمة المرور غير صحيحة، أو الحساب غير موجود في Supabase.';
    }
    if (message.contains('email not confirmed')) {
      return 'الحساب موجود لكن البريد غير مؤكد. عطّل Confirm email مؤقتاً من Supabase أو أكد البريد.';
    }
    if (message.contains('signup is disabled')) {
      return 'إنشاء الحسابات معطل في Supabase. فعّل Email provider من Auth > Providers.';
    }
    if (message.contains('user already registered') ||
        message.contains('already registered')) {
      return 'هذا البريد موجود مسبقاً. استعمل زر دخول بدل إنشاء حساب.';
    }
    return 'خطأ مصادقة Supabase: ${error.message}';
  }

  Future<void> uploadGlobalCatalog() {
    final activeUpload = _activeUpload;
    if (activeUpload != null) {
      _uploadQueued = true;
      return activeUpload;
    }

    final task = _runSerializedUpload();
    _activeUpload = task;
    return task;
  }

  Future<void> _runSerializedUpload() async {
    try {
      do {
        _uploadQueued = false;
        await _performUpload();
      } while (_uploadQueued);
    } finally {
      _activeUpload = null;
    }
  }

  Future<void> _performUpload() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول إلى Supabase قبل رفع الكتالوج.');
    }

    final catalogData = await _db.exportGlobalCatalog();
    for (final requiredTable in const ['Colors', 'ShutterComponents']) {
      if (catalogData[requiredTable] is! List) {
        throw StateError(
          'تعذر قراءة جدول $requiredTable محلياً؛ لن يتم رفع كتالوج ناقص.',
        );
      }
    }

    final versionId =
        'catalog_${DateTime.now().toUtc().microsecondsSinceEpoch}_${user.id}';
    final tableRowCounts = <String, int>{};
    final chunkCounts = <String, int>{};
    final chunkRows = <Map<String, dynamic>>[];

    for (final entry in catalogData.entries) {
      final rows = entry.value;
      if (rows is! List) continue;
      tableRowCounts[entry.key] = rows.length;

      final chunks = _chunkRows(rows);
      chunkCounts[entry.key] = chunks.length;
      for (var i = 0; i < chunks.length; i++) {
        chunkRows.add({
          'version_id': versionId,
          'table_name': entry.key,
          'chunk_index': i,
          'total_chunks': chunks.length,
          'row_count': chunks[i].length,
          'payload': chunks[i],
        });
      }
    }

    if (chunkRows.isEmpty) {
      throw StateError('الكتالوج المحلي فارغ؛ لم يتم رفع أي شيء.');
    }

    await _client.from('catalog_manifest').upsert({
      'id': 'latest',
      'version_id': versionId,
      'status': 'uploading',
      'tables': catalogData.keys.toList(),
      'table_row_counts': tableRowCounts,
      'chunk_counts': chunkCounts,
      'uploader_uid': user.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    const batchSize = 40;
    for (var start = 0; start < chunkRows.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, chunkRows.length);
      await _client
          .from('catalog_chunks')
          .insert(chunkRows.sublist(start, end));
    }

    final uploadedChunks = await _client
        .from('catalog_chunks')
        .select('table_name,row_count,total_chunks,chunk_index')
        .eq('version_id', versionId);

    final verifiedRows = <String, int>{};
    final verifiedChunks = <String, int>{};
    for (final row in uploadedChunks) {
      final table = row['table_name']?.toString() ?? '';
      if (table.isEmpty) continue;
      verifiedRows[table] =
          (verifiedRows[table] ?? 0) +
          ((row['row_count'] as num?)?.toInt() ?? 0);
      verifiedChunks[table] = (verifiedChunks[table] ?? 0) + 1;
    }

    for (final entry in tableRowCounts.entries) {
      if ((verifiedRows[entry.key] ?? -1) != entry.value ||
          (verifiedChunks[entry.key] ?? -1) != (chunkCounts[entry.key] ?? 0)) {
        throw StateError(
          'تعذر تأكيد رفع جدول ${entry.key}. '
          'المحلي ${entry.value}، السحابة ${verifiedRows[entry.key] ?? 0}.',
        );
      }
    }

    await _client.from('catalog_manifest').upsert({
      'id': 'latest',
      'version_id': versionId,
      'status': 'completed',
      'tables': catalogData.keys.toList(),
      'table_row_counts': tableRowCounts,
      'chunk_counts': chunkCounts,
      'uploader_uid': user.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    await _client.from('catalog_chunks').delete().neq('version_id', versionId);

    lastCatalogUploadSummary =
        'الألوان: ${tableRowCounts['Colors'] ?? 0}، '
        'البروفيلات: ${tableRowCounts['Sections'] ?? 0}، '
        'مركبات الستائر: ${tableRowCounts['ShutterComponents'] ?? 0}';
  }

  List<List<dynamic>> _chunkRows(List<dynamic> rows) {
    final chunks = <List<dynamic>>[];
    var current = <dynamic>[];
    var currentSize = 2;

    for (final row in rows) {
      final rowSize = jsonEncode(row).length + 1;
      if (current.isNotEmpty && currentSize + rowSize > _maxChunkCharacters) {
        chunks.add(current);
        current = <dynamic>[];
        currentSize = 2;
      }
      current.add(row);
      currentSize += rowSize;
    }

    if (current.isNotEmpty || rows.isEmpty) {
      chunks.add(current);
    }
    return chunks;
  }
}
