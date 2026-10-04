import 'dart:async';
import 'dart:convert';

import 'package:database_data/sql_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_admin_status_service.dart';

class SupabaseCatalogSyncService {
  SupabaseCatalogSyncService._internal();

  static final SupabaseCatalogSyncService _instance =
      SupabaseCatalogSyncService._internal();

  factory SupabaseCatalogSyncService() => _instance;

  static const int _maxChunkCharacters = 180000;

  final SqlDatabase _db = SqlDatabase();

  Future<void>? _activeUpload;
  bool _uploadQueued = false;
  Future<void>? _activeDownload;
  RealtimeChannel? _catalogChannel;
  String? _catalogChannelName;
  void Function()? _onCatalogChanged;

  String lastCatalogUploadSummary = '';
  String lastCatalogDownloadSummary = '';

  SupabaseClient get _client => Supabase.instance.client;

  bool get isSignedIn => _client.auth.currentUser != null;

  /// This is checked against Supabase itself. A local Firebase role or a
  /// locally edited preference is not sufficient to publish the shared
  /// catalogue.
  Future<bool> isCurrentUserAppAdmin() async {
    return AppAdminStatusService.instance.isCurrentUserAdmin();
  }

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

  Future<void> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    try {
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      if (response.user == null) {
        throw Exception('تعذر تسجيل الدخول إلى Supabase عبر Google.');
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
    if (!await isCurrentUserAppAdmin()) {
      throw Exception('رفع الكتالوج المركزي متاح لمدير التطبيق فقط.');
    }

    // Keep the local SQLite change log clean after the central upload. These
    // rows are deliberately not part of workshop_sync_rows anymore.
    final pendingBeforeUpload = await _db.exportPendingCloudChanges(
      allowedTables: SqlDatabase.catalogTables.toSet(),
    );

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

    final catalogAcknowledgements = pendingBeforeUpload.acknowledgements
        .where((ack) => SqlDatabase.catalogTables.contains(ack.table))
        .toList(growable: false);
    await _db.acknowledgePendingCloudChanges(catalogAcknowledgements);

    lastCatalogUploadSummary =
        'الألوان: ${tableRowCounts['Colors'] ?? 0}، '
        'البروفيلات: ${tableRowCounts['Sections'] ?? 0}، '
        'مركبات الستائر: ${tableRowCounts['ShutterComponents'] ?? 0}';
  }

  Future<void> downloadGlobalCatalog({bool allowMissing = false}) {
    final activeDownload = _activeDownload;
    if (activeDownload != null) return activeDownload;

    final task = _performDownload(allowMissing: allowMissing);
    _activeDownload = task;
    unawaited(
      task
          .whenComplete(() {
            if (identical(_activeDownload, task)) _activeDownload = null;
          })
          .catchError((_) {}),
    );
    return task;
  }

  Future<void> _performDownload({required bool allowMissing}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول إلى Supabase قبل تنزيل الكتالوج.');
    }

    final manifest = await _client
        .from('catalog_manifest')
        .select()
        .eq('id', 'latest')
        .maybeSingle();
    if (manifest == null) {
      if (allowMissing) return;
      throw Exception('لم ينشر مدير التطبيق الكتالوج المركزي بعد.');
    }

    if (manifest['status']?.toString() != 'completed') {
      throw Exception(
        'الكتالوج المركزي قيد الرفع أو غير مكتمل؛ لن يتم تنزيل بيانات جزئية.',
      );
    }

    final versionId = manifest['version_id']?.toString() ?? '';
    if (versionId.isEmpty) {
      throw StateError('مؤشر الكتالوج المركزي لا يحتوي على نسخة صالحة.');
    }

    // Older catalog manifests incorrectly included workshop-owned price
    // tables (including AccessoryColorPrices). They must be ignored during a
    // global catalog download, otherwise every phone either rejects the
    // manifest or overwrites its own workshop prices.
    final tables = _readStringList(
      manifest['tables'],
    ).where(SqlDatabase.catalogTables.contains).toList(growable: false);
    final expectedRows = _readIntMap(manifest['table_row_counts']);
    final expectedChunks = _readIntMap(manifest['chunk_counts']);
    if (tables.isEmpty || expectedRows.isEmpty) {
      throw StateError('بيانات تعريف الكتالوج المركزي فارغة.');
    }
    if (tables.isEmpty) {
      throw StateError('الكتالوج المركزي لا يحتوي على جداول كتالوج صالحة.');
    }

    final chunks = <Map<String, dynamic>>[];
    const pageSize = 500;
    var offset = 0;
    while (true) {
      final page = await _client
          .from('catalog_chunks')
          .select('table_name,chunk_index,total_chunks,row_count,payload')
          .eq('version_id', versionId)
          // Do not fetch legacy workshop-price chunks from old manifests.
          // They are not part of the global catalogue and would otherwise be
          // treated as invalid chunks or overwrite local workshop prices.
          .inFilter('table_name', tables)
          .order('table_name')
          .order('chunk_index')
          .range(offset, offset + pageSize - 1);
      final pageRows = List<Map<String, dynamic>>.from(page);
      chunks.addAll(pageRows);
      if (pageRows.length < pageSize) break;
      offset += pageRows.length;
    }
    if (chunks.isEmpty)
      throw StateError('الكتالوج المركزي لا يحتوي على أجزاء.');

    final catalogData = <String, dynamic>{
      for (final table in tables) table: <dynamic>[],
    };
    final actualChunks = <String, int>{};
    for (final chunk in chunks) {
      final table = chunk['table_name']?.toString() ?? '';
      final payload = chunk['payload'];
      if (!catalogData.containsKey(table) || payload is! List) {
        throw StateError('جزء غير صالح في الكتالوج المركزي.');
      }
      final rowCount = (chunk['row_count'] as num?)?.toInt();
      if (rowCount == null || rowCount != payload.length) {
        throw StateError('عدد سجلات جزء الكتالوج غير صحيح في جدول $table.');
      }
      final totalChunks = (chunk['total_chunks'] as num?)?.toInt();
      if (totalChunks == null || totalChunks != (expectedChunks[table] ?? -1)) {
        throw StateError('عدد أجزاء الكتالوج غير صحيح في جدول $table.');
      }
      (catalogData[table] as List).addAll(payload);
      actualChunks[table] = (actualChunks[table] ?? 0) + 1;
    }

    for (final table in tables) {
      final actualRows = (catalogData[table] as List).length;
      if (actualRows != (expectedRows[table] ?? -1) ||
          (actualChunks[table] ?? 0) != (expectedChunks[table] ?? -1)) {
        throw StateError('الكتالوج المركزي غير مكتمل في جدول $table.');
      }
    }

    await _db.importGlobalCatalog(catalogData);
    final local = await _db.db;
    if (local != null) {
      await local.execute(
        'CREATE TABLE IF NOT EXISTS CatalogDownloadState (id INTEGER PRIMARY KEY, version TEXT NOT NULL)',
      );
      await local.rawInsert(
        'INSERT OR REPLACE INTO CatalogDownloadState (id, version) VALUES (1, ?)',
        [versionId],
      );
    }
    lastCatalogDownloadSummary =
        'تم تنزيل الكتالوج المركزي: ${expectedRows['Colors'] ?? 0} لونًا، '
        '${expectedRows['Sections'] ?? 0} بروفايل.';
  }

  /// On restart only fetch catalogue chunks when the published version changed.
  Future<void> refreshIfChanged() async {
    final manifest = await _client
        .from('catalog_manifest')
        .select('version_id,status')
        .eq('id', 'latest')
        .maybeSingle();
    if (manifest == null || manifest['status'] != 'completed') return;
    final local = await _db.db;
    if (local == null) return;
    await local.execute(
      'CREATE TABLE IF NOT EXISTS CatalogDownloadState (id INTEGER PRIMARY KEY, version TEXT NOT NULL)',
    );
    final saved = await local.query('CatalogDownloadState', where: 'id = 1');
    final sections = await local.query('Sections', columns: ['id'], limit: 1);
    if (saved.isNotEmpty &&
        saved.first['version'] == manifest['version_id'] &&
        sections.isNotEmpty)
      return;
    await downloadGlobalCatalog(allowMissing: true);
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, int> _readIntMap(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, int>{};
    for (final entry in value.entries) {
      final number = entry.value;
      if (number is num) result[entry.key.toString()] = number.toInt();
    }
    return result;
  }

  void startRealtime({void Function()? onDataChanged}) {
    _onCatalogChanged = onDataChanged;
    final user = _client.auth.currentUser;
    if (user == null) return;

    const channelName = 'global_catalog_manifest';
    if (_catalogChannelName == channelName && _catalogChannel != null) return;
    final oldChannel = _catalogChannel;
    if (oldChannel != null) unawaited(_client.removeChannel(oldChannel));

    _catalogChannelName = channelName;
    _catalogChannel = _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'catalog_manifest',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: 'latest',
          ),
          callback: (_) => unawaited(_refreshAfterRealtimeChange()),
        )
        .subscribe();
  }

  Future<void> _refreshAfterRealtimeChange() async {
    try {
      await downloadGlobalCatalog();
      _onCatalogChanged?.call();
    } catch (error) {
      // A transient event during an upload must not terminate the Realtime
      // listener. The next manifest event or app resume retries the download.
      print('Central catalog realtime refresh failed: $error');
    }
  }

  void stopRealtime() {
    final channel = _catalogChannel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    _catalogChannel = null;
    _catalogChannelName = null;
    _onCatalogChanged = null;
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
