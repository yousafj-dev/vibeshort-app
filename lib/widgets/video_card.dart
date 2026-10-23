import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:vibeshort/core/route_observer.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/discover/hashtag_videos_screen.dart';
import 'package:vibeshort/screens/profile/public_profile_screen.dart';
import 'package:vibeshort/widgets/comments_sheet.dart';
import 'package:vibeshort/widgets/own_video_sheet.dart';
import 'package:vibeshort/widgets/report_sheet.dart';

/// Lighter Cloudinary delivery for playback: phones record big
/// files, and the feed only needs a 720p-wide stream. The original
/// file stays untouched in storage. Non-Cloudinary URLs play as-is.
String playbackUrlFor(String url) {
  if (!url.contains('/upload/')) return url;
  return url.replaceFirst(
      '/upload/', '/upload/q_auto:low,w_720,c_limit,vc_auto/');
}

/// One full-screen video in the feed: player + right rail
/// (avatar / like / comment / share) + caption block.
///
/// Playback suspension (bug fix): the shell keeps every tab
/// mounted in an IndexedStack, so a feed video used to keep
/// playing — sound included — after the user left Home, and a
/// pushed page (profile, hashtag, upload) never stopped it
/// either. Playback is now suspended while ANY blocker in
/// [_blockers] is present:
///  - 'tab': the shell says the Home tab is not selected
///    (drives [VideoCard.hostVisible]);
///  - 'route': a page route covers this card's route
///    (RouteAware via [appRouteObserver]);
///  - 'lifecycle': the app is backgrounded.
/// Suspending only pauses — the controller is never disposed or
/// re-seeked — and when the LAST blocker clears, playback
/// resumes from the preserved position ONLY if the video was
/// playing when the first blocker arrived, so a manual
/// single-tap pause survives leaving and returning.
class VideoCard extends StatefulWidget {
  final VibeVideo video;
  final bool isActive;

  /// Driven by the shell through the home feed: false while a
  /// different bottom-nav tab is selected. Null outside the
  /// shell feed (the standalone viewer), where tab state does
  /// not apply.
  final ValueListenable<bool>? hostVisible;

  const VideoCard({
    super.key,
    required this.video,
    required this.isActive,
    this.hostVisible,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard>
    with WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;
  bool _showPlayIcon = false;

  /// Active playback blockers — see the [VideoCard] doc.
  final Set<String> _blockers = {};

  /// Captured when the first blocker arrives: was the video
  /// playing (or about to autoplay as the active page)? Only
  /// then does clearing the last blocker resume playback.
  bool _resumeWhenUnblocked = false;

  /// Double-tap like: tap point of the current heart burst, and
  /// a counter so every burst restarts its animation.
  Offset? _burstAt;
  int _burstId = 0;

  // Fix round, item 3 (feed long-press menu) state.
  double _speed = 1.0;
  bool _clearDisplay = false;
  bool _captionsOn = true;

  // Optimistic like state, reconciled with the stream below.
  late bool _liked;
  late int _likes;

  /// Tap recognizers for the caption's hashtag spans; rebuilt with
  /// the spans and disposed with the card.
  final List<TapGestureRecognizer> _captionRecognizers = [];

  @override
  void initState() {
    super.initState();
    _liked = widget.video.likedByMe(AuthService.instance.uid);
    _likes = widget.video.likes;
    WidgetsBinding.instance.addObserver(this);
    final hostVisible = widget.hostVisible;
    if (hostVisible != null) {
      hostVisible.addListener(_onHostVisibleChanged);
      if (!hostVisible.value) _addBlocker('tab');
    }
    _initPlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to this card's enclosing route: a page pushed on
    // top of it (profile, hashtag page, settings...) suspends
    // playback until it pops again.
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => _addBlocker('route');

  @override
  void didPopNext() => _removeBlocker('route');

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _removeBlocker('lifecycle');
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _addBlocker('lifecycle');
    }
  }

  void _onHostVisibleChanged() {
    final hostVisible = widget.hostVisible;
    if (hostVisible == null) return;
    if (hostVisible.value) {
      _removeBlocker('tab');
    } else {
      _addBlocker('tab');
    }
  }

  /// Suspend playback for [reason]. Only the FIRST blocker
  /// captures the was-playing state and pauses; later blockers
  /// just stack, so overlapping suspensions (tab switch while a
  /// page is open, backgrounding on top of that) all have to
  /// clear before anything resumes.
  void _addBlocker(String reason) {
    if (!_blockers.add(reason)) return;
    if (_blockers.length > 1) return;
    final ctrl = _ctrl;
    if (ctrl != null && _ready) {
      _resumeWhenUnblocked = ctrl.value.isPlaying;
      if (_resumeWhenUnblocked) ctrl.pause();
    } else {
      // Player not ready yet: the active page would autoplay on
      // init, so remember to start it once unblocked (init
      // itself checks the blockers before playing).
      _resumeWhenUnblocked = widget.isActive;
    }
  }

  /// Lift one suspension. When the LAST blocker clears, resume
  /// from the preserved position — but only if the video was
  /// playing when it was suspended; a manual pause stays paused.
  void _removeBlocker(String reason) {
    if (!_blockers.remove(reason)) return;
    if (_blockers.isNotEmpty) return;
    final shouldResume = _resumeWhenUnblocked;
    _resumeWhenUnblocked = false;
    if (shouldResume && widget.isActive && _ready) {
      _ctrl?.play();
      if (_showPlayIcon && mounted) {
        setState(() => _showPlayIcon = false);
      }
    }
  }

  Future<void> _initPlayer() async {
    final url = playbackUrlFor(widget.video.videoUrl);
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _ctrl = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setPlaybackSpeed(_speed);
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _ready = true);
      if (widget.isActive) {
        if (_blockers.isEmpty) {
          ctrl.play();
        } else {
          // Became ready while suspended (off-tab, covered or
          // backgrounded): start when the last blocker clears.
          _resumeWhenUnblocked = true;
        }
      }
    } catch (e) {
      debugPrint('VideoCard init failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(VideoCard old) {
    super.didUpdateWidget(old);
    // Reconcile like state when the stream delivers fresh data.
    final freshLiked = widget.video.likedByMe(AuthService.instance.uid);
    if (freshLiked != _liked || widget.video.likes != _likes) {
      _liked = freshLiked;
      _likes = widget.video.likes;
    }
    if (old.isActive != widget.isActive && _ready) {
      if (widget.isActive) {
        if (_blockers.isEmpty) {
          _ctrl?.play();
        } else {
          // Swiped to while suspended: play once unblocked.
          _resumeWhenUnblocked = true;
        }
      } else {
        _ctrl?.pause();
        // A page that lost focus must never auto-resume later.
        _resumeWhenUnblocked = false;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    widget.hostVisible?.removeListener(_onHostVisibleChanged);
    for (final r in _captionRecognizers) {
      r.dispose();
    }
    _ctrl?.dispose();
    super.dispose();
  }

  /// Caption as rich text: `#tags` in the accent color, tappable to
  /// open that hashtag's video grid.
  InlineSpan _captionSpan(String caption) {
    for (final r in _captionRecognizers) {
      r.dispose();
    }
    _captionRecognizers.clear();
    const base = TextStyle(
      color: Colors.white,
      fontSize: 14,
      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in RegExp(r'#[A-Za-z0-9_]+').allMatches(caption)) {
      if (m.start > last) {
        spans.add(TextSpan(text: caption.substring(last, m.start)));
      }
      final tag = m.group(0)!.substring(1).toLowerCase();
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => HashtagVideosScreen(tag: tag)),
          );
        };
      _captionRecognizers.add(recognizer);
      spans.add(TextSpan(
        text: m.group(0),
        style: const TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.w700,
        ),
        recognizer: recognizer,
      ));
      last = m.end;
    }
    if (last < caption.length) {
      spans.add(TextSpan(text: caption.substring(last)));
    }
    return TextSpan(style: base, children: spans);
  }

  /// Tap on the video: in Clear display mode a tap only brings
  /// the UI back; otherwise it toggles play/pause as before.
  /// (With onDoubleTap registered, a single tap fires after the
  /// double-tap window — the standard GestureDetector pattern.)
  void _handleTap() {
    if (_clearDisplay) {
      setState(() => _clearDisplay = false);
      return;
    }
    _togglePlay();
  }

  /// Double-tap on the video (bug fix): toggles the like exactly
  /// like the rail heart — like when not liked, unlike when
  /// already liked — through the same optimistic like path.
  /// Liking also bursts a heart at the tap point (TikTok style);
  /// unliking has no burst.
  void _onDoubleTapDown(TapDownDetails details) {
    _burstAt = details.localPosition;
  }

  void _onDoubleTap() {
    final wasLiked = _liked;
    _toggleLike();
    if (!wasLiked) {
      setState(() => _burstId++);
    } else if (_burstAt != null) {
      setState(() => _burstAt = null);
    }
  }

  /// Long-press menu (fix round, item 3): Download, Playback
  /// speed, Clear display, Captions on/off, Share — plus the
  /// own-video actions when this is my video.
  void _openFeedMenu() {
    final video = widget.video;
    final isMine = video.uid == AuthService.instance.uid;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        Widget row(IconData icon, String label,
            {String? subtitle, VoidCallback? onTap}) {
          return ListTile(
            leading: Icon(icon, color: Colors.white),
            title: Text(label, style: const TextStyle(color: Colors.white)),
            subtitle: subtitle == null
                ? null
                : Text(subtitle,
                    style: const TextStyle(color: AppTheme.muted)),
            onTap: onTap,
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(Icons.download, 'Download video',
                  subtitle: 'Save to your gallery', onTap: () {
                Navigator.of(sheetCtx).pop();
                downloadVideoAction(context, video);
              }),
              row(Icons.speed, 'Playback speed',
                  subtitle: '${_speed}x', onTap: () {
                Navigator.of(sheetCtx).pop();
                _openSpeedMenu();
              }),
              row(Icons.visibility_off_outlined, 'Clear display',
                  subtitle: 'Hide all buttons and text', onTap: () {
                Navigator.of(sheetCtx).pop();
                setState(() => _clearDisplay = true);
              }),
              row(
                _captionsOn
                    ? Icons.closed_caption
                    : Icons.closed_caption_off_outlined,
                _captionsOn ? 'Captions: On' : 'Captions: Off',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  setState(() => _captionsOn = !_captionsOn);
                },
              ),
              row(Icons.share_outlined, 'Share', onTap: () {
                Navigator.of(sheetCtx).pop();
                _share();
              }),
              if (isMine) ...[
                const Divider(color: Colors.white10, height: 1),
                row(
                  video.pinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  video.pinned ? 'Unpin video' : 'Pin video',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    pinVideoAction(context, video);
                  },
                ),
                row(Icons.edit_outlined, 'Edit captions', onTap: () {
                  Navigator.of(sheetCtx).pop();
                  editCaptionAction(context, video);
                }),
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: Color(0xFFFF5C7A)),
                  title: const Text('Delete video',
                      style: TextStyle(color: Color(0xFFFF5C7A))),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    deleteVideoAction(context, video);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Playback-speed chooser for the long-press menu.
  void _openSpeedMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Playback speed',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              for (final s in const [0.5, 1.0, 1.5, 2.0])
                ListTile(
                  title: Text('${s}x',
                      style: const TextStyle(color: Colors.white)),
                  trailing: _speed == s
                      ? const Icon(Icons.check, color: AppTheme.accent)
                      : null,
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    setState(() => _speed = s);
                    await _ctrl?.setPlaybackSpeed(s);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _togglePlay() {
    final ctrl = _ctrl;
    if (ctrl == null || !_ready) return;
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
        _showPlayIcon = true;
      } else {
        ctrl.play();
        _showPlayIcon = false;
      }
    });
  }

  Future<void> _toggleLike() async {
    final wasLiked = _liked;
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    try {
      await FirestoreService.instance.toggleLike(widget.video);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likes = widget.video.likes;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(video: widget.video),
    );
  }

  Future<void> _share() async {
    try {
      await Share.share(widget.video.videoUrl,
          subject: 'Watch on VibeShort');
    } catch (e) {
      debugPrint('share failed: $e');
    }
  }

  void _openProfile() {
    final uid = widget.video.uid;
    if (uid.isEmpty || uid == AuthService.instance.uid) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
    );
  }

  /// Overflow menu (Phase 4, blueprint Section 9): report this
  /// video, or block its creator so their videos leave my feeds.
  void _openMoreMenu() {
    final video = widget.video;
    final isMine = video.uid == AuthService.instance.uid;
    // Fix round, item 2: my own videos get the own-video action
    // sheet (Download / Pin / Edit captions / Share / Delete)
    // instead of the report/block menu.
    if (isMine) {
      showOwnVideoActions(context, video);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: Colors.white),
                title: const Text('Report video',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  showReportSheet(
                    context,
                    targetType: 'video',
                    targetId: video.id,
                    targetOwnerId: video.uid,
                    targetLabel: 'video',
                  );
                },
              ),
              if (!isMine)
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.white),
                  title: Text('Block @${video.username}',
                      style: const TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    await confirmAndBlockUser(
                      context,
                      targetUid: video.uid,
                      targetName: '@${video.username}',
                    );
                  },
                ),
              ListTile(
                leading:
                    const Icon(Icons.close, color: Colors.white),
                title: const Text('Cancel',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(sheetCtx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Player (cover-fit) or states
          GestureDetector(
            onTap: _handleTap,
            onDoubleTapDown: _onDoubleTapDown,
            onDoubleTap: _onDoubleTap,
            onLongPress: _openFeedMenu,
            child: _failed
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            color: AppTheme.muted, size: 40),
                        SizedBox(height: 8),
                        Text('Could not play this video',
                            style: TextStyle(color: AppTheme.muted)),
                      ],
                    ),
                  )
                : _ready && _ctrl != null
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _ctrl!.value.size.width,
                          height: _ctrl!.value.size.height,
                          child: VideoPlayer(_ctrl!),
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.accent),
                      ),
          ),
          if (_showPlayIcon && _ready && !_clearDisplay)
            const Center(
              child: Icon(Icons.play_arrow,
                  size: 84, color: Colors.white70),
            ),
          // Double-tap heart burst, centred on the tap point.
          if (_burstAt != null)
            Positioned.fill(
              child: IgnorePointer(
                child: _HeartBurst(
                  key: ValueKey(_burstId),
                  center: _burstAt!,
                  onDone: () {
                    if (mounted) setState(() => _burstAt = null);
                  },
                ),
              ),
            ),
          // Bottom gradient for caption readability
          if (!_clearDisplay)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 180,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
          // Caption block (bottom-left, clear of the rail)
          if (!_clearDisplay)
          Positioned(
            left: 14,
            right: 92,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _openProfile,
                  child: Text(
                    '@${video.username}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                  ),
                ),
                if (_captionsOn && video.caption.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  RichText(
                    text: _captionSpan(video.caption),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.music_note,
                        size: 15, color: Colors.white),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        video.soundName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Right rail
          if (!_clearDisplay)
          Positioned(
            right: 10,
            bottom: 90,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatarButton(),
                const SizedBox(height: 22),
                _railButton(
                  icon: _liked ? Icons.favorite : Icons.favorite,
                  color: _liked ? const Color(0xFFFF3B5C) : Colors.white,
                  label: '$_likes',
                  onTap: _toggleLike,
                ),
                const SizedBox(height: 20),
                _railButton(
                  icon: Icons.mode_comment,
                  color: Colors.white,
                  label: '${video.commentCount}',
                  onTap: _openComments,
                ),
                const SizedBox(height: 20),
                _railButton(
                  icon: Icons.share,
                  color: Colors.white,
                  label: 'Share',
                  onTap: _share,
                ),
                const SizedBox(height: 20),
                _railButton(
                  icon: Icons.more_vert,
                  color: Colors.white,
                  label: 'More',
                  onTap: _openMoreMenu,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarButton() {
    final photo = widget.video.userPhoto;
    return GestureDetector(
      onTap: _openProfile,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          gradient: photo.isEmpty ? AppTheme.primaryGradient : null,
          color: AppTheme.card,
        ),
        child: ClipOval(
          child: photo.isNotEmpty
              ? Image.network(photo, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _avatarLetter())
              : _avatarLetter(),
        ),
      ),
    );
  }

  Widget _avatarLetter() {
    final name = widget.video.username;
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _railButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black38,
            ),
            child: Icon(icon, color: color, size: 27),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

/// TikTok-style heart burst shown at the double-tap point when a
/// video is liked: pops in with a slight tilt, drifts up a
/// little, then fades out (~650 ms) and reports [onDone] so the
/// card can remove it.
class _HeartBurst extends StatefulWidget {
  final Offset center;
  final VoidCallback onDone;

  const _HeartBurst({super.key, required this.center, required this.onDone});

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      });
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final t = _anim.value;
            // Pop: overshoot to 1.15 by 35%, settle at 1.0.
            final scale = t < 0.35
                ? Curves.easeOutBack.transform(t / 0.35) * 1.15
                : 1.15 - 0.15 * ((t - 0.35) / 0.65);
            // Fade out over the last 40%.
            final opacity = t < 0.6 ? 1.0 : 1.0 - (t - 0.6) / 0.4;
            return Positioned(
              left: widget.center.dx - 45,
              top: widget.center.dy - 45 - 14 * t,
              width: 90,
              height: 90,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: -0.16,
                  child: Transform.scale(
                    scale: scale,
                    child: const Icon(
                      Icons.favorite,
                      size: 90,
                      color: Color(0xFFFF3B5C),
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 18),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
