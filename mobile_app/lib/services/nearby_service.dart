import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/peer_device.dart';
import 'notification_service.dart';
import 'similarity_api_service.dart';

/// UI-side service that drives Nearby Connections **in the main isolate**.
///
/// The `nearby_connections` plugin requires an Activity context, so all calls
/// must happen here — not in a background-service isolate. The companion
/// [BackgroundServiceHelper] keeps a foreground notification alive so Android
/// doesn't kill the process while scanning.
class NearbyService extends ChangeNotifier {
  static const String _serviceId = 'com.example.mobile_app.nearby';

  // ── Public state ──────────────────────────────────────────────────────────
  String displayName = '';
  String secretWord = '';
  bool isAdvertising = false;
  bool isDiscovering = false;
  String statusMessage = 'Idle';

  final Map<String, PeerDevice> discoveredPeers = {};
  String? connectedEndpointId;
  String? connectedPeerName;
  String? receivedSecretWord;

  // ── Internal ──────────────────────────────────────────────────────────────
  final _nearby = Nearby();
  final _pendingNames = <String, String>{};
  NotificationService? _notificationService;

  // ── Public API ────────────────────────────────────────────────────────────

  void setNotificationService(NotificationService service) {
    _notificationService = service;
  }

  void setDisplayName(String name) {
    displayName = name;
    notifyListeners();
  }

  void setSecretWord(String word) {
    secretWord = word;
    notifyListeners();
  }

  /// Request all runtime permissions required by Nearby Connections.
  Future<bool> requestPermissions() async {
    List<Permission> perms = [];

    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final sdk = info.version.sdkInt;

      // Location is always needed for Nearby Connections (BLE + WiFi Direct).
      perms.add(Permission.location);

      if (sdk >= 31) {
        perms.addAll([
          Permission.bluetoothScan,
          Permission.bluetoothAdvertise,
          Permission.bluetoothConnect,
        ]);
      }
      if (sdk >= 33) {
        perms.add(Permission.nearbyWifiDevices);
      }
    } else {
      perms.addAll([Permission.bluetooth, Permission.location]);
    }

    final statuses = await perms.request();
    final allGranted =
        statuses.values.every((s) => s == PermissionStatus.granted);

    if (!allGranted) {
      _setStatus('Some permissions were denied. P2P may not work.');
    }
    return allGranted;
  }

  /// Start advertising + discovery. Call after [requestPermissions].
  Future<void> startBoth() async {
    if (displayName.trim().isEmpty) {
      _setStatus('Display name not set.');
      return;
    }

    // Stop any previous session first.
    if (isAdvertising || isDiscovering) {
      await _stopNearby();
    }

    // ── Advertise ──
    try {
      final advOk = await _nearby.startAdvertising(
        displayName,
        Strategy.P2P_STAR,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      isAdvertising = advOk;
      debugPrint('[knkt] startAdvertising → $advOk');
    } catch (e) {
      _setStatus('Failed to advertise: $e');
      debugPrint('[knkt] startAdvertising FAILED: $e');
      return;
    }

    // ── Discover ──
    try {
      final disOk = await _nearby.startDiscovery(
        displayName,
        Strategy.P2P_STAR,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: _serviceId,
      );
      isDiscovering = disOk;
      debugPrint('[knkt] startDiscovery → $disOk');
    } catch (e) {
      _setStatus('Failed to discover: $e');
      debugPrint('[knkt] startDiscovery FAILED: $e');
      return;
    }

    _setStatus('Live — advertising & discovering as "$displayName"…');
  }

  /// Stop all Nearby activity.
  Future<void> stopAll() async {
    await _stopNearby();
    connectedEndpointId = null;
    connectedPeerName = null;
    receivedSecretWord = null;
    discoveredPeers.clear();
    _pendingNames.clear();
    _setStatus('Idle');
  }

  @override
  void dispose() {
    _stopNearby();
    super.dispose();
  }

  // ── Nearby callbacks ────────────────────────────────────────────────────

  void _onEndpointFound(String endpointId, String name, String serviceId) {
    debugPrint('[knkt] onEndpointFound: $endpointId ($name)');
    discoveredPeers[endpointId] = PeerDevice(endpointId: endpointId, name: name);
    if (name != displayName) {
      _notificationService?.showNearbyNotification(name);
    }
    notifyListeners();

    // Auto-connect: the device whose name sorts first initiates.
    if (connectedEndpointId == null && displayName.compareTo(name) < 0) {
      _setStatus('Found "$name" — auto-connecting…');
      _autoConnect(endpointId);
    } else if (connectedEndpointId == null) {
      _setStatus('Found "$name" — waiting for their connection…');
    }
  }

  void _onEndpointLost(String? endpointId) {
    debugPrint('[knkt] onEndpointLost: $endpointId');
    if (endpointId != null) {
      discoveredPeers.remove(endpointId);
      notifyListeners();
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    debugPrint('[knkt] onConnectionInitiated: $endpointId (${info.endpointName})');
    _pendingNames[endpointId] = info.endpointName;
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: (_, __) {},
    );
    _setStatus('Accepted connection from "${info.endpointName}"…');
  }

  void _onConnectionResult(String endpointId, Status status) {
    debugPrint('[knkt] onConnectionResult: $endpointId → ${status.name}');
    if (status == Status.CONNECTED) {
      final name = _pendingNames[endpointId] ?? endpointId;
      connectedEndpointId = endpointId;
      connectedPeerName = name;
      notifyListeners();
      _setStatus('Connected to "$name". Exchanging secret…');
      // Send our secret word to the peer.
      final bytes = Uint8List.fromList(utf8.encode(secretWord));
      _nearby.sendBytesPayload(endpointId, bytes);
    } else {
      _setStatus('Connection to $endpointId failed (${status.name}).');
    }
  }

  void _onDisconnected(String endpointId) {
    debugPrint('[knkt] onDisconnected: $endpointId');
    if (connectedEndpointId == endpointId) {
      connectedEndpointId = null;
      connectedPeerName = null;
      receivedSecretWord = null;
    }
    _pendingNames.remove(endpointId);
    notifyListeners();
    _setStatus('Disconnected from $endpointId.');
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
    final word = utf8.decode(payload.bytes!);
    connectedEndpointId ??= endpointId;
    final peer = _pendingNames[endpointId] ?? endpointId;
    connectedPeerName ??= peer;
    receivedSecretWord = word;
    notifyListeners();
    _setStatus('Secret word received from "$peer"!');

    SimilarityApiService.postEncounter(
      myUserId: displayName,
      peerUserId: peer,
      secretWord: word,
    );
  }

  Future<void> _autoConnect(String endpointId) async {
    try {
      await _nearby.requestConnection(
        displayName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      _setStatus('Auto-connect failed: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _stopNearby() async {
    try { await _nearby.stopAdvertising(); } catch (_) {}
    try { await _nearby.stopDiscovery(); } catch (_) {}
    try { await _nearby.stopAllEndpoints(); } catch (_) {}
    isAdvertising = false;
    isDiscovering = false;
  }

  void _setStatus(String message) {
    statusMessage = message;
    debugPrint('[knkt] status: $message');
    notifyListeners();
  }
}
