import 'package:flutter/material.dart';

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
      similarity: 94,
    ),
    _Profile(
      name: 'Marcus Chen',
      imageUrl: 'https://i.pravatar.cc/150?img=68',
      similarity: 87,
    ),
    _Profile(
      name: 'Sofia Reyes',
      imageUrl: 'https://i.pravatar.cc/150?img=45',
      similarity: 82,
    ),
    _Profile(
      name: 'James Okafor',
      imageUrl: 'https://i.pravatar.cc/150?img=53',
      similarity: 76,
    ),
    _Profile(
      name: 'Lina Johansson',
      imageUrl: 'https://i.pravatar.cc/150?img=44',
      similarity: 71,
    ),
    _Profile(
      name: 'Dev Kapoor',
      imageUrl: 'https://i.pravatar.cc/150?img=60',
      similarity: 65,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('knkt'),
        backgroundColor: colors.inversePrimary,
        actions: [
          if (userPhotoUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: onSignOut,
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(userPhotoUrl!),
                ),
              ),
            )
          else
            IconButton(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _profiles.length,
        itemBuilder: (context, index) {
          final profile = _profiles[index];
          return _ProfileCard(profile: profile, colors: colors, theme: theme);
        },
      ),
    );
  }
}

class _Profile {
  final String name;
  final String imageUrl;
  final int similarity;

  const _Profile({
    required this.name,
    required this.imageUrl,
    required this.similarity,
  });
}

class _ProfileCard extends StatelessWidget {
  final _Profile profile;
  final ColorScheme colors;
  final ThemeData theme;

  const _ProfileCard({
    required this.profile,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: NetworkImage(profile.imageUrl),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                profile.name,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${profile.similarity}%',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
