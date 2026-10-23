import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
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
class VideoCard extends StatefulWidget {
  final VibeVideo video;
  final bool isActive;

  const VideoCard({super.key, required this.video, required this.isActive});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;
  bool _showPlayIcon = false;

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
    _initPlayer();
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
      if (widget.isActive) ctrl.play();
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
        _ctrl?.play();
      } else {
        _ctrl?.pause();
      }
    }
  }

  @override
  void dispose() {
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
  void _handleTap() {
    if (_clearDisplay) {
      setState(() => _clearDisplay = false);
      return;
    }
    _togglePlay();
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
