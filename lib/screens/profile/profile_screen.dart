import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/home/video_viewer_screen.dart';
import 'package:vibeshort/screens/admin/admin_panel_screen.dart';
import 'package:vibeshort/screens/profile/edit_profile_screen.dart';
import 'package:vibeshort/screens/profile/settings_screen.dart';
import 'package:vibeshort/screens/wallet/wallet_screen.dart';

/// Own profile: header (photo, name, @username, bio), stats
/// (Videos / Following / Followers / Likes), Edit Profile button
/// and the my-videos grid.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in.',
              style: TextStyle(color: AppTheme.muted)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: FirestoreService.instance.userProfile(uid),
        builder: (context, snap) {
          final profile = snap.data;
          final name = profile?.displayOrFallback ??
              AuthService.instance.displayName;
          final username = profile?.username ?? '';
          final photo = (profile?.photoUrl.isNotEmpty ?? false)
              ? profile!.photoUrl
              : (AuthService.instance.photoUrl ?? '');
          final bio = profile?.bio ?? '';
          return StreamBuilder<List<VibeVideo>>(
            stream: FirestoreService.instance.userVideos(uid),
            builder: (context, vsnap) {
              final videos = vsnap.data ?? const <VibeVideo>[];
              final likesTotal =
                  videos.fold<int>(0, (sum, v) => sum + v.likes);
              return ListView(
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: CircleAvatar(
                      radius: 46,
                      backgroundColor: AppTheme.card,
                      backgroundImage:
                          photo.isNotEmpty ? NetworkImage(photo) : null,
                      child: photo.isEmpty
                          ? Text(
                              name.isNotEmpty
                                  ? name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      name,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                  if (username.isNotEmpty)
                    Center(
                      child: Text(
                        '@$username',
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                    ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        bio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _stat('${videos.length}', 'Videos'),
                      _countStat(
                          FirestoreService.instance.followingCount(uid),
                          'Following'),
                      _countStat(
                          FirestoreService.instance.followersCount(uid),
                          'Followers'),
                      _stat('$likesTotal', 'Likes'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const EditProfileScreen()),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit profile'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const WalletScreen()),
                      ),
                      icon: const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 18),
                      label: const Text('Wallet'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  // Phase 4: the Admin panel entry exists ONLY for
                  // accounts whose Firestore role is 'admin'.
                  if (profile?.isAdmin ?? false) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AdminPanelScreen()),
                        ),
                        icon: const Icon(Icons.shield_outlined, size: 18),
                        label: const Text('Admin panel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accent,
                          minimumSize: const Size.fromHeight(46),
                          side: const BorderSide(color: AppTheme.accent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: Colors.white10),
                  if (vsnap.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.accent)),
                    )
                  else if (videos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          'No videos yet.\nYour uploads will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.muted),
                        ),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: videos.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 3 / 4,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemBuilder: (context, i) =>
                          _gridTile(context, videos, i),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.muted)),
      ],
    );
  }

  Widget _countStat(Stream<int> stream, String label) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) => _stat('${snap.data ?? 0}', label),
    );
  }

  Widget _gridTile(BuildContext context, List<VibeVideo> videos, int i) {
    final v = videos[i];
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              VideoViewerScreen(videos: videos, initialPage: i),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          v.thumbUrl.isNotEmpty
              ? Image.network(v.thumbUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _thumbFallback())
              : _thumbFallback(),
          const Positioned(
            left: 6,
            bottom: 6,
            child: Row(
              children: [
                Icon(Icons.play_arrow, size: 15, color: Colors.white),
              ],
            ),
          ),
          Positioned(
            left: 22,
            bottom: 6,
            child: Text(
              '${v.likes}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 4)]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: const Center(
        child:
            Icon(Icons.play_circle_outline, color: Colors.white70, size: 30),
      ),
    );
  }
}
