import 'package:flutter/material.dart';

import '../theme.dart';

class DashboardScreen extends StatelessWidget {
  final String? userPhotoUrl;
  final VoidCallback onSignOut;

  const DashboardScreen({
    super.key,
    this.userPhotoUrl,
    required this.onSignOut,
  });

  static const _profiles = [
    _Profile(
      name: 'Anya Patel',
      imageUrl: 'https://i.pravatar.cc/150?img=47',
      subtitle: 'ML Engineer · HealthTech',
      similarity: 94,
    ),
    _Profile(
      name: 'Marcus Chen',
      imageUrl: 'https://i.pravatar.cc/150?img=68',
      subtitle: 'Full-stack Dev · B2B SaaS',
      similarity: 87,
    ),
    _Profile(
      name: 'Sofia Reyes',
      imageUrl: 'https://i.pravatar.cc/150?img=45',
      subtitle: 'Product Designer · EdTech',
      similarity: 82,
    ),
    _Profile(
      name: 'James Okafor',
      imageUrl: 'https://i.pravatar.cc/150?img=53',
      subtitle: 'Backend Dev · FinTech',
      similarity: 76,
    ),
    _Profile(
      name: 'Lina Johansson',
      imageUrl: 'https://i.pravatar.cc/150?img=44',
      subtitle: 'UX Researcher · Climate',
      similarity: 71,
    ),
    _Profile(
      name: 'Dev Kapoor',
      imageUrl: 'https://i.pravatar.cc/150?img=60',
      subtitle: 'Data Scientist · AI/ML',
      similarity: 65,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  if (userPhotoUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppRadius.avatar),
                        child: Image.network(
                          userPhotoUrl!,
                          width: AppSpacing.avatarSize,
                          height: AppSpacing.avatarSize,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: onSignOut,
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
            const SizedBox(height: 20),
            // Contact list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                itemCount: _profiles.length,
                itemBuilder: (context, index) {
                  final profile = _profiles[index];
                  return _ProfileTile(profile: profile, theme: theme);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Profile {
  final String name;
  final String imageUrl;
  final String subtitle;
  final int similarity;

  const _Profile({
    required this.name,
    required this.imageUrl,
    required this.subtitle,
    required this.similarity,
  });
}

class _ProfileTile extends StatelessWidget {
  final _Profile profile;
  final ThemeData theme;

  const _ProfileTile({
    required this.profile,
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
            // Avatar (squircle)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.avatar),
              child: Image.network(
                profile.imageUrl,
                width: AppSpacing.avatarSize,
                height: AppSpacing.avatarSize,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => Container(
                  width: AppSpacing.avatarSize,
                  height: AppSpacing.avatarSize,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLightBlue,
                    borderRadius: BorderRadius.circular(AppRadius.avatar),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: AppColors.surfaceMediumBlue,
                    size: 24,
                  ),
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
                    profile.name,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.subtitle,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Similarity badge
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${profile.similarity}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
