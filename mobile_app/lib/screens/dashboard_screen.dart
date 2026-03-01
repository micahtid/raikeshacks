import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_model.dart';
import '../services/backend_service.dart';
import '../services/ble_discovery_service.dart';
import '../services/connection_service.dart';
import '../services/background_service.dart';
import '../services/nearby_service.dart';
import '../theme.dart';
import 'chat_screen.dart';

// ── Dashboard screen ─────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final String? userPhotoUrl;
  final String displayName;
  final VoidCallback onSignOut;
  final NearbyService nearbyService;
  final ConnectionService connectionService;
  final BleDiscoveryService bleService;

  const DashboardScreen({
    super.key,
    this.userPhotoUrl,
    required this.displayName,
    required this.onSignOut,
    required this.nearbyService,
    required this.connectionService,
    required this.bleService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTab = 0;
  bool _isScanning = false;
  bool _isDeleting = false;
  bool _isClearingData = false;

  NearbyService get _svc => widget.nearbyService;
  ConnectionService get _connSvc => widget.connectionService;
  BleDiscoveryService get _bleSvc => widget.bleService;
  String get _firstName => widget.displayName.split(' ').first;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    _connSvc.addListener(_onChanged);
    _bleSvc.addListener(_onChanged);
    _startScanning();
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    _connSvc.removeListener(_onChanged);
    _bleSvc.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startScanning() async {
    final granted = await _svc.requestPermissions();
    if (!granted) return;

    // BLE advertising BEFORE anything else — Nearby Connections grabs the BLE
    // advertising slot internally, which blocks flutter_ble_peripheral.
    await _bleSvc.startAdvertising();

    // Start foreground service — runs BLE scanning in its own background
    // isolate so peer discovery continues when the app is minimized.
    // The main Dart isolate is paused by Android when backgrounded, so
    // scanning MUST happen in the background service isolate.
    await BackgroundServiceManager.start();

    // Nearby Connections (foreground only, richer payload exchange).
    await _svc.startBoth();

    if (mounted) setState(() => _isScanning = true);
  }

  Future<void> _stopScanning() async {
    await BackgroundServiceManager.stop();
    await _bleSvc.stopAll();
    await _svc.stopAll();
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fresh Start'),
        content: const Text(
          'This will remove all your connections and chat history. Your profile will be kept.',
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
            child: Text('Clear', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClearingData = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('student_uid');

      if (uid == null || uid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No account found')));
          setState(() => _isClearingData = false);
        }
        return;
      }

      final success = await BackendService.clearUserData(uid);
      if (success) {
        widget.connectionService.clearLocalData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All connections and chats cleared')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to clear data')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isClearingData = false);
    }
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
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('student_uid');

      if (uid == null || uid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No account found to delete')),
          );
          setState(() => _isDeleting = false);
        }
        return;
      }

      final success = await BackendService.deleteStudent(uid);
      if (success) {
        await prefs.remove('student_uid');
        widget.onSignOut();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete account')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  String _peerName(ConnectionModel conn) {
    final peerUid = conn.otherUid(_connSvc.myUid ?? '');
    final profile = _connSvc.peerProfiles[peerUid];
    if (profile != null) {
      final identity = profile['identity'] as Map<String, dynamic>?;
      return identity?['full_name'] as String? ?? 'Unknown';
    }
    return 'Unknown';
  }

  String _peerInitials(ConnectionModel conn) {
    final name = _peerName(conn);
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _connectionRoomId(ConnectionModel conn) {
    final uids = [conn.uid1, conn.uid2]..sort();
    return '${uids[0]}_${uids[1]}';
  }

  void _pushChatScreen(ConnectionModel conn) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peerName: _peerName(conn),
          peerInitials: _peerInitials(conn),
          roomId: _connectionRoomId(conn),
          myUid: _connSvc.myUid ?? '',
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

  Widget _buildConnectionSection(
    ThemeData theme,
    String title,
    List<ConnectionModel> connections,
    bool showAcceptButton,
  ) {
    if (connections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            20,
            AppSpacing.screenPadding,
            10,
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
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${connections.length}',
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
        ...connections.map((conn) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              0,
              AppSpacing.screenPadding,
              10,
            ),
            child: _ConnectionCard(
              conn: conn,
              peerName: _peerName(conn),
              peerInitials: _peerInitials(conn),
              myUid: _connSvc.myUid ?? '',
              showAcceptButton:
                  showAcceptButton && !conn.hasAccepted(_connSvc.myUid ?? ''),
              showChatButton: conn.isComplete,
              onTap: () => _showProfileSheet(conn),
              onAccept: () => _connSvc.acceptConnection(conn.connectionId),
              onChat: () => _pushChatScreen(conn),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDashboardContent(ThemeData theme) {
    final connected = _connSvc.connectedNearby;
    final pending = _connSvc.pendingRequests;

    return ListView(
      key: const ValueKey('dashboard'),
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // Welcome header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            24,
            AppSpacing.screenPadding,
            0,
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
        // ── Profile card sections ──
        _buildConnectionSection(theme, 'Connected', connected, false),
        _buildConnectionSection(theme, 'Requests', pending, true),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Profile bottom sheet ──────────────────────────────────────────────

  void _showProfileSheet(ConnectionModel conn) {
    final myUid = _connSvc.myUid ?? '';
    final name = _peerName(conn);
    final initials = _peerInitials(conn);
    final summary = conn.summaryFor(myUid);
    final iAccepted = conn.hasAccepted(myUid);
    final isComplete = conn.isComplete;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        String buttonLabel;
        bool buttonEnabled;
        Color buttonColor;
        VoidCallback? buttonAction;

        if (isComplete) {
          buttonLabel = 'Chat';
          buttonEnabled = true;
          buttonColor = AppColors.primary;
          buttonAction = () {
            Navigator.pop(ctx);
            _pushChatScreen(conn);
          };
        } else if (iAccepted) {
          buttonLabel = 'Pending';
          buttonEnabled = false;
          buttonColor = AppColors.inactive;
          buttonAction = null;
        } else {
          buttonLabel = 'Accept';
          buttonEnabled = true;
          buttonColor = AppColors.primary;
          buttonAction = () {
            _connSvc.acceptConnection(conn.connectionId);
            Navigator.pop(ctx);
          };
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
                name,
                style: GoogleFonts.sora(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              // Match percentage
              Text(
                '${conn.matchPercentage.toStringAsFixed(0)}% match',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              // Summary (from Gemini)
              if (summary != null && summary.isNotEmpty)
                Text(
                  summary,
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
                      borderRadius: BorderRadius.circular(AppRadius.button),
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
    final acceptedConnections = _connSvc.allAccepted;

    return Column(
      key: const ValueKey('chat'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            24,
            AppSpacing.screenPadding,
            16,
          ),
          child: Text('Messages', style: theme.textTheme.headlineSmall),
        ),
        Expanded(
          child: acceptedConnections.isEmpty
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
                  itemCount: acceptedConnections.length,
                  separatorBuilder: (context, index) => const Divider(
                    height: 0.5,
                    indent: AppSpacing.screenPadding + 56,
                  ),
                  itemBuilder: (context, index) {
                    final conn = acceptedConnections[index];
                    return _ChatListTile(
                      name: _peerName(conn),
                      initials: _peerInitials(conn),
                      summary: conn.summaryFor(_connSvc.myUid ?? ''),
                      onTap: () => _pushChatScreen(conn),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
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
        // Fresh Start button
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: FilledButton(
            onPressed: _isClearingData ? null : _clearData,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceLightBlue,
              foregroundColor: AppColors.textPrimary,
            ),
            child: _isClearingData
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary,
                    ),
                  )
                : const Text('Fresh Start'),
          ),
        ),
        const SizedBox(height: 12),
        // Delete Account button
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
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

// ── Connection card ──────────────────────────────────────────────────────────

class _ConnectionCard extends StatelessWidget {
  final ConnectionModel conn;
  final String peerName;
  final String peerInitials;
  final String myUid;
  final bool showAcceptButton;
  final bool showChatButton;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback? onChat;

  const _ConnectionCard({
    required this.conn,
    required this.peerName,
    required this.peerInitials,
    required this.myUid,
    required this.showAcceptButton,
    required this.showChatButton,
    required this.onTap,
    required this.onAccept,
    this.onChat,
  });

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
                peerInitials,
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
                  Text(
                    peerName,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${conn.matchPercentage.toStringAsFixed(0)}% match',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Accept button
            if (showAcceptButton) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onAccept,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Accept',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
            // Chat icon — only visible when connected
            if (showChatButton) ...[
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
  final String name;
  final String initials;
  final String? summary;
  final VoidCallback onTap;

  const _ChatListTile({
    required this.name,
    required this.initials,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = summary ?? 'Tap to start chatting';

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
                initials,
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
                    name,
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

  const _GlassNavBar({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: Container(
          height: 68,
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
