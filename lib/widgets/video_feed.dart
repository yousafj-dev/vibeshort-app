import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/widgets/video_card.dart';

/// Vertical TikTok-style pager over a fixed list of videos.
/// Only the visible page's player is active; each page is keyed by
/// its video's document id so a card can never be re-bound to a
/// different video while keeping a stale player.
///
/// Pull-to-refresh (fix round, item 8): when [onRefresh] is set
/// and the user is on the FIRST video, dragging down past the top
/// edge accumulates a pull; releasing beyond the threshold runs
/// [onRefresh] (the parent reloads the feed, which rebuilds this
/// pager at page 0). Normal vertical swipes between videos are
/// untouched — overscroll only exists beyond the first page.
class PagedVideoFeed extends StatefulWidget {
  final List<VibeVideo> videos;
  final int initialPage;
  final Future<void> Function()? onRefresh;

  /// Forwarded to every card: false suspends playback (the
  /// shell's Home tab is not selected). Null in the standalone
  /// viewer, where tab state does not apply.
  final ValueListenable<bool>? hostVisible;

  const PagedVideoFeed({
    super.key,
    required this.videos,
    this.initialPage = 0,
    this.onRefresh,
    this.hostVisible,
  });

  @override
  State<PagedVideoFeed> createState() => _PagedVideoFeedState();
}

class _PagedVideoFeedState extends State<PagedVideoFeed> {
  late final PageController _pageCtrl;
  late int _current;

  /// Pull distance in logical px while overscrolling at page 0,
  /// and whether a refresh is currently running.
  double _pullPx = 0;
  bool _refreshing = false;

  static const double _pullThreshold = 80;
  static const double _pullCap = 120;

  @override
  void initState() {
    super.initState();
    _current = widget.initialPage
        .clamp(0, widget.videos.isEmpty ? 0 : widget.videos.length - 1);
    _pageCtrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (widget.onRefresh == null || _refreshing) return false;
    if (n is OverscrollNotification) {
      // Android (clamping physics): dragging past the top edge of
      // page 0 reports negative overscroll deltas.
      if (_current == 0 && n.overscroll < 0) {
        setState(() {
          _pullPx = (_pullPx - n.overscroll).clamp(0, _pullCap);
        });
      }
    } else if (n is ScrollUpdateNotification) {
      // Bouncing physics: the scroll position itself goes
      // negative past the top edge.
      if (_current == 0 && n.metrics.pixels < 0) {
        final double px = (-n.metrics.pixels).clamp(0.0, _pullCap).toDouble();
        if (px > _pullPx) setState(() => _pullPx = px);
      }
    } else if (n is ScrollEndNotification) {
      if (_pullPx >= _pullThreshold && _current == 0) {
        _runRefresh();
      } else if (_pullPx != 0) {
        setState(() => _pullPx = 0);
      }
    }
    return false;
  }

  Future<void> _runRefresh() async {
    final refresh = widget.onRefresh;
    if (refresh == null) return;
    setState(() {
      _refreshing = true;
      _pullPx = 0;
    });
    try {
      await refresh();
    } catch (e) {
      debugPrint('feed refresh failed: $e');
    }
    // The parent usually rebuilds this pager (new key) as part of
    // the refresh, so this state may already be disposed.
    if (!mounted) return;
    setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.videos;
    if (_current >= videos.length) _current = 0;
    final pager = PageView.builder(
      controller: _pageCtrl,
      scrollDirection: Axis.vertical,
      itemCount: videos.length,
      onPageChanged: (i) => setState(() {
        _current = i;
        if (i != 0) _pullPx = 0;
      }),
      itemBuilder: (context, i) => VideoCard(
        key: ValueKey(videos[i].id),
        video: videos[i],
        isActive: i == _current,
        hostVisible: widget.hostVisible,
      ),
    );
    if (widget.onRefresh == null) return pager;
    final showIndicator = _refreshing || _pullPx > 4;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: pager,
        ),
        if (showIndicator)
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black54,
                ),
                padding: const EdgeInsets.all(9),
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: AppTheme.accent,
                  value: _refreshing
                      ? null
                      : (_pullPx / _pullThreshold).clamp(0.0, 1.0),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
