import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'backend_service.dart';
import 'notification_service.dart';

class FcmService {
  String? _uid;
  final _messaging = FirebaseMessaging.instance;

  Future<void> initialize(
    String uid,
    NotificationService notificationService,
  ) async {
    _uid = uid;

    try {
      // Request notification permission
      final settings = await _messaging.requestPermission();
      debugPrint('[knkt] FCM permission: ${settings.authorizationStatus}');

      // Get token and register with server
      final token = await _messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_registerToken);

      // Handle foreground messages — show a local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('[knkt] FCM foreground message: ${message.data}');
        final connectionId = message.data['connection_id'] as String?;
        final roomId = message.data['room_id'] as String?;

        final title =
            message.notification?.title ??
            (roomId != null
                ? 'Connection complete!'
                : (connectionId != null ? 'New connection request!' : 'knkt'));
        final body =
            message.notification?.body ??
            (roomId != null
                ? "You're connected! Start chatting now."
                : (connectionId != null
                      ? "Someone wants to connect with you."
                      : ""));

        await notificationService.showNotification(
          id: (connectionId ?? message.messageId ?? 'default').hashCode,
          title: title,
          body: body,
        );
      });

      // Handle background tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[knkt] FCM opened from background: ${message.data}');
      });
    } catch (e) {
      debugPrint('[knkt] FCM init error: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    if (_uid == null) return;
    await BackendService.updateFcmToken(_uid!, token);
    debugPrint('[knkt] FCM token registered');
  }
}
