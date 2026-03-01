import 'package:flutter/foundation.dart';

import 'backend_service.dart';

/// Firebase Cloud Messaging setup.
///
/// Note: Full FCM requires firebase_core and firebase_messaging packages
/// plus Firebase project configuration (google-services.json, etc.).
/// This class provides the integration point — initialize() should be
/// called after Firebase.initializeApp().
class FcmService {
  String? _uid;

  /// Initialize FCM: request permission, get token, register with server.
  ///
  /// Call this after Firebase is initialized and user is signed in.
  Future<void> initialize(String uid) async {
    _uid = uid;

    try {
      // Firebase messaging is only available after Firebase.initializeApp()
      // and adding firebase_messaging dependency + firebase config files.
      // For now, this is a stub that will be activated in Phase 4.
      debugPrint('[knkt] FCM: Ready for initialization (uid: $uid)');
      debugPrint('[knkt] FCM: Requires Firebase project setup (Phase 4)');
    } catch (e) {
      debugPrint('[knkt] FCM init error: $e');
    }
  }

  /// Register the FCM token with the server.
  Future<void> _registerToken(String token) async {
    if (_uid == null) return;
    await BackendService.updateFcmToken(_uid!, token);
    debugPrint('[knkt] FCM token registered');
  }
}
