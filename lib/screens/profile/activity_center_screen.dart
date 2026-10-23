import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/widgets/video_grid.dart';

/// Activity center (settings pack): two tabs — the videos I
/// liked and my watch history (recorded when a feed video
/// becomes the active playing page). Both are thumbnail grids;
/// tapping a tile opens the full-screen viewer.
class ActivityCenterScreen extends StatelessWidget {
  const ActivityCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: const Text('Activity center'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Liked videos'),
              Tab(text: 'Watch history'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _VideoList(
              stream: FirestoreService.instance.likedVideos(),
              emptyText: 'Videos you like will show up here.',
            ),
            _VideoList(
              stream: FirestoreService.instance.watchHistory(),
              emptyText: 'Videos you watch will show up here.',
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoList extends StatelessWidget {
  final Stream<List<VibeVideo>> stream;
  final String emptyText;

  const _VideoList({required this.stream, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VibeVideo>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.accent));
        }
        final videos = snap.data ?? const <VibeVideo>[];
        if (videos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted),
              ),
            ),
          );
        }
        return ListView(
          children: [
            VideoGrid(videos: videos),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
