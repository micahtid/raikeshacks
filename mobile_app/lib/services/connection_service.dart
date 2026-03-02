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

  /// When true, uses local mock data instead of backend calls.
  bool demoMode = false;

  /// Load myUid from prefs, fetch existing connections, start polling.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    myUid = prefs.getString('student_uid');
    if (myUid == null) myUid = 'demo_user';

    if (demoMode) {
      _loadDemoData();
      return;
    }

    await refreshConnections();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => refreshConnections(),
    );
  }

  /// Populate mock connections for demo purposes.
  void _loadDemoData() {
    final me = myUid!;
    const peerA = 'demo_peer_pending';
    const peerB = 'demo_peer_requested';
    const peerC = 'demo_peer_discover';

    // 1) Incoming request (other accepted, I haven't) — "Pending" from their side
    final connA = ConnectionModel(
      connectionId: '${me}_$peerA',
      uid1: me,
      uid2: peerA,
      uid1Accepted: false,
      uid2Accepted: true,
      matchPercentage: 85.0,
      uid1Summary: 'They have strong backend and systems design skills that complement your frontend expertise.',
      uid2Summary: 'You bring creative UI/UX skills that pair well with their engineering background.',
      notificationMessage: 'A great complementary match!',
      createdAt: DateTime.now().toIso8601String(),
    );

    // 2) Sent request (I accepted, other hasn't) — "Pending" from my side
    final connB = ConnectionModel(
      connectionId: '${me}_$peerB',
      uid1: me,
      uid2: peerB,
      uid1Accepted: true,
      uid2Accepted: false,
      matchPercentage: 72.0,
      uid1Summary: 'They are experienced in ML and data pipelines — exactly what you need.',
      uid2Summary: 'You bring product vision and design thinking to their technical skillset.',
      notificationMessage: 'Strong skills alignment detected!',
      createdAt: DateTime.now().toIso8601String(),
    );

    // 3) New discovery (neither accepted)
    final connC = ConnectionModel(
      connectionId: '${me}_$peerC',
      uid1: me,
      uid2: peerC,
      uid1Accepted: false,
      uid2Accepted: false,
      matchPercentage: 91.0,
      uid1Summary: 'They are building in the same space and have complementary technical skills.',
      uid2Summary: 'You have the design and growth skills their project needs.',
      notificationMessage: 'Exceptional match nearby!',
      createdAt: DateTime.now().toIso8601String(),
    );

    connections[connA.connectionId] = connA;
    connections[connB.connectionId] = connB;
    connections[connC.connectionId] = connC;

    // Mock peer profiles (anonymous until accepted)
    peerProfiles[peerA] = {
      'identity': {
        'full_name': 'Jordan Rivera',
        'university': 'MIT',
        'graduation_year': 2026,
        'major': ['Computer Science'],
        'minor': ['Mathematics'],
      },
      'focus_areas': ['startup', 'research'],
      'project': {'one_liner': 'Building an AI-powered tutoring platform', 'stage': 'mvp', 'industry': ['EdTech', 'AI']},
      'skills': {
        'possessed': [{'name': 'Python', 'source': 'resume'}, {'name': 'Systems Design', 'source': 'resume'}, {'name': 'Cloud Infrastructure', 'source': 'portfolio'}],
        'needed': [{'name': 'UI/UX Design', 'priority': 'must_have'}, {'name': 'React Native', 'priority': 'nice_to_have'}],
      },
    };

    peerProfiles[peerB] = {
      'identity': {
        'full_name': 'Alex Chen',
        'university': 'Stanford',
        'graduation_year': 2025,
        'major': ['Data Science'],
        'minor': [],
      },
      'focus_areas': ['side_project', 'open_source'],
      'project': {'one_liner': 'Open-source ML pipeline toolkit', 'stage': 'launched', 'industry': ['Developer Tools']},
      'skills': {
        'possessed': [{'name': 'Machine Learning', 'source': 'resume'}, {'name': 'Data Engineering', 'source': 'resume'}],
        'needed': [{'name': 'Product Management', 'priority': 'must_have'}],
      },
    };

    peerProfiles[peerC] = {
      'identity': {
        'full_name': 'Sam Patel',
        'university': 'UC Berkeley',
        'graduation_year': 2026,
        'major': ['EECS', 'Business'],
        'minor': ['Design'],
      },
      'focus_areas': ['startup', 'looking'],
      'project': {'one_liner': 'Marketplace for student freelancers', 'stage': 'idea', 'industry': ['Marketplace', 'Future of Work']},
      'skills': {
        'possessed': [{'name': 'Full-Stack Development', 'source': 'portfolio'}, {'name': 'Growth Marketing', 'source': 'questionnaire'}],
        'needed': [{'name': 'Mobile Development', 'priority': 'must_have'}, {'name': 'Backend Architecture', 'priority': 'must_have'}],
      },
    };

    notifyListeners();
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
      // Wait for the other user to create the connection.
      // A fallback timeout avoids a stuck skeleton if their request fails.
      Future.delayed(const Duration(seconds: 10), () {
        if (loadingPeerUids.contains(peerUid)) {
          loadingPeerUids.remove(peerUid);
          notifyListeners();
        }
      });
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

  /// Accept (or Connect) a connection.
  Future<void> acceptConnection(String connectionId) async {
    if (myUid == null) return;

    if (demoMode) {
      // Simulate accept locally
      await Future.delayed(const Duration(milliseconds: 800));
      final conn = connections[connectionId];
      if (conn == null) return;
      final updated = ConnectionModel(
        connectionId: conn.connectionId,
        uid1: conn.uid1,
        uid2: conn.uid2,
        uid1Accepted: conn.uid1 == myUid ? true : conn.uid1Accepted,
        uid2Accepted: conn.uid2 == myUid ? true : conn.uid2Accepted,
        matchPercentage: conn.matchPercentage,
        uid1Summary: conn.uid1Summary,
        uid2Summary: conn.uid2Summary,
        notificationMessage: conn.notificationMessage,
        createdAt: conn.createdAt,
        updatedAt: DateTime.now().toIso8601String(),
      );
      connections[connectionId] = updated;
      notifyListeners();
      return;
    }

    final updated = await BackendService.acceptConnection(connectionId, myUid!);
    if (updated != null) {
      connections[connectionId] = updated;
      // When both accepted, ensure we have the peer's real profile for un-anonymize
      if (updated.isComplete) {
        final peerUid = updated.otherUid(myUid!);
        peerProfiles.remove(peerUid); // force re-fetch for fresh data
        await _ensurePeerProfile(peerUid);
      }
      notifyListeners();
    }
  }

  /// Refresh all connections from server.
  Future<void> refreshConnections() async {
    if (myUid == null || demoMode) return;
    final list = await BackendService.getConnectionsForUser(myUid!);
    if (list != null) {
      connections.clear();
      for (final conn in list) {
        connections[conn.connectionId] = conn;
        // Fetch peer profiles we don't have yet
        final peerUid = conn.otherUid(myUid!);
        if (conn.isComplete) {
          // Force re-fetch so un-anonymize picks up fresh data
          peerProfiles.remove(peerUid);
        }
        await _ensurePeerProfile(peerUid);

        loadingPeerUids.remove(peerUid);
      }
      notifyListeners();
    }
  }

  /// Connections where both accepted AND peer is currently nearby.
  List<ConnectionModel> get connectedNearby {
    if (myUid == null) return [];
    return connections.values.where((c) {
      return c.isComplete && nearbyUids.contains(c.otherUid(myUid!));
    }).toList();
  }

  /// Brand new discoveries: above threshold, neither user has connected yet.
  List<ConnectionModel> get discoveredMatches {
    if (myUid == null) return [];
    return connections.values.where((c) {
      return c.isAboveThreshold && !c.uid1Accepted && !c.uid2Accepted;
    }).toList();
  }

  /// I tapped Connect, waiting for the other user.
  List<ConnectionModel> get sentRequests {
    if (myUid == null) return [];
    return connections.values.where((c) {
      return c.isAboveThreshold && c.hasAccepted(myUid!) && !c.isComplete;
    }).toList();
  }

  /// The other user connected, I haven't accepted yet.
  List<ConnectionModel> get incomingRequests {
    if (myUid == null) return [];
    return connections.values.where((c) {
      final otherUid = c.otherUid(myUid!);
      return c.isAboveThreshold &&
          !c.hasAccepted(myUid!) &&
          c.hasAccepted(otherUid);
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
