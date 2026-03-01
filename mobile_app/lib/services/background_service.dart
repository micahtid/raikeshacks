import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Manages an Android foreground service that keeps the app process alive
/// and runs BLE scanning in a background isolate so peer discovery continues
/// when the user switches apps.
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

// ── Background isolate entry point ─────────────────────────────────────────

/// Company ID used to filter knkt BLE advertisements (matches BleDiscoveryService).
const int _companyId = 0xFFFF;

/// Prefix byte to identify knkt advertisements (matches BleDiscoveryService).
const int _magicByte = 0x4B; // 'K' for knkt

/// Default backend URL — used when SharedPreferences has no override.
const String _defaultBackendUrl =
    'https://raikeshacks-production.up.railway.app';

/// Entry point for the background isolate. Runs BLE scanning so that peer
/// discovery and notifications work even when the main Flutter UI is paused.
@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  StreamSubscription<List<ScanResult>>? scanSub;

  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) async {
      await scanSub?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      service.stopSelf();
    });

    await service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'knkt',
      content: 'Discovering nearby people…',
    );
  }

  final prefs = await SharedPreferences.getInstance();
  final myUid = prefs.getString('student_uid');
  if (myUid == null || myUid.isEmpty) return;

  final backendUrl =
      prefs.getString('backend_url') ?? _defaultBackendUrl;

  // Initialize the notifications plugin for this isolate (separate from main).
  final notifPlugin = FlutterLocalNotificationsPlugin();
  await notifPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  final discoveredUids = <String>{};

  // Start BLE scanning. Skip turnOn() — it requires Activity context.
  // The main isolate already called turnOn() before starting the service.
  try {
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 0), // no timeout — scan indefinitely
      continuousUpdates: true,
      androidUsesFineLocation: true,
    );
    debugPrint('[knkt-bg] BLE scanning started');
  } catch (e) {
    debugPrint('[knkt-bg] BLE scan start failed: $e');
    return;
  }

  scanSub = FlutterBluePlus.scanResults.listen((results) {
    for (final result in results) {
      _processScanResult(
        result,
        myUid: myUid,
        backendUrl: backendUrl,
        discoveredUids: discoveredUids,
        notifPlugin: notifPlugin,
      );
    }
  });
}

/// Process a single BLE scan result — extract peer UID from manufacturer data,
/// create a connection via the backend, and show a local notification.
Future<void> _processScanResult(
  ScanResult result, {
  required String myUid,
  required String backendUrl,
  required Set<String> discoveredUids,
  required FlutterLocalNotificationsPlugin notifPlugin,
}) async {
  final mfgData = result.advertisementData.manufacturerData;
  if (mfgData.isEmpty) return;

  for (final entry in mfgData.entries) {
    if (entry.key != _companyId) continue;
    final data = entry.value;
    if (data.isEmpty || data[0] != _magicByte) continue;

    final uidBytes = data.sublist(1);
    final peerUid = _decodeUid(uidBytes);
    if (peerUid == null || peerUid.isEmpty || peerUid == myUid) continue;

    if (discoveredUids.contains(peerUid)) continue;
    discoveredUids.add(peerUid);

    debugPrint('[knkt-bg] discovered peer: $peerUid (rssi: ${result.rssi})');

    // Create connection via backend (handles duplicates server-side).
    try {
      final resp = await http.post(
        Uri.parse('$backendUrl/connections'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid1': myUid, 'uid2': peerUid}),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        // Fetch peer name for the notification.
        String peerName = 'Someone';
        try {
          final profileResp = await http.get(
            Uri.parse('$backendUrl/students/$peerUid'),
          );
          if (profileResp.statusCode == 200) {
            final profile = jsonDecode(profileResp.body);
            peerName = (profile['full_name'] as String?) ?? 'Someone';
          }
        } catch (_) {}

        await notifPlugin.show(
          peerUid.hashCode,
          'Someone nearby!',
          '$peerName is around you',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'nearby_alerts',
              'Nearby Alerts',
              channelDescription: 'Notifications when someone is nearby',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
        debugPrint('[knkt-bg] notification shown for $peerName');
      }
    } catch (e) {
      debugPrint('[knkt-bg] connection/notification failed: $e');
    }
  }
}

/// Decode 16-byte binary back into a UUID string with hyphens.
/// Mirrors [BleDiscoveryService.decodeUid].
String? _decodeUid(List<int> bytes) {
  if (bytes.length == 16) {
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
  if (bytes.isNotEmpty && bytes.length <= 36) {
    return String.fromCharCodes(bytes);
  }
  return null;
}
