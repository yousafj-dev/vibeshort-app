import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/widgets/video_grid.dart';

/// All videos carrying one hashtag, as a thumbnail grid. Tapping a
/// tile opens the feed viewer starting at that video.
class HashtagVideosScreen extends StatelessWidget {
  /// The tag, without the leading '#'.
  final String tag;

  const HashtagVideosScreen({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text('#$tag')),
      body: StreamBuilder<List<VibeVideo>>(
        stream: FirestoreService.instance.videosByHashtag(tag),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final videos = snap.data ?? const <VibeVideo>[];
          if (videos.isEmpty) {
            return const Center(
              child: Text(
                'No videos with this hashtag yet.',
                style: TextStyle(color: AppTheme.muted),
              ),
            );
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text(
                    '${videos.length} video${videos.length == 1 ? '' : 's'}',
                    style:
                        const TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                ),
                VideoGrid(videos: videos),
              ],
            ),
          );
        },
      ),
    );
  }
}
