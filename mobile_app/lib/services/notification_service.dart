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
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // Request notification permission on Android 13+.
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
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
