import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wraps [flutter_background_service] so the app keeps running even when the
/// user switches away.  On Android this uses a foreground service with a
/// persistent notification; on iOS it uses background fetch (best-effort).
class BackgroundServiceHelper {
  static const String _notificationChannelId = 'raikeshacks_foreground';
  static const String _notificationChannelName = 'Raikeshacks Nearby';
  static const int _notificationId = 888;

  /// Call once from `main()` before `runApp`.
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Android notification channel for the foreground service.
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: 'Keeps nearby device discovery active in the background.',
      importance: Importance.low,
    );

    final flnPlugin = FlutterLocalNotificationsPlugin();
    await flnPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'Raikeshacks',
        initialNotificationContent: 'Listening for nearby encounters…',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Entry point that runs in the foreground-service isolate (Android) or on
  /// the main isolate (iOS).  We keep it minimal – the heavy lifting (Nearby
  /// Connections + HTTP POST) happens on the main isolate because
  /// platform-channel plugins are bound there.  This isolate just keeps the
  /// process alive.
  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((_) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((_) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((_) {
      service.stopSelf();
    });

    // Periodic heartbeat – keeps the service alive.
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Raikeshacks',
          content: 'Listening for nearby encounters…',
        );
      }
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }
}
