import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/widgets/video_feed.dart';

/// Home: the full-screen vertical "For You" feed.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder(
        stream: FirestoreService.instance.videoFeed(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final videos = snap.data ?? const [];
          if (videos.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.video_library_outlined,
                        size: 56, color: AppTheme.muted),
                    SizedBox(height: 14),
                    Text(
                      'No videos yet',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Tap the + button below to post the first video.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
            );
          }
          return Stack(
            children: [
              PagedVideoFeed(videos: videos),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(
                      child: Text(
                        'For You',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 6)
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
