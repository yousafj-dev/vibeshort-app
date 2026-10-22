import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/screens/home/video_viewer_screen.dart';

/// 3-column thumbnail grid over [videos]; tapping a tile opens the
/// full-screen viewer starting at that video. Shared by Discover
/// search results and the hashtag screen.
class VideoGrid extends StatelessWidget {
  final List<VibeVideo> videos;

  const VideoGrid({super.key, required this.videos});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: videos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 3 / 4,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, i) => _tile(context, i),
    );
  }

  Widget _tile(BuildContext context, int i) {
    final v = videos[i];
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoViewerScreen(videos: videos, initialPage: i),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          v.thumbUrl.isNotEmpty
              ? Image.network(v.thumbUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback())
              : _fallback(),
          Positioned(
            left: 5,
            bottom: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite, size: 12, color: Colors.white),
                const SizedBox(width: 3),
                Text(
                  '${v.likes}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: const Center(
        child:
            Icon(Icons.play_circle_outline, color: Colors.white70, size: 30),
      ),
    );
  }
}
