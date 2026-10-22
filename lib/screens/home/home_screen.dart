import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/widgets/video_feed.dart';

/// Home: full-screen vertical feed with TikTok-style top tabs —
/// "Following" (videos from creators I follow) and "For You"
/// (everything, newest first). For You is the default tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, initialIndex: 1, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: const [
              _FeedPane(followingOnly: true),
              _FeedPane(followingOnly: false),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: SizedBox(
                  width: 210,
                  child: TabBar(
                    controller: _tabs,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    labelStyle: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(color: Colors.white, width: 3),
                      insets: EdgeInsets.symmetric(horizontal: 34),
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Following'),
                      Tab(text: 'For You'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One home tab's feed body. [followingOnly] switches the stream and
/// the empty state.
class _FeedPane extends StatelessWidget {
  final bool followingOnly;

  const _FeedPane({required this.followingOnly});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService.instance;
    return StreamBuilder<List<VibeVideo>>(
      stream: followingOnly ? fs.followingFeed() : fs.videoFeed(),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    followingOnly
                        ? Icons.people_outline
                        : Icons.video_library_outlined,
                    size: 56,
                    color: AppTheme.muted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    followingOnly
                        ? 'Follow creators to see their videos here'
                        : 'No videos yet',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    followingOnly
                        ? 'Tap a creator\'s avatar in the feed and hit Follow.'
                        : 'Tap the + button below to post the first video.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          );
        }
        return PagedVideoFeed(videos: videos);
      },
    );
  }
}
