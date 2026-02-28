import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/peer_device.dart';
import '../services/nearby_service.dart';
import '../theme.dart';

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

  Widget _buildDashboardContent(ThemeData theme) {
    final peers = _svc.discoveredPeers.values.toList();

    return Column(
      key: const ValueKey('dashboard'),
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: 8),
        // Nearby peers list
        Expanded(
          child: peers.isEmpty
              ? _EmptyState(isScanning: _isScanning)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 100,
                  ),
                  itemCount: peers.length,
                  itemBuilder: (context, index) {
                    final peer = peers[index];
                    final isConnected =
                        peer.endpointId == _svc.connectedEndpointId;
                    return _PeerTile(
                      peer: peer,
                      isConnected: isConnected,
                      theme: theme,
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
                icon: Icons.person_rounded,
                label: 'Profile',
                isSelected: selectedIndex == 1,
                onTap: () => onTap(1),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
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

// ── Empty state ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isScanning;

  const _EmptyState({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isScanning
                  ? Icons.bluetooth_searching
                  : Icons.bluetooth_disabled,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              isScanning
                  ? 'Scanning for nearby people\u2026'
                  : 'Tap Scan to find people nearby',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
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
