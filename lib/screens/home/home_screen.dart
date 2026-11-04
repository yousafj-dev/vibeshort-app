import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/services/prefs_service.dart';
import 'package:vibeshort/widgets/video_feed.dart';

/// Home: full-screen vertical feed with TikTok-style top tabs —
/// "Following" (videos from creators I follow, newest first) and
/// "For You" (the whole pool, in a per-session shuffled order).
/// For You is the default tab.
///
/// Feed refresh (fix round, items 7 + 8): re-tapping the Home tab
/// in the bottom nav calls [HomeScreenState.refreshFeed], and
/// pulling down on the first video triggers the same reload per
/// pane. A refresh bumps the pane's tick, which re-subscribes the
/// feed stream (a fresh query) and rebuilds the pager at page 0.
///
/// Feed freshness (test-apk-17): the For You pool is shuffled
/// ONCE per session (and once per manual refresh), so reopening
/// the app never lands on the same starting video — the id of
/// the previous session's opener is kept in PrefsService and a
/// fresh shuffle that would repeat it is swapped away from it.
/// A "Refresh" pill sits at the top-right of the feed, next to
/// the tabs; when a manual refresh finishes, a short-lived
/// "Feed refreshed — new videos" chip confirms it at the top.
/// The Following pane is untouched: still newest-first.
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

  /// "Feed refreshed" chip (test-apk-17): shown for ~2 s after a
  /// MANUAL refresh completes (top pill, Home re-tap, or the
  /// pull-down gesture) — never on an ordinary app open.
  bool _bannerVisible = false;
  Timer? _bannerTimer;

  /// Guards the top pill / Home re-tap against spam taps while a
  /// refresh is already running.
  bool _topRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, initialIndex: 1, vsync: this);
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
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
  /// Also the top Refresh pill's action (test-apk-17).
  void refreshFeed() {
    if (_tabs.index != 1) _tabs.animateTo(1);
    final pane = _forYouKey.currentState;
    if (pane == null || _topRefreshing) return;
    _topRefreshing = true;
    pane.refresh().whenComplete(() => _topRefreshing = false);
  }

  /// A pane finished a manual refresh: flash the confirmation
  /// chip at the top of the feed, then fade it out.
  void _showRefreshedBanner() {
    if (!mounted) return;
    setState(() => _bannerVisible = true);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _bannerVisible = false);
    });
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
              _FeedPane(
                  followingOnly: true,
                  hostVisible: hostVisible,
                  onRefreshed: _showRefreshedBanner),
              _FeedPane(
                  key: _forYouKey,
                  followingOnly: false,
                  hostVisible: hostVisible,
                  onRefreshed: _showRefreshedBanner),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: SizedBox(
                height: 48,
                child: Stack(
                  children: [
                    Center(
                      child: SizedBox(
                        width: 210,
                        child: TabBar(
                          controller: _tabs,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white60,
                          labelStyle: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 6)
                            ],
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 6)
                            ],
                          ),
                          indicator: const UnderlineTabIndicator(
                            borderSide:
                                BorderSide(color: Colors.white, width: 3),
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
                    // Refresh pill (test-apk-17): always visible at
                    // the top of the feed, right of the tabs. One
                    // tap re-shuffles For You and restarts it from
                    // a new first video.
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _topRefreshing ? null : refreshFeed,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh,
                                      size: 15, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'Refresh',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black87,
                                            blurRadius: 4)
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // "Feed refreshed" confirmation chip (test-apk-17):
          // fades in under the tabs after a manual refresh and
          // back out ~2 s later. IgnorePointer throughout, so it
          // never blocks a swipe or a tap while visible.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 54),
                child: Center(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _bannerVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                size: 15, color: AppTheme.accent),
                            SizedBox(width: 6),
                            Text(
                              'Feed refreshed — new videos',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
/// forwarded to the pager. [onRefreshed] fires when a manual
/// refresh (pull-down, top pill, Home re-tap) has completed, so
/// the home screen can flash its confirmation chip.
class _FeedPane extends StatefulWidget {
  final bool followingOnly;
  final ValueListenable<bool> hostVisible;
  final VoidCallback? onRefreshed;

  const _FeedPane({
    super.key,
    required this.followingOnly,
    required this.hostVisible,
    this.onRefreshed,
  });

  @override
  State<_FeedPane> createState() => _FeedPaneState();
}

class _FeedPaneState extends State<_FeedPane> {
  /// Bumped on every refresh: re-keys the stream subscription and
  /// the pager so the feed reloads and restarts at the first video.
  int _tick = 0;

  final Random _rng = Random();

  /// For You session order (test-apk-17): the shuffled order the
  /// pager actually renders. Null until the session's first
  /// snapshot lands (and again right after a refresh, until the
  /// fresh snapshot lands), at which point the pool is shuffled
  /// once and stored here. Later snapshots are reconciled INTO
  /// this order — objects refreshed, removed videos dropped,
  /// brand-new arrivals appended at the end — so scrolling
  /// within a session never reshuffles or repeats. Unused by
  /// the Following pane, which renders the stream order as-is.
  List<VibeVideo>? _sessionOrder;

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() {
      _tick++;
      // Test-apk-17: dropping the session order makes the fresh
      // snapshot reshuffle — a refresh always brings new videos,
      // never just the same list reloaded.
      _sessionOrder = null;
    });
    // Brief beat so the reload (and its spinner) is perceptible —
    // the fresh stream snapshot follows immediately after.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) widget.onRefreshed?.call();
  }

  /// Turns a raw stream snapshot (newest first) into the For You
  /// session order. First snapshot of a session: shuffle, then
  /// apply the different-opener rule — if the shuffle would open
  /// on the same video as last session (PrefsService) and the
  /// pool has an alternative, swap the opener with the next
  /// different video — and record the new opener for next time.
  List<VibeVideo> _applySessionOrder(List<VibeVideo> snapshot) {
    final order = _sessionOrder;
    if (order == null) {
      final shuffled = List<VibeVideo>.of(snapshot)..shuffle(_rng);
      if (shuffled.length > 1) {
        final lastFirst = PrefsService.lastFeedFirstId;
        if (lastFirst != null && shuffled.first.id == lastFirst) {
          final swapIdx =
              shuffled.indexWhere((v) => v.id != lastFirst, 1);
          if (swapIdx > 0) {
            final tmp = shuffled[0];
            shuffled[0] = shuffled[swapIdx];
            shuffled[swapIdx] = tmp;
          }
        }
      }
      _sessionOrder = shuffled;
      if (shuffled.isNotEmpty &&
          shuffled.first.id != PrefsService.lastFeedFirstId) {
        PrefsService.setLastFeedFirstId(shuffled.first.id);
      }
      return shuffled;
    }
    // Reconcile: keep the session order stable across snapshots.
    final byId = <String, VibeVideo>{for (final v in snapshot) v.id: v};
    final kept = <VibeVideo>[];
    final seen = <String>{};
    for (final old in order) {
      final fresh = byId[old.id];
      if (fresh != null && seen.add(old.id)) kept.add(fresh);
    }
    for (final v in snapshot) {
      if (seen.add(v.id)) kept.add(v);
    }
    _sessionOrder = kept;
    return kept;
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
        final pool = snap.data ?? const <VibeVideo>[];
        if (pool.isEmpty) {
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
                    style: TextStyle(
                        color: AppTheme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    followingOnly
                        ? 'Tap a creator\'s avatar in the feed and hit Follow.'
                        : 'Tap the + button below to post the first video.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          );
        }
        // For You renders the shuffled session order; Following
        // renders the stream's newest-first order untouched.
        final videos = followingOnly ? pool : _applySessionOrder(pool);
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
