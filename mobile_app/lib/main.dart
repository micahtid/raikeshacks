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
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
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
    final baseUrl = dotenv.env['BACKEND_URL'] ?? 'https://raikeshacks-teal.vercel.app';
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
      await _googleSignIn.signIn();
    } catch (e) {
      if (mounted) {
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentUser == null) {
      final theme = Theme.of(context);
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: Column(
              children: [
                const Spacer(flex: 3),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLightBlue,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sectionGapSmall),
                Text(
                  'knkt',
                  style: GoogleFonts.sora(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Find your people. Build together.',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(flex: 4),
                FilledButton.icon(
                  onPressed: _handleSignIn,
                  icon: const Icon(Icons.login, size: 20),
                  label: const Text('Sign in with Google'),
                ),
                const SizedBox(height: AppSpacing.screenPadding),
              ],
            ),
          ),
        ),
      );
    }

    if (!_onboardingComplete) {
      return OnboardingScreen(
        onComplete: _onOnboardingComplete,
        onSignOut: _handleSignOut,
        fullName: _currentUser!.displayName ?? '',
        email: _currentUser!.email,
        photoUrl: _currentUser!.photoUrl,
      );
    }

    // Set the display name from the Google account for Nearby Connections.
    final displayName = _currentUser!.displayName ?? _currentUser!.email;
    if (_nearbyService.displayName != displayName) {
      _nearbyService.setDisplayName(displayName);
    }

    return DashboardScreen(
      userPhotoUrl: _currentUser!.photoUrl,
      displayName: displayName,
      onSignOut: _handleSignOut,
      nearbyService: _nearbyService,
      connectionService: _connectionService,
    );
  }
}
