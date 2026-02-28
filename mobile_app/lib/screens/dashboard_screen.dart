import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../models/peer_device.dart';
import '../services/nearby_service.dart';
import '../theme.dart';
import 'chat_screen.dart';

// ── Mock data ────────────────────────────────────────────────────────────────

enum _ConnectionState { incoming, pending, suggested, connected }

class _MockUser {
  final String id;
  final String name;
  final String focus;
  final String stage;
  final String bio;
  final int score; // compatibility score 0-100
  final _ConnectionState initialState;

  const _MockUser({
    required this.id,
    required this.name,
    required this.focus,
    required this.stage,
    required this.bio,
    required this.score,
    required this.initialState,
  });
}

const _mockUsers = [
  _MockUser(
    id: '1',
    name: 'Alex Rivera',
    focus: 'Startup',
    stage: 'MVP',
    bio: 'Building a fintech platform for freelancers. Looking for co-founders with mobile dev or design chops.',
    score: 92,
    initialState: _ConnectionState.incoming,
  ),
  _MockUser(
    id: '2',
    name: 'Jordan Kim',
    focus: 'Research',
    stage: 'Idea',
    bio: 'PhD candidate exploring NLP for accessibility tools. Always down to brainstorm over coffee.',
    score: 87,
    initialState: _ConnectionState.incoming,
  ),
  _MockUser(
    id: '3',
    name: 'Sam Chen',
    focus: 'Side Project',
    stage: 'Launched',
    bio: 'Shipped a habit-tracking app last month. Now iterating on retention and onboarding flows.',
    score: 78,
    initialState: _ConnectionState.pending,
  ),
  _MockUser(
    id: '4',
    name: 'Taylor Brooks',
    focus: 'Open Source',
    stage: 'Scaling',
    bio: 'Maintaining a popular Dart testing library. Interested in dev-tooling and CI/CD pipelines.',
    score: 74,
    initialState: _ConnectionState.pending,
  ),
  _MockUser(
    id: '5',
    name: 'Morgan Lee',
    focus: 'Startup',
    stage: 'Idea',
    bio: 'Exploring the intersection of AI and education. Former teacher turned indie hacker.',
    score: 85,
    initialState: _ConnectionState.suggested,
  ),
  _MockUser(
    id: '6',
    name: 'Casey Patel',
    focus: 'Side Project',
    stage: 'MVP',
    bio: 'Designing a local-first recipe app. Passionate about offline-capable mobile experiences.',
    score: 69,
    initialState: _ConnectionState.suggested,
  ),
  _MockUser(
    id: '7',
    name: 'Riley Nakamura',
    focus: 'Research',
    stage: 'Launched',
    bio: 'Published a paper on mesh networking for rural connectivity. Building a proof-of-concept app.',
    score: 81,
    initialState: _ConnectionState.suggested,
  ),
];

// ── Dashboard screen ─────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final String? userPhotoUrl;
  final String displayName;
  final VoidCallback onSignOut;
  final NearbyService nearbyService;

  const DashboardScreen({
    super.key,
    this.userPhotoUrl,
    required this.displayName,
    required this.onSignOut,
    required this.nearbyService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTab = 0;
  bool _isScanning = false;
  bool _isDeleting = false;

  /// Connection state for each mock user, initialized from their defaults.
  late final Map<String, _ConnectionState> _connectionStates = {
    for (final u in _mockUsers) u.id: u.initialState,
  };

  NearbyService get _svc => widget.nearbyService;
  String get _firstName => widget.displayName.split(' ').first;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onNearbyChanged);
    _startScanning();
  }

  @override
  void dispose() {
    _svc.removeListener(_onNearbyChanged);
    super.dispose();
  }

  void _onNearbyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startScanning() async {
    final granted = await _svc.requestPermissions();
    if (!granted) return;
    await _svc.startBoth();
    if (mounted) setState(() => _isScanning = true);
  }

  Future<void> _stopScanning() async {
    await _svc.stopAll();
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all associated data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    final url = dotenv.env['DELETE_ACCOUNT_URL'];
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delete URL not configured')),
        );
        setState(() => _isDeleting = false);
      }
      return;
    }

    try {
      final response = await http.delete(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.displayName}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        widget.onSignOut();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete account: ${response.statusCode}'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _acceptMockUser(String id) {
    setState(() => _connectionStates[id] = _ConnectionState.connected);
  }

  void _connectMockUser(String id) {
    setState(() => _connectionStates[id] = _ConnectionState.pending);
  }

  void _pushChatScreen(_MockUser user) {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : user.name.isNotEmpty
            ? user.name[0].toUpperCase()
            : '?';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peerName: user.name,
          peerInitials: initials,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // Main content
          SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _selectedTab == 0
                  ? _buildDashboardContent(theme)
                  : _selectedTab == 1
                      ? _buildChatContent(theme)
                      : _buildProfileContent(theme),
            ),
          ),
          // Floating glass nav bar
          Positioned(
            left: 24,
            right: 24,
            bottom: bottomPadding + 16,
            child: _GlassNavBar(
              selectedIndex: _selectedTab,
              onTap: (index) => setState(() => _selectedTab = index),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dashboard tab ──────────────────────────────────────────────────────

  Widget _buildSection(
    ThemeData theme,
    String title,
    List<_MockUser> users,
  ) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding, 20, AppSpacing.screenPadding, 10,
          ),
          child: Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${users.length}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...users.map((user) {
          final state = _connectionStates[user.id]!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 10,
            ),
            child: _MockProfileCard(
              user: user,
              state: state,
              onTap: () => _showProfileSheet(user),
              onChat: () => _pushChatScreen(user),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDashboardContent(ThemeData theme) {
    final peers = _svc.discoveredPeers.values.toList();

    // Requests: incoming (not yet accepted)
    final requests = _mockUsers
        .where((u) => _connectionStates[u.id] == _ConnectionState.incoming)
        .toList();

    // Connected: mutually accepted (from any original section)
    final connected = _mockUsers
        .where((u) => _connectionStates[u.id] == _ConnectionState.connected)
        .toList();

    // Discover: suggested + pending outgoing
    final discover = _mockUsers.where((u) {
      final s = _connectionStates[u.id]!;
      return s == _ConnectionState.suggested ||
          s == _ConnectionState.pending;
    }).toList();

    return ListView(
      key: const ValueKey('dashboard'),
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // Welcome header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding, 24, AppSpacing.screenPadding, 0,
          ),
          child: Text(
            'Welcome back, $_firstName',
            style: theme.textTheme.headlineSmall,
          ),
        ),
        // Status banner
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _StatusBanner(
            message: _svc.statusMessage,
            isScanning: _isScanning,
            onToggle: _isScanning ? _stopScanning : _startScanning,
          ),
        ),
        // Connected peer card (if any)
        if (_svc.connectedEndpointId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _ConnectedCard(
              peerName: _svc.connectedPeerName ?? 'Peer',
              receivedWord: _svc.receivedSecretWord,
            ),
          ),
        // Nearby Bluetooth peers
        if (peers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding, 20, AppSpacing.screenPadding, 8,
            ),
            child: Text(
              'Nearby',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          ...peers.map((peer) {
            final isConnected = peer.endpointId == _svc.connectedEndpointId;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              child: _PeerTile(
                peer: peer,
                isConnected: isConnected,
                theme: theme,
              ),
            );
          }),
        ],
        // ── Profile card sections ──
        _buildSection(theme, 'Connected', connected),
        _buildSection(theme, 'Requests', requests),
        _buildSection(theme, 'Discover', discover),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Profile bottom sheet ──────────────────────────────────────────────

  void _showProfileSheet(_MockUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final state = _connectionStates[user.id]!;
        final parts = user.name.trim().split(RegExp(r'\s+'));
        final initials = parts.length >= 2
            ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
            : user.name.isNotEmpty
                ? user.name[0].toUpperCase()
                : '?';

        String buttonLabel;
        bool buttonEnabled;
        Color buttonColor;
        VoidCallback? buttonAction;

        switch (state) {
          case _ConnectionState.incoming:
            buttonLabel = 'Accept';
            buttonEnabled = true;
            buttonColor = AppColors.primary;
            buttonAction = () {
              _acceptMockUser(user.id);
              Navigator.pop(ctx);
            };
          case _ConnectionState.pending:
            buttonLabel = 'Pending';
            buttonEnabled = false;
            buttonColor = AppColors.inactive;
            buttonAction = null;
          case _ConnectionState.suggested:
            buttonLabel = 'Connect';
            buttonEnabled = true;
            buttonColor = AppColors.primary;
            buttonAction = () {
              _connectMockUser(user.id);
              Navigator.pop(ctx);
            };
          case _ConnectionState.connected:
            buttonLabel = 'Connected';
            buttonEnabled = false;
            buttonColor = AppColors.inactive;
            buttonAction = null;
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLightBlue,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Name
              Text(
                user.name,
                style: GoogleFonts.sora(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              // Focus + Stage row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _MockProfileCard._focusIcons[user.focus] ??
                        Icons.work_rounded,
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    user.focus,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Icon(
                    _MockProfileCard._stageIcons[user.stage] ??
                        Icons.flag_rounded,
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    user.stage,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Bio
              Text(
                user.bio,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              // Action button
              SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeight,
                child: FilledButton(
                  onPressed: buttonEnabled ? buttonAction : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: buttonEnabled
                        ? AppColors.onPrimary
                        : AppColors.textTertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: Text(
                    buttonLabel,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Chat tab ─────────────────────────────────────────────────────────

  Widget _buildChatContent(ThemeData theme) {
    final connectedUsers = _mockUsers
        .where((u) => _connectionStates[u.id] == _ConnectionState.connected)
        .toList();

    return Column(
      key: const ValueKey('chat'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding, 24, AppSpacing.screenPadding, 16,
          ),
          child: Text('Messages', style: theme.textTheme.headlineSmall),
        ),
        Expanded(
          child: connectedUsers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No conversations yet',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connect with people to start chatting',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
                  itemCount: connectedUsers.length,
                  separatorBuilder: (context, index) => const Divider(
                    height: 0.5,
                    indent: AppSpacing.screenPadding + 56,
                  ),
                  itemBuilder: (context, index) {
                    final user = connectedUsers[index];
                    return _ChatListTile(
                      user: user,
                      onTap: () => _pushChatScreen(user),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Profile tab ────────────────────────────────────────────────────────

  Widget _buildProfileContent(ThemeData theme) {
    return Column(
      key: const ValueKey('profile'),
      children: [
        const Spacer(flex: 2),
        // Profile picture
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 2),
            ),
            child: ClipOval(
              child: widget.userPhotoUrl != null
                  ? Image.network(
                      widget.userPhotoUrl!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: AppColors.surfaceLightBlue,
                      alignment: Alignment.center,
                      child: Text(
                        _firstName.isNotEmpty
                            ? _firstName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Name
        Text(
          widget.displayName,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const Spacer(flex: 2),
        // Sign Out button
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: FilledButton(
            onPressed: widget.onSignOut,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceLightBlue,
              foregroundColor: AppColors.textPrimary,
            ),
            child: const Text('Sign Out'),
          ),
        ),
        const SizedBox(height: 12),
        // Delete Account button
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: FilledButton(
            onPressed: _isDeleting ? null : _deleteAccount,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Delete Account'),
          ),
        ),
        const SizedBox(height: 120),
      ],
    );
  }
}

// ── Mock profile card ────────────────────────────────────────────────────────

class _MockProfileCard extends StatelessWidget {
  final _MockUser user;
  final _ConnectionState state;
  final VoidCallback onTap;
  final VoidCallback? onChat;

  const _MockProfileCard({
    required this.user,
    required this.state,
    required this.onTap,
    this.onChat,
  });

  String get _initials {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
  }

  static const _focusIcons = <String, IconData>{
    'Startup': Icons.rocket_launch_rounded,
    'Research': Icons.science_rounded,
    'Side Project': Icons.handyman_rounded,
    'Open Source': Icons.public_rounded,
  };

  static const _stageIcons = <String, IconData>{
    'Idea': Icons.lightbulb_rounded,
    'MVP': Icons.construction_rounded,
    'Launched': Icons.rocket_rounded,
    'Scaling': Icons.trending_up_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surfaceLightBlue,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.name,
                          style: GoogleFonts.sora(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Pending chip
                      if (state == _ConnectionState.pending) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.textTertiary
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Pending',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Compatibility score
                  Text(
                    '${user.score}% match',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Chat icon — only visible when connected (rounded rectangle)
            if (state == _ConnectionState.connected) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onChat,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    size: 18,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Chat list tile ───────────────────────────────────────────────────────

class _ChatListTile extends StatelessWidget {
  final _MockUser user;
  final VoidCallback onTap;

  const _ChatListTile({required this.user, required this.onTap});

  static const _lastMessages = <String, String>{
    '1': 'We should collab sometime.',
    '2': 'Sounds great, let me know!',
    '3': 'Just shipped a new build.',
    '4': 'PR is up for review.',
    '5': 'Let me know if you want to chat about AI!',
    '6': 'Offline-first is the way to go.',
    '7': 'Mesh networking is wild stuff.',
  };

  String get _initials {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final preview = _lastMessages[user.id] ?? 'Tap to start chatting';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: 14,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surfaceLightBlue,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Timestamp
            Text(
              '2m ago',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Glass morphism nav bar ────────────────────────────────────────────────

class _GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _GlassNavBar({
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF797583).withValues(alpha: 0.18),
                const Color(0xFF363567).withValues(alpha: 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavBarItem(
                icon: Icons.dashboard_rounded,
                label: 'Dashboard',
                isSelected: selectedIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavBarItem(
                icon: Icons.chat_bubble_rounded,
                label: 'Chat',
                isSelected: selectedIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavBarItem(
                icon: Icons.person_rounded,
                label: 'Profile',
                isSelected: selectedIndex == 2,
                onTap: () => onTap(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isScanning;
  final VoidCallback onToggle;

  const _StatusBanner({
    required this.message,
    required this.isScanning,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isScanning
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isScanning
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
            size: 20,
            color: isScanning ? AppColors.primary : AppColors.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                color: isScanning
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isScanning ? 'Stop' : 'Scan',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connected card ────────────────────────────────────────────────────────

class _ConnectedCard extends StatelessWidget {
  final String peerName;
  final String? receivedWord;

  const _ConnectedCard({
    required this.peerName,
    this.receivedWord,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.handshake, size: 24, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected to $peerName',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                if (receivedWord != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Similarity check in progress\u2026',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Exchanging data\u2026',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Peer tile ─────────────────────────────────────────────────────────────

class _PeerTile extends StatelessWidget {
  final PeerDevice peer;
  final bool isConnected;
  final ThemeData theme;

  const _PeerTile({
    required this.peer,
    required this.isConnected,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            // Avatar
            Container(
              width: AppSpacing.avatarSize,
              height: AppSpacing.avatarSize,
              decoration: BoxDecoration(
                color: isConnected
                    ? AppColors.primary
                    : AppColors.surfaceLightBlue,
                borderRadius: BorderRadius.circular(AppRadius.avatar),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(peer.name),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color:
                      isConnected ? AppColors.onPrimary : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Name + subtitle
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peer.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    isConnected ? 'Connected' : 'Nearby',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isConnected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Connection status badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isConnected
                    ? AppColors.primary
                    : AppColors.surfaceGray,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth,
                size: 18,
                color: isConnected
                    ? AppColors.onPrimary
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
