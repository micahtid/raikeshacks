import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_model.dart';
import 'backend_service.dart';
import 'nearby_service.dart';

/// Central service managing all connection state.
class ConnectionService extends ChangeNotifier {
  /// All connections keyed by connection_id.
  final Map<String, ConnectionModel> connections = {};

  /// Cached peer profile data keyed by uid.
  final Map<String, Map<String, dynamic>> peerProfiles = {};

  /// UIDs currently discovered via Bluetooth.
  final Set<String> nearbyUids = {};

  /// UIDs currently being loaded (BT connected, API in progress).
  final Set<String> loadingPeerUids = {};

  /// This user's UID (loaded from SharedPreferences).
  String? myUid;

  Timer? _pollTimer;

  /// Load myUid from prefs, fetch existing connections, start polling.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    myUid = prefs.getString('student_uid');
    if (myUid == null) return;

    await refreshConnections();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => refreshConnections(),
    );
  }

  /// Called when a peer UID is received via Bluetooth.
  Future<void> onPeerDiscovered(String peerUid) async {
    nearbyUids.add(peerUid);
    loadingPeerUids.add(peerUid);
    notifyListeners();

    if (myUid == null) {
      loadingPeerUids.remove(peerUid);
      notifyListeners();
      return;
    }

    // Only the alphabetically-first user creates the connection to avoid duplicates
    if (myUid!.compareTo(peerUid) > 0) {
      loadingPeerUids.remove(peerUid);
      notifyListeners();
      return;
    }

    final connectionId = _makeConnectionId(myUid!, peerUid);
    if (connections.containsKey(connectionId)) {
      // Re-encounter: notify backend (fire-and-forget)
      BackendService.notifyReencounter(connectionId);
      loadingPeerUids.remove(peerUid);
      notifyListeners();
      return;
    }

    debugPrint('[knkt] Creating connection: $myUid <-> $peerUid');
    final conn = await BackendService.createConnection(myUid!, peerUid);
    if (conn != null) {
      connections[conn.connectionId] = conn;
      await _ensurePeerProfile(peerUid);
    }
    loadingPeerUids.remove(peerUid);
    notifyListeners();
  }

  /// Called when a Bluetooth peer is lost.
  void onPeerLost(String endpointId, NearbyService nearbyService) {
    final uid = nearbyService.endpointToUid[endpointId];
    if (uid != null) {
      nearbyUids.remove(uid);
      notifyListeners();
    }
  }

  /// Accept a connection.
  Future<void> acceptConnection(String connectionId) async {
    if (myUid == null) return;
    final updated = await BackendService.acceptConnection(connectionId, myUid!);
    if (updated != null) {
      connections[connectionId] = updated;
      notifyListeners();
    }
  }

  /// Refresh all connections from server.
  Future<void> refreshConnections() async {
    if (myUid == null) return;
    final list = await BackendService.getConnectionsForUser(myUid!);
    if (list != null) {
      connections.clear();
      for (final conn in list) {
        connections[conn.connectionId] = conn;
        // Fetch peer profiles we don't have yet
        final peerUid = conn.otherUid(myUid!);
        await _ensurePeerProfile(peerUid);
      }
    }
  }

  /// Connections where both accepted AND peer is currently nearby.
  List<ConnectionModel> get connectedNearby {
    if (myUid == null) return [];
    return connections.values.where((c) {
      return c.isComplete && nearbyUids.contains(c.otherUid(myUid!));
    }).toList();
  }

  /// Connections above threshold but not yet mutually accepted.
  List<ConnectionModel> get pendingRequests {
    if (myUid == null) return [];
    return connections.values.where((c) {
      return c.isAboveThreshold && !c.isComplete;
    }).toList();
  }

  /// All mutually accepted connections (for chat tab).
  List<ConnectionModel> get allAccepted {
    return connections.values.where((c) => c.isComplete).toList();
  }

  Future<void> _ensurePeerProfile(String uid) async {
    if (peerProfiles.containsKey(uid)) return;
    final profile = await BackendService.getStudent(uid);
    if (profile != null) {
      peerProfiles[uid] = profile;
    }
  }

  /// Clear all in-memory state (used after "Fresh Start").
  void clearLocalData() {
    connections.clear();
    peerProfiles.clear();
    nearbyUids.clear();
    loadingPeerUids.clear();
    notifyListeners();
  }

  String _makeConnectionId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
