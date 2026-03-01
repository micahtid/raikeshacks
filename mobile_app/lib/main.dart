import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/backend_service.dart';
import 'services/connection_service.dart';
import 'services/fcm_service.dart';
import 'services/nearby_service.dart';
import 'services/notification_service.dart';
import 'services/websocket_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'knkt',
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final GoogleSignIn _googleSignIn;
  final NearbyService _nearbyService = NearbyService();
  final NotificationService _notificationService = NotificationService();
  final ConnectionService _connectionService = ConnectionService();
  final WebSocketService _webSocketService = WebSocketService();
  final FcmService _fcmService = FcmService();
  GoogleSignInAccount? _currentUser;
  bool _isLoading = true;
  bool _onboardingComplete = false;
  String? _storedUid;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    // On Android, google_sign_in uses the OAuth client registered in
    // Google Cloud Console (matched by package name + SHA-1) automatically.
    // clientId is only needed for iOS, macOS, and web.
    final needsClientId = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    _googleSignIn = GoogleSignIn(
      clientId: needsClientId ? dotenv.env['GOOGLE_CLIENT_ID'] : null,
    );
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      setState(() {
        _currentUser = account;
      });
    });
    _trySignInSilently();
  }

  Future<void> _initNotifications() async {
    await _notificationService.init();
    _nearbyService.setNotificationService(_notificationService);
  }

  Future<void> _trySignInSilently() async {
    try {
      await _googleSignIn.signInSilently();
    } catch (_) {}
    // Check if user already completed onboarding
    final prefs = await SharedPreferences.getInstance();
    _storedUid = prefs.getString('student_uid');
    if (_storedUid != null && _storedUid!.isNotEmpty) {
      _onboardingComplete = true;
      await _initServices();
    } else if (_currentUser != null) {
      // No stored UID but user is signed in — check if profile exists on backend
      await _tryRecoverProfile(_currentUser!.email, prefs);
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Look up an existing profile by email and restore the stored UID.
  Future<void> _tryRecoverProfile(String email, SharedPreferences prefs) async {
    try {
      final profile = await BackendService.getStudentByEmail(email);
      if (profile != null) {
        final uid = profile['uid'] as String?;
        if (uid != null && uid.isNotEmpty) {
          await prefs.setString('student_uid', uid);
          _storedUid = uid;
          _onboardingComplete = true;
          await _initServices();
        }
      }
    } catch (e) {
      debugPrint('[knkt] profile recovery failed: $e');
    }
  }

  Future<void> _initServices() async {
    // Wire NearbyService callbacks to ConnectionService
    _nearbyService.onPeerUidReceived = (uid) =>
        _connectionService.onPeerDiscovered(uid);
    _nearbyService.onPeerLost = (endpointId) =>
        _connectionService.onPeerLost(endpointId, _nearbyService);

    // Initialize ConnectionService
    await _connectionService.initialize();

    // Connect WebSocket for real-time events
    final baseUrl = dotenv.env['BACKEND_URL'] ?? 'https://raikeshacks-production.up.railway.app';
    if (_connectionService.myUid != null) {
      _webSocketService.onMatchFound = (_) => _connectionService.refreshConnections();
      _webSocketService.onConnectionAccepted = (_) => _connectionService.refreshConnections();
      _webSocketService.onConnectionComplete = (_) => _connectionService.refreshConnections();
      _webSocketService.connect(_connectionService.myUid!, baseUrl);

      // Initialize FCM (stub until Firebase project is set up)
      await _fcmService.initialize(_connectionService.myUid!);
    }
  }

  Future<void> _handleSignIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return;

      // Show loading while we check if user already completed onboarding,
      // so the onboarding screen doesn't flash briefly.
      if (mounted) setState(() => _isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      _storedUid = prefs.getString('student_uid');
      if (_storedUid != null && _storedUid!.isNotEmpty) {
        _onboardingComplete = true;
        await _initServices();
      } else {
        await _tryRecoverProfile(account.email, prefs);
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e')),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    _webSocketService.disconnect();
    await _nearbyService.stopAll();
    await _googleSignIn.signOut();
    setState(() => _onboardingComplete = false);
  }

  void _onOnboardingComplete() {
    setState(() => _onboardingComplete = true);
    _initServices();
  }

  @override
  void dispose() {
    _webSocketService.disconnect();
    _connectionService.dispose();
    _nearbyService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isLoading) {
      child = Scaffold(
        key: const ValueKey('loading'),
        backgroundColor: AppColors.primary,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.onPrimary,
          ),
        ),
      );
    } else if (_currentUser == null) {
      child = _SignInPage(
        key: const ValueKey('signin'),
        onSignIn: _handleSignIn,
      );
    } else if (!_onboardingComplete) {
      child = OnboardingScreen(
        key: const ValueKey('onboarding'),
        onComplete: _onOnboardingComplete,
        onSignOut: _handleSignOut,
        fullName: _currentUser!.displayName ?? '',
        email: _currentUser!.email,
        photoUrl: _currentUser!.photoUrl,
      );
    } else {
      final displayName = _currentUser!.displayName ?? _currentUser!.email;
      if (_nearbyService.displayName != displayName) {
        _nearbyService.setDisplayName(displayName);
      }
      child = DashboardScreen(
        key: const ValueKey('dashboard'),
        userPhotoUrl: _currentUser!.photoUrl,
        displayName: displayName,
        onSignOut: _handleSignOut,
        nearbyService: _nearbyService,
        connectionService: _connectionService,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Sign-in page with animated network graph
// ---------------------------------------------------------------------------

class _SignInPage extends StatefulWidget {
  final VoidCallback onSignIn;
  const _SignInPage({super.key, required this.onSignIn});

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _graphController;

  @override
  void initState() {
    super.initState();
    _graphController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _graphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          // Full-screen lilac background
          Positioned.fill(
            child: Container(color: AppColors.primary),
          ),

          // Network graph animation (upper area, compact)
          Positioned(
            top: height * 0.04,
            left: 24,
            right: 24,
            height: height * 0.46,
            child: AnimatedBuilder(
              animation: _graphController,
              builder: (context, child) {
                return CustomPaint(
                  painter:
                      _NetworkGraphPainter(progress: _graphController.value),
                  size: Size.infinite,
                );
              },
            ),
          ),

          // Dark bottom container with semicircle top
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height * 0.48,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    40,
                    AppSpacing.screenPadding,
                    AppSpacing.screenPadding,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      Text(
                        'knkt',
                        style: GoogleFonts.sora(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Find your people. Build together.',
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(flex: 2),
                      FilledButton.icon(
                        onPressed: widget.onSignIn,
                        icon: const Icon(Icons.login, size: 20),
                        label: const Text('Sign in with Google'),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Network graph CustomPainter — nodes + edges that flash in waves
// ---------------------------------------------------------------------------

class _NetworkGraphPainter extends CustomPainter {
  final double progress;

  _NetworkGraphPainter({required this.progress});

  // Node positions as fractions of the paint area
  static const _nodes = [
    Offset(0.15, 0.15),
    Offset(0.40, 0.06),
    Offset(0.65, 0.12),
    Offset(0.88, 0.20),
    Offset(0.10, 0.42),
    Offset(0.35, 0.34),
    Offset(0.60, 0.38),
    Offset(0.85, 0.46),
    Offset(0.22, 0.62),
    Offset(0.50, 0.58),
    Offset(0.78, 0.68),
  ];

  // Base radius per node for natural variation
  static const _nodeRadii = [
    7.0, 10.0, 6.0, 8.5, 9.0, 12.0, 7.5, 6.5, 11.0, 8.0, 9.5,
  ];

  // Edges connecting nodes
  static const _edges = [
    [0, 1], [1, 2], [2, 3],
    [0, 4], [0, 5],
    [1, 5], [1, 6],
    [2, 6], [2, 7], [3, 7],
    [4, 5], [5, 6], [6, 7],
    [4, 8], [5, 9], [6, 9], [7, 10],
    [8, 9], [9, 10],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scaledNodes =
        _nodes.map((n) => Offset(n.dx * size.width, n.dy * size.height)).toList();

    final totalEdges = _edges.length;

    // Draw edges — each one pulses based on its phase offset
    for (int i = 0; i < totalEdges; i++) {
      final phase = i / totalEdges;
      // Sine wave gives smooth flash; each edge is offset by its phase
      final raw = math.sin(2 * math.pi * (progress - phase));
      // Clamp to [0,1] — only the positive half of the sine produces a flash
      final pulse = raw.clamp(0.0, 1.0);

      final baseAlpha = 0.10;
      final flashAlpha = 0.45;
      final alpha = baseAlpha + pulse * (flashAlpha - baseAlpha);
      final width = 1.2 + pulse * 1.0;

      final from = scaledNodes[_edges[i][0]];
      final to = scaledNodes[_edges[i][1]];

      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..strokeWidth = width,
      );
    }

    // Draw nodes — gently pulse when adjacent edges are active
    for (int n = 0; n < scaledNodes.length; n++) {
      // Find max pulse of any edge touching this node
      double maxPulse = 0;
      for (int i = 0; i < totalEdges; i++) {
        if (_edges[i][0] == n || _edges[i][1] == n) {
          final phase = i / totalEdges;
          final raw = math.sin(2 * math.pi * (progress - phase));
          if (raw > maxPulse) maxPulse = raw.clamp(0.0, 1.0);
        }
      }

      final nodeAlpha = 0.25 + maxPulse * 0.35;
      final nodeRadius = _nodeRadii[n] + maxPulse * 2.5;

      canvas.drawCircle(
        scaledNodes[n],
        nodeRadius,
        Paint()..color = Colors.white.withValues(alpha: nodeAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(_NetworkGraphPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
