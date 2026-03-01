import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'notification_service.dart';

/// Manages an Android foreground service that keeps the app process alive
/// so Nearby Connections (BT discovery) continues when the user switches apps.
///
/// The foreground service shows a persistent notification — Android requires
/// this for any long-running background work.
class BackgroundServiceManager {
  static final _service = FlutterBackgroundService();

  /// Call once at app startup to configure the service.
  static Future<void> configure() async {
    if (!Platform.isAndroid) return;

    // The notification channel must exist before configuring the service.
    await NotificationService.createDiscoveryChannel();

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
        notificationChannelId: 'knkt_discovery',
        initialNotificationTitle: 'knkt',
        initialNotificationContent: 'Discovering nearby people…',
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  /// Start the foreground service (call when BT discovery begins).
  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    final running = await _service.isRunning();
    if (!running) {
      await _service.startService();
      debugPrint('[knkt] background service started');
    }
  }

  /// Stop the foreground service (call when discovery stops or user signs out).
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    final running = await _service.isRunning();
    if (running) {
      _service.invoke('stop');
      debugPrint('[knkt] background service stopped');
    }
  }
}

/// Entry point for the background isolate. The foreground service keeps
/// the app process alive — the actual BT work still runs in the main isolate.
@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) {
      service.stopSelf();
    });

    // Keep the foreground notification visible.
    await service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'knkt',
      content: 'Discovering nearby people…',
    );
  }
}
