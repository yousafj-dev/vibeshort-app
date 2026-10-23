import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/screens/create/camera_record_screen.dart';
import 'package:vibeshort/screens/profile/public_profile_screen.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/services/sounds_service.dart';
import 'package:vibeshort/widgets/video_grid.dart';

/// Sound page (sound page round, TikTok style): opened by
/// tapping the sound line under a feed video's caption.
///
/// Two kinds of sound live here:
///  - a built-in LIBRARY sound — header shows the track and its
///    artist, the grid lists every video using that soundId;
///  - an ORIGINAL sound — one video's own audio. The page is
///    anchored at the source video (resolved through the tapped
///    video's soundSourceVideoId when the sound was reused), the
///    owner line credits its creator, and the grid lists the
///    source video plus every video that reused its sound.
///
/// "Use this sound" opens the camera with the sound already
/// attached: it plays during recording and is mixed in at post
/// time, with the attribution stored on the new video.
class SoundPageScreen extends StatefulWidget {
  /// The video whose sound line was tapped.
  final VibeVideo video;

  const SoundPageScreen({super.key, required this.video});

  @override
  State<SoundPageScreen> createState() => _SoundPageScreenState();
}

class _SoundPageScreenState extends State<SoundPageScreen> {
  /// Library mode: the catalogue entry (null when the stored
  /// soundId is no longer in the catalogue — the page then
  /// shows the stored name and lists videos, but cannot offer
  /// "Use this sound").
  VibeSound? _librarySound;
  String _librarySoundId = '';

  /// Original mode: the video that anchors the sound. Null
  /// while a reused sound's source is still being resolved, and
  /// stays null if the source video no longer exists.
  VibeVideo? _anchor;
  bool _resolvingAnchor = false;

  bool _preparing = false;

  bool get _isLibrary => _librarySoundId.isNotEmpty;

  /// The id whose videos the original-sound grid lists: the
  /// resolved anchor's id, falling back to the tapped video's
  /// stored source id while resolution runs.
  String get _originalAnchorId {
    final anchor = _anchor;
    if (anchor != null) return anchor.id;
    final v = widget.video;
    return v.soundSourceVideoId.isNotEmpty ? v.soundSourceVideoId : v.id;
  }

  @override
  void initState() {
    super.initState();
    final v = widget.video;
    if (v.soundId.isNotEmpty) {
      _librarySoundId = v.soundId;
      _librarySound = BuiltInSounds.byId(v.soundId);
      return;
    }
    if (v.soundSourceVideoId.isEmpty || v.soundSourceVideoId == v.id) {
      // This video IS the source of its original sound.
      _anchor = v;
      return;
    }
    // The sound was reused from another video: resolve the
    // source so the page (and any new reuse) credits it, never
    // a chain of 'original sound' hops.
    _resolvingAnchor = true;
    FirestoreService.instance.getVideo(v.soundSourceVideoId).then((src) {
      if (!mounted) return;
      if (src != null && src.soundId.isNotEmpty) {
        // The source's own audio was a library track after all:
        // prefer the library path (spec: no chains).
        setState(() {
          _resolvingAnchor = false;
          _librarySoundId = src.soundId;
          _librarySound = BuiltInSounds.byId(src.soundId);
        });
        return;
      }
      setState(() {
        _resolvingAnchor = false;
        _anchor = src; // may stay null if the source is gone
      });
    });
  }

  String get _title {
    if (_isLibrary) return _librarySound?.name ?? widget.video.soundName;
    return 'Original sound';
  }

  Future<void> _useThisSound() async {
    if (_preparing) return;
    setState(() => _preparing = true);
    try {
      final PreselectedSound pre;
      if (_isLibrary) {
        final sound = _librarySound;
        if (sound == null) {
          throw Exception('This sound is no longer available.');
        }
        final file = await SoundCache.fileFor(sound);
        pre = PreselectedSound(
          displayName: sound.name,
          soundId: sound.id,
          filePath: file.path,
        );
      } else {
        final anchor = _anchor;
        if (anchor == null) {
          throw Exception('The original video for this sound is gone.');
        }
        final file = await OriginalSoundCache.audioFileFor(anchor);
        pre = PreselectedSound(
          displayName: 'original sound — @${anchor.username}',
          filePath: file.path,
          sourceVideoId: anchor.id,
          ownerId: anchor.uid,
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CameraRecordScreen(initialSound: pre),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  void _openOwnerProfile() {
    final anchor = _anchor;
    if (anchor == null) return;
    final uid = anchor.uid;
    if (uid.isEmpty || uid == AuthService.instance.uid) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Sound')),
      body: Column(
        children: [
          _header(),
          const Divider(color: Colors.white10, height: 1),
          Expanded(child: _videosArea()),
          _useButton(),
        ],
      ),
    );
  }

  Widget _header() {
    final anchor = _anchor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SpinningDisc(
            imageUrl: _isLibrary ? null : anchor?.thumbUrl,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                if (_isLibrary)
                  Text(
                    _librarySound == null
                        ? 'VibeShort Sounds'
                        : 'VibeShort Sounds • ${_librarySound!.artist} • ${_librarySound!.durationLabel}',
                    style: const TextStyle(
                        color: AppTheme.muted, fontSize: 13),
                  )
                else if (anchor != null)
                  GestureDetector(
                    onTap: _openOwnerProfile,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ownerAvatar(anchor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '@${anchor.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    _resolvingAnchor
                        ? 'Loading…'
                        : widget.video.feedSoundLabel,
                    style: const TextStyle(
                        color: AppTheme.muted, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerAvatar(VibeVideo anchor) {
    final photo = anchor.userPhoto;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: photo.isEmpty ? AppTheme.primaryGradient : null,
        color: AppTheme.card,
      ),
      child: ClipOval(
        child: photo.isNotEmpty
            ? Image.network(photo,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarLetter(anchor))
            : _avatarLetter(anchor),
      ),
    );
  }

  Widget _avatarLetter(VibeVideo anchor) {
    final name = anchor.username;
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _videosArea() {
    if (_isLibrary) {
      return StreamBuilder<List<VibeVideo>>(
        stream:
            FirestoreService.instance.videosWithSoundId(_librarySoundId),
        builder: (context, snap) => _grid(snap, const []),
      );
    }
    if (_resolvingAnchor) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accent));
    }
    final anchorId = _originalAnchorId;
    return StreamBuilder<List<VibeVideo>>(
      stream: FirestoreService.instance.videosUsingOriginalSound(anchorId),
      builder: (context, snap) {
        final anchor = _anchor;
        final lead = (anchor != null && anchor.id == anchorId)
            ? <VibeVideo>[anchor]
            : const <VibeVideo>[];
        return _grid(snap, lead, excludeId: anchorId);
      },
    );
  }

  Widget _grid(
    AsyncSnapshot<List<VibeVideo>> snap,
    List<VibeVideo> lead, {
    String? excludeId,
  }) {
    if (snap.connectionState == ConnectionState.waiting && lead.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accent));
    }
    var videos = snap.data ?? const <VibeVideo>[];
    if (excludeId != null) {
      videos = videos.where((v) => v.id != excludeId).toList();
    }
    final all = [...lead, ...videos];
    if (all.isEmpty) {
      return const Center(
        child: Text(
          'No videos with this sound yet.',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              '${all.length} video${all.length == 1 ? '' : 's'}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ),
          VideoGrid(videos: all),
        ],
      ),
    );
  }

  Widget _useButton() {
    final enabled = !_preparing &&
        (_isLibrary ? _librarySound != null : _anchor != null);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton.icon(
              onPressed: enabled ? _useThisSound : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _preparing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.videocam, color: Colors.white),
              label: Text(
                _preparing ? 'Preparing sound…' : 'Use this sound',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The slowly spinning "disc" in the sound page header: a
/// vinyl-style circle (sweep gradient) carrying the source
/// video's thumbnail, or a music note for library sounds.
class _SpinningDisc extends StatefulWidget {
  final String? imageUrl;

  const _SpinningDisc({this.imageUrl});

  @override
  State<_SpinningDisc> createState() => _SpinningDiscState();
}

class _SpinningDiscState extends State<_SpinningDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Transform.rotate(
          angle: _anim.value * 2 * math.pi,
          child: Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Color(0xFF1B1B28),
                  Color(0xFF2E2E44),
                  Color(0xFF1B1B28),
                  Color(0xFF2E2E44),
                  Color(0xFF1B1B28),
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                  border: Border.all(color: Colors.black, width: 3),
                ),
                child: ClipOval(
                  child: url != null && url.isNotEmpty
                      ? Image.network(url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.music_note,
                              color: Colors.white,
                              size: 26))
                      : const Icon(Icons.music_note,
                          color: Colors.white, size: 26),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
