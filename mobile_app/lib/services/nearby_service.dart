import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/peer_device.dart';
import 'similarity_api_service.dart';

class NearbyService extends ChangeNotifier {
  static const String _serviceId = 'com.example.mobile_app.nearby';

  // ── User inputs ──────────────────────────────────────────────────────────
  String displayName = '';
  String secretWord = '';

  // ── Runtime state ────────────────────────────────────────────────────────
  bool isAdvertising = false;
  bool isDiscovering = false;
  String statusMessage = 'Idle';

  /// Peers found during discovery (endpointId → PeerDevice).
  final Map<String, PeerDevice> discoveredPeers = {};

  // Caches the remote name received in onConnectionInitiated so it is
  // available on both the advertiser and discoverer sides when the connection
  // result arrives.
  final Map<String, String> _pendingConnectionNames = {};

  String? connectedEndpointId;
  String? connectedPeerName;
  String? receivedSecretWord;

  // ── Public API ────────────────────────────────────────────────────────────

  void setDisplayName(String name) {
    displayName = name;
    notifyListeners();
  }

  void setSecretWord(String word) {
    secretWord = word;
    notifyListeners();
  }

  /// Request all permissions required by Nearby Connections.
  /// Returns true only if every permission was granted.
  Future<bool> requestPermissions() async {
    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.nearbyWifiDevices,
    ];

    final statuses = await permissions.request();
    final allGranted = statuses.values.every(
      (s) => s == PermissionStatus.granted,
    );

    if (!allGranted) {
      _setStatus('Some permissions were denied. P2P may not work correctly.');
    }
    return allGranted;
  }

  /// Start both advertising AND discovering simultaneously.
  /// Auto-connects to the first discovered peer.
  Future<void> startBoth() async {
    if (displayName.trim().isEmpty) {
      _setStatus('Enter a Display Name first.');
      return;
    }

    try {
      await Nearby().startAdvertising(
        displayName,
        Strategy.P2P_STAR,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      isAdvertising = true;
    } catch (e) {
      _setStatus('Failed to start advertising: $e');
      return;
    }

    try {
      await Nearby().startDiscovery(
        displayName,
        Strategy.P2P_STAR,
        onEndpointFound: (endpointId, name, serviceId) {
          discoveredPeers[endpointId] = PeerDevice(
            endpointId: endpointId,
            name: name,
          );
          notifyListeners();
          // Auto-connect to the first peer we find.
          // Only the device with the lower display name initiates, so both
          // sides don't call requestConnection simultaneously (race condition).
          if (connectedEndpointId == null && displayName.compareTo(name) < 0) {
            _setStatus('Found "$name" — auto-connecting…');
            _autoConnect(endpointId);
          } else if (connectedEndpointId == null) {
            _setStatus('Found "$name" — waiting for their connection…');
          }
        },
        onEndpointLost: (String? endpointId) {
          if (endpointId != null) discoveredPeers.remove(endpointId);
          notifyListeners();
        },
        serviceId: _serviceId,
      );
      isDiscovering = true;
    } catch (e) {
      _setStatus('Failed to start discovery: $e');
      return;
    }

    _setStatus('Live — advertising & discovering as "$displayName"…');
  }

  Future<void> _autoConnect(String endpointId) async {
    try {
      await Nearby().requestConnection(
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

  /// Stop advertising, discovery, and disconnect all endpoints.
  Future<void> stopAll() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();

    isAdvertising = false;
    isDiscovering = false;
    connectedEndpointId = null;
    connectedPeerName = null;
    receivedSecretWord = null;
    discoveredPeers.clear();
    _setStatus('Idle');
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Called on BOTH the advertiser and the discoverer when a connection is
  /// being negotiated. We auto-accept every incoming request.
  void _onConnectionInitiated(
    String endpointId,
    ConnectionInfo connectionInfo,
  ) {
    // Cache the remote name so _onConnectionResult can use it on both sides.
    _pendingConnectionNames[endpointId] = connectionInfo.endpointName;
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {
        // No-op: bytes payloads are small; we don't need progress tracking.
      },
    );
    _setStatus('Accepted connection from "${connectionInfo.endpointName}"…');
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      final peerName = discoveredPeers[endpointId]?.name ??
          _pendingConnectionNames[endpointId] ??
          'Unknown';
      _pendingConnectionNames.remove(endpointId);
      connectedEndpointId = endpointId;
      connectedPeerName = peerName;
      _setStatus('Connected to "$peerName". Exchanging secret…');
      _sendSecretWord(endpointId);
    } else {
      _setStatus('Connection to $endpointId failed (${status.name}).');
    }
  }

  void _onDisconnected(String endpointId) {
    if (connectedEndpointId == endpointId) {
      connectedEndpointId = null;
      connectedPeerName = null;
      receivedSecretWord = null;
    }
    _setStatus('Disconnected from $endpointId.');
  }

  Future<void> _sendSecretWord(String endpointId) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(secretWord));
      await Nearby().sendBytesPayload(endpointId, bytes);
    } catch (e) {
      _setStatus('Failed to send secret word: $e');
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      final bytes = payload.bytes;
      if (bytes != null) {
        receivedSecretWord = utf8.decode(bytes);
        // Update the peer name from the connection result if not already set.
        connectedEndpointId ??= endpointId;
        connectedPeerName ??= discoveredPeers[endpointId]?.name ?? 'Peer';
        _setStatus(
          'Secret word received from "${connectedPeerName ?? endpointId}"!',
        );

        // ── Auto-trigger similarity check ──
        _postEncounter();
      }
    }
  }

  /// Silently POST the encounter to the Vercel backend.
  Future<void> _postEncounter() async {
    final peer = connectedPeerName;
    if (peer == null) return;

    _setStatus('Posting encounter to backend…');
    final ok = await SimilarityApiService.postEncounter(
      myUserId: displayName,
      peerUserId: peer,
      secretWord: receivedSecretWord,
    );
    _setStatus(
      ok
          ? 'Similarity check initiated for "$peer".'
          : 'Backend POST failed – will retry on next encounter.',
    );
  }

  void _setStatus(String message) {
    statusMessage = message;
    notifyListeners();
  }
}
