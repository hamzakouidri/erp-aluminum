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
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    unawaited(_registerCurrentTokenWithRetry());
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
      final type = message.data['type']?.toString() ?? '';
      if (type.startsWith('order_')) {
        unawaited(
          OrderNotificationService().showOrderPushNotification(
            data: message.data,
          ),
        );
        return;
      }
      // The download above applies the new prices and shows the in-app
      // price notification itself; showing this one too would duplicate it.
      if (type == 'prices') return;
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

  bool _registrationInFlight = false;

  /// The token row needs the workshop UUID, which is only known once the
  /// workshop sync has started. On slow networks that takes longer than a few
  /// seconds; the old 4 × 1–4 s retry often gave up first, so the device was
  /// never stored in device_push_tokens and FCM could not reach it while the
  /// app was closed (only the in-app Realtime path worked).
  Future<void> _registerCurrentTokenWithRetry() async {
    if (_registrationInFlight) return;
    _registrationInFlight = true;
    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          final user = Supabase.instance.client.auth.currentUser;
          if (user == null) return;
          final sync = SupabaseWorkshopSyncService();
          if (sync.currentWorkshopUuid.isEmpty) {
            await sync.ensureStarted(timeout: const Duration(seconds: 30));
          }
          if (sync.currentWorkshopUuid.isNotEmpty) {
            await _registerToken(await FirebaseMessaging.instance.getToken());
            debugPrint('Push token registered for this device.');
            return;
          }
        } catch (error) {
          debugPrint('Push token registration attempt failed: $error');
        }
        await Future<void>.delayed(Duration(seconds: 5 * (attempt + 1)));
      }
      debugPrint('Push token registration gave up: no workshop context.');
    } finally {
      _registrationInFlight = false;
    }
  }

  Future<void> _registerToken(String? token) async {
    final user = Supabase.instance.client.auth.currentUser;
    final workshopId = SupabaseWorkshopSyncService().currentWorkshopUuid;
    if (token == null || token.isEmpty || user == null || workshopId.isEmpty) {
      return;
    }
    final platform = kIsWeb ? 'web' : Platform.operatingSystem;
    try {
      // Moves a token previously owned by another account on this phone.
      await Supabase.instance.client.rpc(
        'register_push_token',
        params: {
          'requested_token': token,
          'requested_workshop_id': workshopId,
          'requested_platform': platform,
        },
      );
      return;
    } catch (error) {
      // Older databases without supabase/push_notifications.sql applied.
      debugPrint('register_push_token RPC unavailable, using upsert: $error');
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

  Future<void> sendAssignmentToCurrentWorkshop({
    required String workerUid,
    required int orderId,
    required int orderNumber,
    required int quantity,
  }) async {
    final workshopId = SupabaseWorkshopSyncService().currentWorkshopUuid;
    if (workshopId.isEmpty) return;
    await sendAssignment(
      workshopId: workshopId,
      workerUid: workerUid,
      orderId: orderId,
      orderNumber: orderNumber,
      quantity: quantity,
    );
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

  /// Sends an authoritative order event to every workshop member allowed to
  /// view orders, excluding the user who performed the operation.
  Future<void> sendOrderEvent({
    required String action,
    required int orderId,
    required String orderCode,
    required String clientName,
    String author = '',
  }) async {
    final workshopId = SupabaseWorkshopSyncService().currentWorkshopUuid;
    if (workshopId.isEmpty) return;
    final normalizedAction = switch (action) {
      'created' || 'updated' || 'deleted' => action,
      _ => throw ArgumentError.value(action, 'action'),
    };
    final eventType = 'order_$normalizedAction';
    final title = switch (normalizedAction) {
      'created' => 'طلبية جديدة في الورشة',
      'updated' => 'تم تعديل طلبية',
      _ => 'تم حذف طلبية',
    };
    final displayCode = orderCode.trim().isEmpty
        ? orderId.toString()
        : orderCode.trim();
    final cleanClient = clientName.trim().isEmpty ? 'عميل' : clientName.trim();
    final body =
        '$cleanClient | #$displayCode'
        '${author.trim().isEmpty ? '' : '\nبواسطة: ${author.trim()}'}';
    final eventId =
        '${eventType}_${orderId}_${DateTime.now().microsecondsSinceEpoch}';
    final senderUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final response = await Supabase.instance.client.functions.invoke(
      'send-worker-assignment',
      body: {
        'workshop_id': workshopId,
        'audience': 'order_viewers',
        'event_type': eventType,
        'preference_type': 'orders',
        'title': title,
        'body': body,
        'order_id': orderId,
        'order_number': int.tryParse(displayCode) ?? 0,
        'data': {
          'event_id': eventId,
          'action': normalizedAction,
          'order_id': orderId.toString(),
          'order_code': displayCode,
          'client_name': cleanClient,
          'author': author.trim(),
          'sender_user_id': senderUserId,
        },
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
