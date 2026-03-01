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
    _injectMockData();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => refreshConnections(),
    );
  }

  /// Inject mock users for testing purposes.
  void _injectMockData() {
    if (myUid == null) return;

    // ── Connected mock: Alex Chen (real name, both accepted, nearby) ──
    const mockUid1 = 'mock_user_alex_001';
    final connId1 = _makeConnectionId(myUid!, mockUid1);

    connections[connId1] = ConnectionModel(
      connectionId: connId1,
      uid1: myUid!.compareTo(mockUid1) < 0 ? myUid! : mockUid1,
      uid2: myUid!.compareTo(mockUid1) < 0 ? mockUid1 : myUid!,
      uid1Accepted: true,
      uid2Accepted: true,
      matchPercentage: 87,
      uid1Summary: 'Alex is building an AI-powered study tool and needs help with backend development. Your ML skills complement their frontend expertise perfectly.',
      uid2Summary: 'A great match for your project — they have strong backend and ML skills that could accelerate your MVP.',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    );
    peerProfiles[mockUid1] = {
      'uid': mockUid1,
      'identity': {
        'full_name': 'Alex Chen',
        'email': 'alex.chen@example.com',
        'profile_photo_url': null,
        'university': 'Stanford University',
        'graduation_year': 2026,
        'major': ['Computer Science'],
        'minor': ['Design'],
      },
      'focus_areas': ['startup', 'side_project'],
      'project': {
        'one_liner': 'AI-powered study assistant for college students',
        'stage': 'mvp',
        'industry': ['EdTech', 'AI/ML'],
      },
      'skills': {
        'possessed': [
          {'name': 'React', 'source': 'resume'},
          {'name': 'TypeScript', 'source': 'resume'},
          {'name': 'Figma', 'source': 'questionnaire'},
          {'name': 'UI/UX Design', 'source': 'questionnaire'},
        ],
        'needed': [
          {'name': 'Python', 'priority': 'must_have'},
          {'name': 'Machine Learning', 'priority': 'must_have'},
          {'name': 'Backend Development', 'priority': 'nice_to_have'},
        ],
      },
    };
    nearbyUids.add(mockUid1);

    // ── Request mock 1: anonymous pending (other user accepted, we haven't) ──
    const mockUid2 = 'mock_user_pending_001';
    final connId2 = _makeConnectionId(myUid!, mockUid2);
    final myIsUid1ForMock2 = myUid!.compareTo(mockUid2) < 0;

    connections[connId2] = ConnectionModel(
      connectionId: connId2,
      uid1: myIsUid1ForMock2 ? myUid! : mockUid2,
      uid2: myIsUid1ForMock2 ? mockUid2 : myUid!,
      // The other user accepted, but we haven't yet
      uid1Accepted: !myIsUid1ForMock2,
      uid2Accepted: myIsUid1ForMock2,
      matchPercentage: 74,
      uid1Summary: 'They have deep expertise in mobile development and are looking for a design-minded co-founder for their fintech idea.',
      uid2Summary: 'Your design skills and startup mindset make you a strong match for their mobile-first fintech project.',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
    );
    peerProfiles[mockUid2] = {
      'uid': mockUid2,
      'focus_areas': ['startup', 'research'],
      'project': {
        'one_liner': 'Fintech app for college students',
        'stage': 'idea',
        'industry': ['FinTech', 'Mobile'],
      },
    };

    // ── Request mock 2: anonymous pending (neither accepted yet) ──
    const mockUid3 = 'mock_user_pending_002';
    final connId3 = _makeConnectionId(myUid!, mockUid3);
    final myIsUid1ForMock3 = myUid!.compareTo(mockUid3) < 0;

    connections[connId3] = ConnectionModel(
      connectionId: connId3,
      uid1: myIsUid1ForMock3 ? myUid! : mockUid3,
      uid2: myIsUid1ForMock3 ? mockUid3 : myUid!,
      uid1Accepted: false,
      uid2Accepted: false,
      matchPercentage: 68,
      uid1Summary: 'A backend engineer with cloud infrastructure experience, looking to team up on open-source developer tools.',
      uid2Summary: 'Their cloud and DevOps skills could help you ship and scale your project infrastructure.',
      createdAt: DateTime.now().subtract(const Duration(hours: 8)).toIso8601String(),
    );
    peerProfiles[mockUid3] = {
      'uid': mockUid3,
      'focus_areas': ['open_source', 'side_project'],
      'project': {
        'one_liner': 'Developer tools for cloud infrastructure',
        'stage': 'mvp',
        'industry': ['DevTools', 'Cloud'],
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
      loadingPeerUids.remove(peerUid);
      notifyListeners();
      return;
    }

    final connectionId = _makeConnectionId(myUid!, peerUid);
    if (connections.containsKey(connectionId)) {
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
      _injectMockData();
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
