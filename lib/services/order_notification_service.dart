import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';

/// Manages real-time order-event notifications within the workshop.
///
/// **How it works:**
/// 1. When any user saves a new order (or edits one), they call
///    [broadcastOrderEvent]. This publishes a Supabase Realtime
///    *Broadcast* message on the channel `order_events_{workshopUuid}`.
/// 2. Every connected device in the same workshop listens on that channel.
///    When the event arrives, [_handleIncomingEvent] shows a local
///    notification with sound.
/// 3. In addition, when background/incremental database sync receives new
///    orders, [showOrderNotificationFromSync] triggers as a secondary guarantee
///    if the device was asleep or temporarily reconnecting.
class OrderNotificationService {
  OrderNotificationService._internal();
  static final OrderNotificationService _instance =
      OrderNotificationService._internal();
  factory OrderNotificationService() => _instance;

  static const String _channelId = 'erp_orders_alert_channel_v2';
  static const String _channelName = 'إشعارات الطلبيات';
  static const String _channelDesc =
      'تنبيهات صوتية فورية عند إضافة أو تعديل الطلبيات في الورشة';

  // ── state ────────────────────────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final Set<String> _recentNotifications = <String>{};

  RealtimeChannel? _channel;
  String? _currentWorkshopUuid;
  String _myDeviceId = '';
  bool _initialized = false;
  bool _isSubscribed = false;
  int _notifId = 0;

  // ── public API ────────────────────────────────────────────────────────────

  /// Call once during app startup (after Supabase is initialized).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _myDeviceId = prefs.getString('device_id') ?? '';
      if (_myDeviceId.isEmpty) {
        _myDeviceId =
            'device_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch % 100000}';
        await prefs.setString('device_id', _myDeviceId);
      }
    } catch (_) {}
    await _initLocalNotifications();
  }

  /// Subscribe to order events for the given [workshopUuid].
  /// Safe to call again when the workshop changes.
  Future<void> subscribeToWorkshop(String workshopUuid) async {
    final cleanUuid = workshopUuid.trim();
    if (cleanUuid.isEmpty) return;
    if (_currentWorkshopUuid == cleanUuid &&
        _channel != null &&
        _isSubscribed) {
      return;
    }

    await _unsubscribe();
    _currentWorkshopUuid = cleanUuid;

    try {
      final client = Supabase.instance.client;
      final ch = client.channel('order_events_$cleanUuid');
      _channel = ch;
      ch
          .onBroadcast(
            event: 'new_order',
            callback: (payload) => _handleIncomingEvent(payload, isNew: true),
          )
          .onBroadcast(
            event: 'edit_order',
            callback: (payload) => _handleIncomingEvent(payload, isNew: false),
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('OrderNotif channel error: $error');
            }
            if (status == RealtimeSubscribeStatus.subscribed) {
              _isSubscribed = true;
            } else if (status == RealtimeSubscribeStatus.closed) {
              _isSubscribed = false;
            }
            debugPrint(
              'OrderNotif: status = $status for order_events_$cleanUuid',
            );
          });
      debugPrint('OrderNotif: subscribed to order_events_$cleanUuid');
    } catch (e) {
      debugPrint('OrderNotif: subscribe failed – $e');
    }
  }

  /// Unsubscribe (e.g. on sign-out).
  Future<void> unsubscribe() => _unsubscribe();

  /// Broadcast an order event so **other** devices receive a notification.
  ///
  /// [isNew] = true when inserting, false when editing.
  /// [clientName] is the display name of the client.
  /// [orderCode] is the order reference number / code.
  /// [authorName] is who triggered the action (optional).
  Future<void> broadcastOrderEvent({
    required String workshopUuid,
    required bool isNew,
    required String clientName,
    required String orderCode,
    String authorName = '',
  }) async {
    final cleanUuid = workshopUuid.trim();
    if (cleanUuid.isEmpty) return;
    try {
      if (_myDeviceId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        _myDeviceId = prefs.getString('device_id') ?? '';
        if (_myDeviceId.isEmpty) {
          _myDeviceId =
              'device_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch % 100000}';
          await prefs.setString('device_id', _myDeviceId);
        }
      }

      // Add our own sent order to dedupe so this device doesn't trigger its own notification
      final dedupeKey = '$orderCode:${isNew ? "new" : "edit"}';
      _recentNotifications.add(dedupeKey);
      Timer(const Duration(seconds: 25), () {
        _recentNotifications.remove(dedupeKey);
      });

      if (_channel == null || _currentWorkshopUuid != cleanUuid) {
        await subscribeToWorkshop(cleanUuid);
      }

      final client = Supabase.instance.client;
      final ch = _channel ?? client.channel('order_events_$cleanUuid');

      final payload = {
        'client_name': clientName,
        'order_code': orderCode,
        'author': authorName,
        'sender_device_id': _myDeviceId,
        'sender_user_id': client.auth.currentUser?.id ?? '',
        'ts': DateTime.now().toUtc().toIso8601String(),
      };

      if (!_isSubscribed) {
        final completer = Completer<void>();
        ch.subscribe((status, [e]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _isSubscribed = true;
            if (!completer.isCompleted) completer.complete();
          }
        });
        await completer.future.timeout(
          const Duration(seconds: 4),
          onTimeout: () {},
        );
      }

      try {
        await ch.sendBroadcastMessage(
          event: isNew ? 'new_order' : 'edit_order',
          payload: payload,
        );
        debugPrint(
          'OrderNotif: broadcast sent successfully (${isNew ? 'new' : 'edit'})',
        );
      } catch (err) {
        debugPrint('OrderNotif: broadcast send error: $err');
      }
    } catch (e) {
      debugPrint('OrderNotif: broadcast failed – $e');
    }
  }

  /// Secondary trigger when incremental sync downloads an order from another device.
  Future<void> showOrderNotificationFromSync({
    required String clientName,
    required String orderCode,
    String author = '',
    bool isNew = true,
  }) async {
    _dispatchNotification(
      clientName: clientName,
      orderCode: orderCode,
      author: author,
      isNew: isNew,
    );
  }

  // ── private helpers ────────────────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'open',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
      linux: linuxSettings,
    );

    try {
      await _plugin.initialize(initSettings);
      if (!kIsWeb && Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.requestNotificationsPermission();
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );
        await android?.createNotificationChannel(channel);
      }
    } catch (e) {
      debugPrint('OrderNotif: local notifications init failed – $e');
    }
  }

  void _handleIncomingEvent(
    Map<String, dynamic> payload, {
    required bool isNew,
  }) {
    final senderDeviceId = payload['sender_device_id']?.toString() ?? '';
    if (senderDeviceId.isNotEmpty && senderDeviceId == _myDeviceId) {
      return;
    }

    final clientName = payload['client_name']?.toString() ?? '';
    final orderCode = payload['order_code']?.toString() ?? '';
    final author = payload['author']?.toString() ?? '';

    _dispatchNotification(
      clientName: clientName,
      orderCode: orderCode,
      author: author,
      isNew: isNew,
    );
  }

  void _dispatchNotification({
    required String clientName,
    required String orderCode,
    required String author,
    required bool isNew,
  }) {
    final dedupeKey = '$orderCode:${isNew ? "new" : "edit"}';
    if (_recentNotifications.contains(dedupeKey)) return;
    _recentNotifications.add(dedupeKey);
    Timer(const Duration(seconds: 25), () {
      _recentNotifications.remove(dedupeKey);
    });

    // 1. Play audible alert chime
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    // 2. Format title and body
    final title = isNew
        ? '📋 طلبية جديدة في الورشة'
        : '✏️ تعديل طلبية في الورشة';
    String body = clientName.isNotEmpty ? clientName : 'عميل';
    if (orderCode.isNotEmpty) body += '  |  #$orderCode';
    if (author.isNotEmpty) body += '\nبواسطة: $author';

    _showLocalNotification(title: title, body: body);
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      );

      await _plugin.show(_notifId++, title, body, details);
      debugPrint('OrderNotif: local notification shown – $title');
    } catch (e) {
      debugPrint('OrderNotif: show notification failed – $e');
    }
  }

  Future<void> _unsubscribe() async {
    final ch = _channel;
    if (ch != null) {
      try {
        await Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
      _channel = null;
    }
    _isSubscribed = false;
    _currentWorkshopUuid = null;
  }

  // ── helpers for callers ────────────────────────────────────────────────────

  /// Reads the current workshop UUID from cache, sync service, or SharedPreferences.
  static Future<String> readWorkshopUuid() async {
    try {
      final syncService = SupabaseWorkshopSyncService();
      if (syncService.currentWorkshopUuid.isNotEmpty) {
        return syncService.currentWorkshopUuid;
      }
      final prefs = await SharedPreferences.getInstance();
      final direct =
          prefs.getString('cached_workshop_uuid') ??
          prefs.getString('selected_supabase_workshop_id') ??
          '';
      if (direct.isNotEmpty) return direct;

      final workshopCode = prefs.getString('workshop_code') ?? '';
      if (workshopCode.isNotEmpty) {
        final codeUuid = prefs.getString(
          'supabase_workshop_uuid_$workshopCode',
        );
        if (codeUuid != null && codeUuid.isNotEmpty) return codeUuid;
      }
      final keys = prefs.getKeys().where(
        (k) => k.startsWith('supabase_workshop_uuid_'),
      );
      if (keys.isEmpty) return '';
      return prefs.getString(keys.first) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Reads the current user's display name from SharedPreferences.
  static Future<String> readUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('workshop_name')?.trim() ??
          prefs.getString('user_display_name')?.trim() ??
          '';
    } catch (_) {
      return '';
    }
  }
}
