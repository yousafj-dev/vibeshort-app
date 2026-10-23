import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';

/// Creator dashboard (settings pack): real totals for my own
/// account — videos posted, likes received, followers, following
/// and total views. Views are counted by the feed (once per
/// session per viewer, never for the owner) into each video's
/// `views` counter.
class CreatorDashboardScreen extends StatelessWidget {
  const CreatorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(
            child: Text('Please log in.',
                style: TextStyle(color: AppTheme.muted))),
      );
    }
    final fs = FirestoreService.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Creator dashboard')),
      body: StreamBuilder<List<VibeVideo>>(
        stream: fs.userVideos(uid),
        builder: (context, snap) {
          final videos = snap.data ?? const <VibeVideo>[];
          final likesTotal = videos.fold<int>(0, (s, v) => s + v.likes);
          final viewsTotal = videos.fold<int>(0, (s, v) => s + v.views);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Your content at a glance',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _card(Icons.video_library_outlined, '${videos.length}',
                      'Total videos'),
                  const SizedBox(width: 12),
                  _card(Icons.play_circle_outline, '$viewsTotal',
                      'Total views'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _card(Icons.favorite_border, '$likesTotal',
                      'Likes received'),
                  const SizedBox(width: 12),
                  _countCard(fs.followersCount(uid), Icons.people_outline,
                      'Followers'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _countCard(fs.followingCount(uid),
                      Icons.person_add_alt_outlined, 'Following'),
                  const SizedBox(width: 12),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Views count once per viewer per app session, and never for your own plays.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.accent, size: 24),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _countCard(Stream<int> stream, IconData icon, String label) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) =>
          _card(icon, '${snap.data ?? 0}', label),
    );
  }
}
