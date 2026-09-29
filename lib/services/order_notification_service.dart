import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages real-time order-event notifications within the workshop.
///
/// **How it works:**
/// 1. When any user saves a new order (or edits one), they call
///    [broadcastOrderEvent]. This publishes a Supabase Realtime
///    *Broadcast* message on the channel `order_events_{workshopUuid}`.
/// 2. Every connected device in the same workshop listens on that channel.
///    When the event arrives, [_handleIncomingEvent] shows a local
///    notification with sound.
///
/// **Platform support:**
/// - Android & iOS : flutter_local_notifications works fully.
/// - Windows/Linux : flutter_local_notifications shows a system tray toast
///   on Windows (requires NuGet plug-in - detected at runtime). Gracefully
///   falls back to a debug print if the plugin is not available.
/// - Web : not supported by flutter_local_notifications; we skip silently.
class OrderNotificationService {
  OrderNotificationService._internal();
  static final OrderNotificationService _instance =
      OrderNotificationService._internal();
  factory OrderNotificationService() => _instance;

  // ── state ────────────────────────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  RealtimeChannel? _channel;
  String? _currentWorkshopUuid;
  String _myDeviceId = '';
  bool _initialized = false;
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
    if (workshopUuid.isEmpty) return;
    if (_currentWorkshopUuid == workshopUuid && _channel != null) return;

    await _unsubscribe();
    _currentWorkshopUuid = workshopUuid;

    try {
      final client = Supabase.instance.client;
      _channel = client
          .channel('order_events_$workshopUuid')
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
          });
      debugPrint('OrderNotif: subscribed to order_events_$workshopUuid');
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
    if (workshopUuid.isEmpty) return;
    try {
      if (_myDeviceId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        _myDeviceId = prefs.getString('device_id') ?? '';
      }
      final client = Supabase.instance.client;
      final channel = client.channel('order_events_$workshopUuid');
      await channel.sendBroadcastMessage(
        event: isNew ? 'new_order' : 'edit_order',
        payload: {
          'client_name': clientName,
          'order_code': orderCode,
          'author': authorName,
          'sender_device_id': _myDeviceId,
          'sender_user_id': Supabase.instance.client.auth.currentUser?.id ?? '',
          'ts': DateTime.now().toUtc().toIso8601String(),
        },
      );
      debugPrint('OrderNotif: broadcast sent (${isNew ? 'new' : 'edit'})');
    } catch (e) {
      debugPrint('OrderNotif: broadcast failed – $e');
    }
  }

  // ── private helpers ────────────────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'open');

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
      linux: linuxSettings,
    );

    try {
      await _plugin.initialize(initSettings);
      // Request Android 13+ permission
      if (!kIsWeb && Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
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
      // Event originated from this device; ignore so the author isn't pinged.
      return;
    }

    final clientName = payload['client_name']?.toString() ?? '';
    final orderCode = payload['order_code']?.toString() ?? '';
    final author = payload['author']?.toString() ?? '';

    final title = isNew ? '📋 طلبية جديدة' : '✏️ تعديل طلبية';
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
        'order_events',
        'إشعارات الطلبيات',
        channelDescription: 'إشعارات عند إضافة أو تعديل طلبية',
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
    _currentWorkshopUuid = null;
  }

  // ── helpers for callers ────────────────────────────────────────────────────

  /// Reads the current workshop UUID from SharedPreferences.
  static Future<String> readWorkshopUuid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Supabase workshop sync stores uuid under this key pattern.
      // We look for any key matching supabase_workshop_uuid_*.
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith('supabase_workshop_uuid_'));
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
