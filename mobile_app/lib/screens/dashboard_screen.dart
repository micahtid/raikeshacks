import 'package:flutter/material.dart';

import '../models/peer_device.dart';
import '../services/nearby_service.dart';
import '../theme.dart';

class DashboardScreen extends StatefulWidget {
  final String? userPhotoUrl;
  final VoidCallback onSignOut;
  final NearbyService nearbyService;

  const DashboardScreen({
    super.key,
    this.userPhotoUrl,
    required this.onSignOut,
    required this.nearbyService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isScanning = false;

  NearbyService get _svc => widget.nearbyService;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peers = _svc.discoveredPeers.values.toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding, 16, 16, 0,
              ),
              child: Row(
                children: [
                  Text('knkt', style: theme.appBarTheme.titleTextStyle),
                  const Spacer(),
                  if (widget.userPhotoUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppRadius.avatar),
                        child: Image.network(
                          widget.userPhotoUrl!,
                          width: AppSpacing.avatarSize,
                          height: AppSpacing.avatarSize,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: widget.onSignOut,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Sign Out',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Container(
                height: AppSpacing.searchBarHeight,
                decoration: BoxDecoration(
                  color: AppColors.surfaceGray,
                  borderRadius: BorderRadius.circular(AppRadius.searchBar),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Search people...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Status banner
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPadding,
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
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isScanning
            ? AppColors.surfaceLightBlue
            : AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(
            isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
            size: 18,
            color: isScanning ? AppColors.primary : AppColors.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isScanning
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onToggle,
            child: Text(
              isScanning ? 'Stop' : 'Scan',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
        color: AppColors.surfaceLightBlue,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
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
                      'Similarity check in progress…',
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
                          'Exchanging data…',
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

class _EmptyState extends StatelessWidget {
  final bool isScanning;

  const _EmptyState({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            isScanning
                ? 'Scanning for nearby people…'
                : 'Tap Scan to find people nearby',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

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
            // Avatar (squircle) — generated from initials
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
                  color: isConnected
                      ? AppColors.onPrimary
                      : AppColors.primary,
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
                  Text(
                    peer.name,
                    style: theme.textTheme.titleSmall,
                  ),
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
