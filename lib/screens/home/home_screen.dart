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
/// The Following pane is untouched: still newest-first.
///
/// Refresh UI (test-apk-18, user's explicit spec): there is NO
/// on-screen refresh button anywhere — the build-17 "Refresh"
/// pill at the top of the feed is removed. Refresh is triggered
/// only by the pull-down gesture on the first video (or by
/// re-tapping Home). While it runs, a small popup at the top
/// reads "Refreshing…"; when it completes the popup turns into
/// "Feed refreshed — new videos" for ~2 s, then dismisses.
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

  /// Refresh popup (test-apk-18): hidden → refreshing while a
  /// manual refresh (pull-down, Home re-tap) runs → done for
  /// ~2 s once it completes. Never shown on an ordinary app open.
  _RefreshPopup _popup = _RefreshPopup.hidden;
  Timer? _popupTimer;

  /// Guards Home re-tap against spam while a refresh is already
  /// running.
  bool _topRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, initialIndex: 1, vsync: this);
  }

  @override
  void dispose() {
    _popupTimer?.cancel();
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
  /// (test-apk-18: the only triggers are this and the pull-down
  /// gesture — there is no refresh button.)
  void refreshFeed() {
    if (_tabs.index != 1) _tabs.animateTo(1);
    final pane = _forYouKey.currentState;
    if (pane == null || _topRefreshing) return;
    _topRefreshing = true;
    pane.refresh().whenComplete(() => _topRefreshing = false);
  }

  /// A pane started a manual refresh: the popup switches to its
  /// "Refreshing…" state.
  void _onRefreshStarted() {
    if (!mounted) return;
    _popupTimer?.cancel();
    setState(() => _popup = _RefreshPopup.refreshing);
  }

  /// A pane finished a manual refresh: the popup switches to
  /// "Feed refreshed — new videos" and dismisses after ~2 s.
  void _onRefreshed() {
    if (!mounted) return;
    setState(() => _popup = _RefreshPopup.done);
    _popupTimer?.cancel();
    _popupTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _popup = _RefreshPopup.hidden);
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
                  onRefreshStarted: _onRefreshStarted,
                  onRefreshed: _onRefreshed),
              _FeedPane(
                  key: _forYouKey,
                  followingOnly: false,
                  hostVisible: hostVisible,
                  onRefreshStarted: _onRefreshStarted,
                  onRefreshed: _onRefreshed),
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
                    // test-apk-18: NO refresh button here —
                    // the build-17 pill is removed per the
                    // user's spec. Pull down on the first video
                    // (or re-tap Home) to refresh; the popup
                    // below reports progress.
                  ],
                ),
              ),
            ),
          ),
          // Refresh popup (test-apk-18): a small pill popup under
          // the tabs. It appears when a pull-down (or Home
          // re-tap) refresh starts — spinner + "Refreshing…" —
          // and turns into "Feed refreshed — new videos" for
          // ~2 s when the refresh completes, then dismisses.
          // IgnorePointer throughout, so it never blocks a swipe
          // or a tap on the video behind it.
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
                      opacity: _popup == _RefreshPopup.hidden ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_popup == _RefreshPopup.refreshing) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 7),
                              const Text(
                                'Refreshing…',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else ...[
                              const Icon(Icons.check_circle,
                                  size: 15, color: AppTheme.accent),
                              const SizedBox(width: 6),
                              const Text(
                                'Feed refreshed — new videos',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
/// forwarded to the pager. [onRefreshStarted] / [onRefreshed]
/// bracket a manual refresh (pull-down or Home re-tap), so the
/// home screen can drive its refresh popup (test-apk-18).
class _FeedPane extends StatefulWidget {
  final bool followingOnly;
  final ValueListenable<bool> hostVisible;
  final VoidCallback? onRefreshStarted;
  final VoidCallback? onRefreshed;

  const _FeedPane({
    super.key,
    required this.followingOnly,
    required this.hostVisible,
    this.onRefreshStarted,
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
    widget.onRefreshStarted?.call();
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

/// States of the top refresh popup (test-apk-18).
enum _RefreshPopup { hidden, refreshing, done }
