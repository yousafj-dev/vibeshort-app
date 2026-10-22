import 'package:flutter/material.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/widgets/video_feed.dart';

/// Full-screen viewer opened from a profile grid: pages through the
/// given videos starting at [initialPage].
class VideoViewerScreen extends StatelessWidget {
  final List<VibeVideo> videos;
  final int initialPage;

  const VideoViewerScreen({
    super.key,
    required this.videos,
    this.initialPage = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PagedVideoFeed(videos: videos, initialPage: initialPage),
          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
