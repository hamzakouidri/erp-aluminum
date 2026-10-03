import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';
import 'order_notification_service.dart';
import 'supabase_workshop_sync_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

class WorkerPushNotificationService {
  WorkerPushNotificationService._();
  static final WorkerPushNotificationService instance =
      WorkerPushNotificationService._();

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  bool _initialized = false;
  void Function(Map<String, dynamic>)? _notificationTapHandler;
  Map<String, dynamic>? _pendingNotificationData;

  bool get _supported =>
      kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  Future<void> initialize() async {
    if (_initialized || !_supported) return;
    _initialized = true;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await _registerToken(await messaging.getToken());
    _tokenSubscription = messaging.onTokenRefresh.listen(_registerToken);
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.session != null) {
        unawaited(_registerCurrentTokenWithRetry());
      }
    });

    OrderNotificationService().onNotificationTap = _handleNotificationTap;
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(_syncThenHandleNotificationTap(message.data));
    });
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      unawaited(_syncThenHandleNotificationTap(initialMessage.data));
    }

    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_downloadLatestWorkshopData());
      final notification = message.notification;
      OrderNotificationService().showAssignmentNotification(
        title: notification?.title ?? 'مهمة جديدة',
        body: notification?.body ?? 'تم إسناد عمل جديد إليك',
        data: message.data,
      );
    });
  }

  void setNotificationTapHandler(void Function(Map<String, dynamic>) handler) {
    _notificationTapHandler = handler;
    final pending = _pendingNotificationData;
    if (pending != null) {
      _pendingNotificationData = null;
      handler(pending);
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    final handler = _notificationTapHandler;
    if (handler == null) {
      _pendingNotificationData = Map<String, dynamic>.from(data);
      return;
    }
    handler(Map<String, dynamic>.from(data));
  }

  Future<void> _syncThenHandleNotificationTap(Map<String, dynamic> data) async {
    await _downloadLatestWorkshopData();
    _handleNotificationTap(data);
  }

  Future<void> _downloadLatestWorkshopData() async {
    try {
      final sync = SupabaseWorkshopSyncService();
      final ready = await sync.ensureStarted(
        timeout: const Duration(seconds: 15),
      );
      if (ready) await sync.downloadWorkshopData();
    } catch (error) {
      debugPrint('Push notification sync failed: $error');
    }
  }

  Future<void> refreshRegistration() async {
    if (!_supported) return;
    await initialize();
    await _registerCurrentTokenWithRetry();
  }

  Future<void> _registerCurrentTokenWithRetry() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await _registerToken(await FirebaseMessaging.instance.getToken());
        final user = Supabase.instance.client.auth.currentUser;
        final workshopId = SupabaseWorkshopSyncService().currentWorkshopUuid;
        if (user != null && workshopId.isNotEmpty) return;
      } catch (error) {
        debugPrint('Push token registration attempt failed: $error');
      }
      await Future<void>.delayed(Duration(seconds: attempt + 1));
    }
  }

  Future<void> _registerToken(String? token) async {
    final user = Supabase.instance.client.auth.currentUser;
    final workshopId = SupabaseWorkshopSyncService().currentWorkshopUuid;
    if (token == null || token.isEmpty || user == null || workshopId.isEmpty) {
      return;
    }
    await Supabase.instance.client.from('device_push_tokens').upsert({
      'user_id': user.id,
      'workshop_id': workshopId,
      'token': token,
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  Future<void> sendAssignment({
    required String workshopId,
    required String workerUid,
    required int orderId,
    required int orderNumber,
    required int quantity,
  }) async {
    if (workshopId.trim().isEmpty || workerUid.trim().isEmpty) return;
    final response = await Supabase.instance.client.functions.invoke(
      'send-worker-assignment',
      body: {
        'workshop_id': workshopId,
        'worker_uids': [workerUid],
        'order_id': orderId,
        'order_number': orderNumber,
        'quantity': quantity,
      },
    );
    _verifyPushResponse(response.data);
  }

  Future<Map<String, bool>> loadPreferences(Iterable<String> eventTypes) async {
    final user = Supabase.instance.client.auth.currentUser;
    final defaults = {for (final type in eventTypes) type: true};
    if (user == null) return defaults;
    final rows = await Supabase.instance.client
        .from('notification_preferences')
        .select('event_type,enabled')
        .eq('user_id', user.id);
    for (final row in rows) {
      final type = row['event_type']?.toString() ?? '';
      if (defaults.containsKey(type)) defaults[type] = row['enabled'] == true;
    }
    return defaults;
  }

  Future<void> savePreference(String eventType, bool enabled) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await Supabase.instance.client.from('notification_preferences').upsert({
      'user_id': user.id,
      'event_type': eventType,
      'enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> sendManagerEvent({
    required String eventType,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    final workshopId = SupabaseWorkshopSyncService().currentWorkshopUuid;
    if (workshopId.isEmpty) return;
    final response = await Supabase.instance.client.functions.invoke(
      'send-worker-assignment',
      body: {
        'workshop_id': workshopId,
        'audience': 'managers',
        'event_type': eventType,
        'title': title,
        'body': body,
        'data': data,
      },
    );
    _verifyPushResponse(response.data);
  }

  void _verifyPushResponse(dynamic data) {
    if (data is! Map) return;
    final failed = (data['failed'] as num?)?.toInt() ?? 0;
    final sent = (data['sent'] as num?)?.toInt() ?? 0;
    if (failed > 0 || sent == 0) {
      throw StateError(
        'تعذر إرسال إشعار FCM: ${data['errors'] ?? data['error'] ?? data}',
      );
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
    _tokenSubscription = null;
    _authSubscription = null;
    _initialized = false;
  }
}
