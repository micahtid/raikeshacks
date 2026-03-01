import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'backend_service.dart';

class FcmService {
  String? _uid;
  final _messaging = FirebaseMessaging.instance;

  Future<void> initialize(String uid) async {
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

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[knkt] FCM foreground message: ${message.notification?.title}');
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
