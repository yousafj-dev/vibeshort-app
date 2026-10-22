import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/home/video_viewer_screen.dart';

/// Public creator profile (Phase 1 basic): info, stats,
/// Follow/Unfollow and their videos grid.
class PublicProfileScreen extends StatelessWidget {
  final String uid;

  const PublicProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final isMe = uid == AuthService.instance.uid;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder(
        stream: FirestoreService.instance.userProfile(uid),
        builder: (context, snap) {
          final profile = snap.data;
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          if (profile == null) {
            return const Center(
              child: Text('This profile is not available yet.',
                  style: TextStyle(color: AppTheme.muted)),
            );
          }
          final name = profile.displayOrFallback;
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
                      backgroundImage: profile.photoUrl.isNotEmpty
                          ? NetworkImage(profile.photoUrl)
                          : null,
                      child: profile.photoUrl.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
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
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                  if (profile.username.isNotEmpty)
                    Center(
                      child: Text('@${profile.username}',
                          style: const TextStyle(color: AppTheme.muted)),
                    ),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        profile.bio,
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
                  if (!isMe) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _FollowButton(targetUid: uid),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: Colors.white10),
                  if (videos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Text('No videos yet.',
                            style: TextStyle(color: AppTheme.muted)),
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
      child: v.thumbUrl.isNotEmpty
          ? Image.network(v.thumbUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _thumbFallback())
          : _thumbFallback(),
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

/// Follow / Following toggle for a public profile.
class _FollowButton extends StatelessWidget {
  final String targetUid;

  const _FollowButton({required this.targetUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: FirestoreService.instance.isFollowing(targetUid),
      builder: (context, snap) {
        final following = snap.data ?? false;
        return SizedBox(
          height: 46,
          child: following
              ? OutlinedButton(
                  onPressed: () => _set(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Following'),
                )
              : ElevatedButton(
                  onPressed: () => _set(context, true),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46)),
                  child: const Text('Follow'),
                ),
        );
      },
    );
  }

  Future<void> _set(BuildContext context, bool follow) async {
    try {
      await FirestoreService.instance.setFollowing(targetUid, follow);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }
}
