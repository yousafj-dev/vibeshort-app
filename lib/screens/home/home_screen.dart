import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/widgets/video_feed.dart';

/// Home: full-screen vertical feed with TikTok-style top tabs —
/// "Following" (videos from creators I follow) and "For You"
/// (everything, newest first). For You is the default tab.
///
/// Feed refresh (fix round, items 7 + 8): re-tapping the Home tab
/// in the bottom nav calls [HomeScreenState.refreshFeed], and
/// pulling down on the first video triggers the same reload per
/// pane. A refresh bumps the pane's tick, which re-subscribes the
/// feed stream (a fresh query) and rebuilds the pager at page 0.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _forYouKey = GlobalKey<_FeedPaneState>();

  /// Playback gate for the whole home feed, driven by the shell:
  /// false while a different bottom-nav tab is selected. The
  /// shell's IndexedStack keeps Home mounted off-tab, so without
  /// this the current video kept playing (with sound) on other
  /// tabs. Cards suspend on false and resume on true — but only
  /// if they were playing when suspended.
  final ValueNotifier<bool> hostVisible = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, initialIndex: 1, vsync: this);
  }

  @override
  void dispose() {
    hostVisible.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// Called by the shell on every bottom-nav switch.
  void setHostVisible(bool visible) {
    if (hostVisible.value != visible) hostVisible.value = visible;
  }

  /// Item 7: Home tab re-tapped while already on Home — jump to
  /// the For You tab and reload its feed from the first video.
  void refreshFeed() {
    if (_tabs.index != 1) _tabs.animateTo(1);
    _forYouKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              _FeedPane(followingOnly: true, hostVisible: hostVisible),
              _FeedPane(
                  key: _forYouKey,
                  followingOnly: false,
                  hostVisible: hostVisible),
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
/// the empty state. [hostVisible] is the shell's playback gate,
/// forwarded to the pager.
class _FeedPane extends StatefulWidget {
  final bool followingOnly;
  final ValueListenable<bool> hostVisible;

  const _FeedPane({
    super.key,
    required this.followingOnly,
    required this.hostVisible,
  });

  @override
  State<_FeedPane> createState() => _FeedPaneState();
}

class _FeedPaneState extends State<_FeedPane> {
  /// Bumped on every refresh: re-keys the stream subscription and
  /// the pager so the feed reloads and restarts at the first video.
  int _tick = 0;

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() => _tick++);
    // Brief beat so the reload (and its spinner) is perceptible —
    // the fresh stream snapshot follows immediately after.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService.instance;
    final followingOnly = widget.followingOnly;
    return StreamBuilder<List<VibeVideo>>(
      key: ValueKey('pane_${followingOnly}_$_tick'),
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
        return PagedVideoFeed(
          key: ValueKey('feed_${followingOnly}_$_tick'),
          videos: videos,
          onRefresh: refresh,
          hostVisible: widget.hostVisible,
        );
      },
    );
  }
}
