import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Lightweight wrapper around [FlutterLocalNotificationsPlugin] for showing
/// local push notifications when a nearby peer is discovered.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'nearby_alerts';
  static const _channelName = 'Nearby Alerts';
  static const _channelDescription = 'Notifications when someone is nearby';

  /// Initialise the plugin and create the Android notification channel.
  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Request notification permission on Android 13+.
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();

      // Explicitly create the FCM notification channel so the OS can
      // display system notifications even if the app never showed one yet.
      const alertsChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      );
      await android?.createNotificationChannel(alertsChannel);
    }
  }

  /// Create the notification channel for the background/foreground service.
  /// Android requires the channel to exist before the service starts.
  /// Uses a standalone plugin instance so it works before [init] is called.
  static Future<void> createDiscoveryChannel() async {
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'knkt_discovery',
        'Background Discovery',
        description: 'Keeps Bluetooth active in the background',
        importance: Importance.low,
      );
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  /// Show a notification telling the user that [peerName] is nearby.
  Future<void> showNearbyNotification(String peerName) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      peerName.hashCode, // unique-ish ID per peer
      'Someone nearby!',
      '$peerName is around you',
      details,
    );
    debugPrint('[knkt] notification: $peerName is nearby');
  }

  /// Show a general-purpose notification (used by FCM handlers).
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(id, title, body, details);
    debugPrint('[knkt] notification shown: $title');
  }
}
