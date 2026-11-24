import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/face_effects.dart';
import 'package:vibeshort/services/sounds_service.dart';
import 'package:vibeshort/services/upload_manager_service.dart';
import 'package:vibeshort/services/video_edit_service.dart';
import 'package:vibeshort/widgets/sounds_sheet.dart';

/// Edit + post screen (Editing phase). Every video — recorded in
/// the in-app camera (with a filter/effect already chosen live) or
/// picked from the gallery — lands here before posting.
///
/// The preview applies the selected look live (a ColorFilter matrix
/// approximation for colour filters and grade effects), the trim
/// window loops in the preview, and the overlay text is drawn at its
/// chosen position. On post, the exact filter/effect chain, trim,
/// music change and text are baked by FFmpeg in the background
/// (see [BakeRecipe]) and the result is uploaded — the user waits
/// on the feed, not here. With no edits chosen the original file
/// is uploaded untouched.
class EditVideoScreen extends StatefulWidget {
  final String videoPath;

  /// Look chosen LIVE on the record screen — pre-selected here so
  /// the posted video gets exactly that baked in.
  final String? initialFilterName;
  final String? initialEffectName;

  /// Built-in sound chosen on the record screen BEFORE recording
  /// (fix round, item 6): it arrives as the already-downloaded
  /// cache file and is mixed in as the video's music, with the
  /// sound attribution stored on the video doc.
  final String? initialSoundId;
  final String? initialSoundName;
  final String? initialSoundPath;

  /// "Use this sound" attribution (sound page round): when the
  /// incoming sound is another video's ORIGINAL sound, the
  /// source video id and its owner's uid ride along so the
  /// posted doc credits them. Null for library/device sounds.
  final String? initialSoundSourceVideoId;
  final String? initialSoundOwnerId;

  /// Face track logged on the record screen (camera upgrade
  /// round): present only when the clip was recorded in-app with
  /// a face sticker selected and at least one face was detected.
  /// The chosen sticker is baked over the face on post.
  final FaceTrackData? faceTrack;

  /// Called after a successful post (shell switches to Home).
  final VoidCallback? onPosted;

  const EditVideoScreen({
    super.key,
    required this.videoPath,
    this.initialFilterName,
    this.initialEffectName,
    this.initialSoundId,
    this.initialSoundName,
    this.initialSoundPath,
    this.initialSoundSourceVideoId,
    this.initialSoundOwnerId,
    this.faceTrack,
    this.onPosted,
  });

  @override
  State<EditVideoScreen> createState() => _EditVideoScreenState();
}

class _EditVideoScreenState extends State<EditVideoScreen> {
  final _caption = TextEditingController();
  final _overlay = TextEditingController();

  VideoPlayerController? _player;
  VideoFilter _filter = VideoFilters.all.first;
  VideoEffect _effect = VideoEffects.none;
  MusicMode _musicMode = MusicMode.original;
  String? _musicPath;
  String? _musicName;

  /// Built-in sound id when the attached music is one of the
  /// app's royalty-free sounds (item 6); null for device files.
  String? _soundId;

  /// "Use this sound" attribution (sound page round): set while
  /// the attached music is another video's original sound;
  /// cleared whenever the music changes to anything else.
  String? _soundSourceVideoId;
  String? _soundOwnerId;
  OverlayPosition _textPos = OverlayPosition.bottom;

  /// Frame shape (editor round 2): centre-crop baked on post.
  VideoCropAspect _crop = VideoCropAspect.original;

  /// Song-start picker (editor round 2): [_musicStartSec] is how
  /// far into the attached track playback begins; [_musicDurSec]
  /// is the track's length (0 = unknown — the picker stays hidden
  /// until the length is known: catalogue sounds carry theirs,
  /// device files are probed with FFprobe).
  double _musicStartSec = 0;
  double _musicDurSec = 0;

  /// Text styling (editor round 2): colour (a drawtext value from
  /// [OverlayTextColors]), size multiplier, bold outline and the
  /// background box.
  String _textColor = 'white';
  double _textScale = 1.0;
  bool _textBold = true;
  bool _textBg = false;

  /// Face sticker to bake (camera upgrade round): starts as the
  /// sticker recorded with; the user may switch it (the logged
  /// face geometry is sticker-agnostic) or remove it entirely.
  FaceStickerKind? _faceKind;

  // Trim window in seconds (start 0, end = full duration = untrimmed).
  double _trimStartSec = 0;
  double _trimEndSec = 0;

  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final filterName = widget.initialFilterName;
    if (filterName != null) {
      _filter = VideoFilters.all.firstWhere(
        (f) => f.name == filterName,
        orElse: () => VideoFilters.all.first,
      );
    }
    final effectName = widget.initialEffectName;
    if (effectName != null) {
      _effect = VideoEffects.all.firstWhere(
        (fx) => fx.name == effectName,
        orElse: () => VideoEffects.none,
      );
    }
    _faceKind = widget.faceTrack?.recordedKind;
    // A built-in sound picked before recording rides in as the
    // music track: replace mode with its cache file as the source.
    if (widget.initialSoundPath != null) {
      _musicMode = MusicMode.replace;
      _musicPath = widget.initialSoundPath;
      _musicName = widget.initialSoundName;
      _soundId = widget.initialSoundId;
      _soundSourceVideoId = widget.initialSoundSourceVideoId;
      _soundOwnerId = widget.initialSoundOwnerId;
      _resolveMusicDuration();
    }
    _initPlayer();
  }

  /// Length of the kept segment — the part of the video the
  /// attached song has to cover.
  double get _clipDurSec {
    if (_durationSec <= 0) return 0;
    if (!_trimActive) return _durationSec;
    final kept = _trimEndSec - _trimStartSec;
    return kept > 0 ? kept : _durationSec;
  }

  /// Furthest the song may start so it still covers the clip.
  double get _maxMusicStart {
    final m = _musicDurSec - _clipDurSec;
    return m > 0 ? m : 0;
  }

  /// Learns the attached track's length for the song-start
  /// picker: catalogue sounds know theirs; anything else is
  /// probed from the file. A new track resets the start offset.
  Future<void> _resolveMusicDuration() async {
    final sid = _soundId;
    final path = _musicPath;
    var dur = 0.0;
    if (sid != null) {
      dur = (BuiltInSounds.byId(sid)?.durationSec ?? 0).toDouble();
    } else if (path != null) {
      dur = await VideoEditService.probeDurationSeconds(path) ?? 0;
    }
    if (!mounted) return;
    setState(() {
      _musicDurSec = dur;
      _musicStartSec = 0;
    });
  }

  Future<void> _initPlayer() async {
    final c = VideoPlayerController.file(File(widget.videoPath));
    try {
      await c.initialize();
      await c.setLooping(true);
    } catch (e) {
      // A corrupt or unreadable clip must not escape as an
      // uncaught async error (Crashlytics "crash"): drop the
      // controller and leave the preview empty instead.
      debugPrint('EditVideo: preview init failed: $e');
      await c.dispose();
      return;
    }
    if (!mounted) {
      c.dispose();
      return;
    }
    _trimEndSec = c.value.duration.inMilliseconds / 1000.0;
    c.addListener(_trimLoop);
    setState(() => _player = c);
    c.play();
  }

  /// Keeps preview playback inside the trim window: reaching the
  /// chosen end jumps back to the chosen start.
  void _trimLoop() {
    final c = _player;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) {
      return;
    }
    final pos = c.value.position.inMilliseconds / 1000.0;
    if (_trimEndSec > _trimStartSec && pos >= _trimEndSec - 0.05) {
      c.seekTo(Duration(milliseconds: (_trimStartSec * 1000).round()));
    }
  }

  @override
  void dispose() {
    _player?.removeListener(_trimLoop);
    _caption.dispose();
    _overlay.dispose();
    _player?.dispose();
    super.dispose();
  }

  double get _durationSec =>
      (_player?.value.duration.inMilliseconds ?? 0) / 1000.0;

  bool get _trimActive =>
      _durationSec > 0 &&
      (_trimStartSec > 0.05 || _trimEndSec < _durationSec - 0.05);

  VideoEditOptions get _options => VideoEditOptions(
        filter: _filter,
        effect: _effect,
        musicMode: _musicMode,
        musicPath: _musicPath,
        musicStartOffset: _musicMode == MusicMode.replace
            ? Duration(
                milliseconds:
                    (_musicStartSec.clamp(0, _maxMusicStart) * 1000)
                        .round())
            : Duration.zero,
        cropAspect: _crop,
        overlayText: _overlay.text,
        overlayPosition: _textPos,
        overlayColor: _textColor,
        overlaySizeScale: _textScale,
        overlayBold: _textBold,
        overlayBackground: _textBg,
        trimStart: _trimActive
            ? Duration(milliseconds: (_trimStartSec * 1000).round())
            : Duration.zero,
        trimEnd: _trimActive && _trimEndSec < _durationSec - 0.05
            ? Duration(milliseconds: (_trimEndSec * 1000).round())
            : null,
        faceBake: (_faceKind != null && widget.faceTrack != null)
            ? FaceBakeData(kind: _faceKind!, track: widget.faceTrack!)
            : null,
      );

  bool get _hasEdits => _options.hasEdits;

  /// Picking a real colour filter clears the effect (an effect's
  /// baked graph replaces the filter chain, never combines with it).
  void _selectFilter(VideoFilter f) {
    setState(() {
      _filter = f;
      if (f.ffmpegFilter != null) _effect = VideoEffects.none;
    });
  }

  /// Picking an effect resets the colour filter for the same reason.
  void _selectEffect(VideoEffect fx) {
    setState(() {
      _effect = fx;
      if (fx.ffmpegGraph != null) _filter = VideoFilters.all.first;
    });
  }

  Future<void> _pickMusic() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      if (!mounted) return;
      setState(() {
        _musicPath = path;
        _musicName = path.split('/').last;
        _musicMode = MusicMode.replace;
        // A device file replaces any built-in sound attribution.
        _soundId = null;
        _soundSourceVideoId = null;
        _soundOwnerId = null;
      });
      _resolveMusicDuration();
    } catch (e) {
      debugPrint('pickMusic failed: $e');
      if (mounted) {
        setState(
            () => _error = 'Could not pick a music file. Please try again.');
      }
    }
  }

  /// Built-in sounds picker (item 6): attach one of the app's
  /// royalty-free tracks to a gallery clip (or a recorded one).
  /// The picked file is already downloaded/cached by the sheet.
  Future<void> _pickBuiltInSound() async {
    final choice = await showSoundsSheet(context, selectedId: _soundId);
    if (choice == null || !mounted) return;
    if (choice.cleared) {
      setState(() {
        _musicMode = MusicMode.original;
        _musicPath = null;
        _musicName = null;
        _soundId = null;
        _soundSourceVideoId = null;
        _soundOwnerId = null;
        _musicDurSec = 0;
        _musicStartSec = 0;
      });
      _player?.setVolume(1);
      return;
    }
    final pick = choice.pick!;
    setState(() {
      _musicMode = MusicMode.replace;
      _musicPath = pick.file.path;
      _musicName = pick.sound.name;
      _soundId = pick.sound.id;
      _soundSourceVideoId = null;
      _soundOwnerId = null;
    });
    _player?.setVolume(1);
    _resolveMusicDuration();
  }

  void _setMusicMode(MusicMode mode) {
    setState(() {
      _musicMode = mode;
      // Leaving replace mode drops the sound attribution.
      if (mode != MusicMode.replace) {
        _soundId = null;
        _soundSourceVideoId = null;
        _soundOwnerId = null;
      }
    });
    // Preview mirrors it: mute silences the preview, anything else
    // restores the original audio.
    _player?.setVolume(mode == MusicMode.mute ? 0 : 1);
  }

  Future<void> _post() async {
    if (AuthService.instance.uid == null) {
      setState(() => _error = 'Please log in first to post.');
      return;
    }
    final player = _player;
    if (player == null || _posting) return;
    // One background job at a time: if the previous post is still
    // preparing or uploading, say so now instead of starting a
    // second job that would have nowhere to go.
    if (UploadManagerService.instance.isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Upload already in progress — please wait for it to finish.'),
        ),
      );
      return;
    }

    setState(() {
      _posting = true;
      _error = null;
    });

    String? soundName;
    String? outSoundId;
    String? outSourceVideoId;
    String? outOwnerId;
    if (_musicMode == MusicMode.replace) {
      // Posting with picked music: name the sound after the
      // track. A built-in sound keeps its exact catalogue name
      // and stores its id for attribution (item 6); a reused
      // ORIGINAL sound keeps its stored display name
      // ('original sound — @<owner>') plus the source/owner
      // attribution (sound page round); a device file is
      // named after the file, as before.
      if (_soundId != null) {
        soundName = _musicName;
        outSoundId = _soundId;
      } else if (_soundSourceVideoId != null) {
        soundName = _musicName;
        outSourceVideoId = _soundSourceVideoId;
        outOwnerId = _soundOwnerId;
      } else {
        soundName = (_musicName ?? 'Music')
            .replaceAll(RegExp(r'\.[^.]+$'), '')
            .replaceAll('_', ' ');
      }
    }

    // Background handoff: the manager takes either the raw file
    // (no edits — uploaded as-is) or a bake recipe (edits chosen —
    // baked in the background first, then uploaded) plus the post
    // metadata, and the user lands straight on the home feed,
    // where the circular indicator counts the current stage's
    // percentage (TikTok style). Nothing blocks on this screen.
    final source = File(widget.videoPath);
    final started = UploadManagerService.instance.startJob(
      file: _hasEdits ? null : source,
      bakeRecipe: _hasEdits
          ? BakeRecipe(
              input: source,
              options: _options,
              videoDuration: player.value.duration,
              videoHeight: player.value.size.height.round(),
              videoWidth: player.value.size.width.round(),
            )
          : null,
      caption: _caption.text,
      soundName: soundName,
      soundId: outSoundId,
      soundSourceVideoId: outSourceVideoId,
      soundOwnerId: outOwnerId,
    );
    if (!started) {
      // An upload started elsewhere a moment ago — stay here so
      // the user can post again once it finishes.
      if (mounted) setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Upload already in progress — please wait for it to finish.'),
        ),
      );
      return;
    }
    widget.onPosted?.call();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  static String _fmt(double secs) {
    final s = secs.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Edit video'),
        actions: [
          TextButton(
            onPressed: _posting ? null : _post,
            child: Text('Post',
                style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _preview(player),
                const SizedBox(height: 16),
                if (_durationSec > 2) ...[
                  _sectionLabel('Trim'),
                  const SizedBox(height: 4),
                  _trimRow(),
                  const SizedBox(height: 8),
                ],
                _sectionLabel('Crop'),
                const SizedBox(height: 8),
                _cropRow(),
                const SizedBox(height: 16),
                _sectionLabel('Filters'),
                const SizedBox(height: 8),
                _filtersRow(),
                const SizedBox(height: 16),
                _sectionLabel('Effects'),
                const SizedBox(height: 2),
                Text(
                    'Grade effects preview live; the rest are applied '
                    'exactly when you post.',
                    style: TextStyle(color: AppTheme.mutedDark, fontSize: 12)),
                const SizedBox(height: 8),
                _effectsRow(),
                if (widget.faceTrack != null) ...[
                  const SizedBox(height: 16),
                  _sectionLabel('Face effect'),
                  const SizedBox(height: 2),
                  Text(
                      'Tracked on your face while recording — the '
                      'sticker is baked into the video when you post.',
                      style: TextStyle(color: AppTheme.mutedDark, fontSize: 12)),
                  const SizedBox(height: 8),
                  _faceRow(),
                ],
                const SizedBox(height: 16),
                _sectionLabel('Music'),
                const SizedBox(height: 8),
                _musicRow(),
                if (_musicMode == MusicMode.replace &&
                    _musicName != null) ...[
                  const SizedBox(height: 6),
                  Text('Music: $_musicName',
                      style: TextStyle(
                          color: AppTheme.mutedDark, fontSize: 12)),
                ],
                if (_musicMode == MusicMode.replace &&
                    _maxMusicStart > 0.5) ...[
                  const SizedBox(height: 10),
                  _musicStartRow(),
                ],
                const SizedBox(height: 16),
                _sectionLabel('Text on video'),
                const SizedBox(height: 8),
                TextField(
                  controller: _overlay,
                  maxLength: 60,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Add text (optional)',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                _positionRow(),
                const SizedBox(height: 10),
                _textColorRow(),
                const SizedBox(height: 10),
                _textStyleRow(),
                const SizedBox(height: 16),
                _sectionLabel('Caption'),
                const SizedBox(height: 8),
                TextField(
                  controller: _caption,
                  maxLines: 3,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    hintText: 'Write a caption… #hashtags welcome',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFFFF5C7A), fontSize: 13)),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _posting ? null : _post,
                  icon: const Icon(Icons.upload),
                  label: const Text('Post video'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
      );

  Widget _trimRow() {
    final dur = _durationSec;
    return Column(
      children: [
        RangeSlider(
          values: RangeValues(_trimStartSec, _trimEndSec),
          min: 0,
          max: dur,
          activeColor: AppTheme.accent,
          inactiveColor: Colors.white24,
          onChanged: _posting
              ? null
              : (v) {
                  var start = v.start;
                  var end = v.end;
                  // Keep at least 1 second between the handles.
                  if (end - start < 1) {
                    if (start == _trimStartSec) {
                      end = start + 1;
                    } else {
                      start = end - 1;
                    }
                  }
                  setState(() {
                    _trimStartSec = start.clamp(0, dur);
                    _trimEndSec = end.clamp(0, dur);
                  });
                },
          onChangeEnd: (_) {
            // Preview the kept segment from its start.
            _player?.seekTo(
                Duration(milliseconds: (_trimStartSec * 1000).round()));
            _player?.play();
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Start ${_fmt(_trimStartSec)}',
                style: TextStyle(
                    color: AppTheme.mutedDark, fontSize: 12.5)),
            Text(
              _trimActive
                  ? 'Keeping ${_fmt(_trimEndSec - _trimStartSec)} of ${_fmt(dur)}'
                  : 'Full length ${_fmt(dur)}',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
            ),
            Text('End ${_fmt(_trimEndSec)}',
                style: TextStyle(
                    color: AppTheme.mutedDark, fontSize: 12.5)),
          ],
        ),
      ],
    );
  }

  Widget _preview(VideoPlayerController? player) {
    Widget video;
    if (player == null || !player.value.isInitialized) {
      video = const Center(child: CircularProgressIndicator());
    } else {
      Widget inner = VideoPlayer(player);
      // A selected effect's grade replaces the filter preview;
      // structural effects have no honest matrix and show the
      // video unchanged — the baked result appears on post.
      final matrix = _effect.ffmpegGraph != null
          ? _effect.previewMatrix
          : _filter.previewMatrix;
      if (matrix != null) {
        inner = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: inner,
        );
      }
      final cropTarget = switch (_crop) {
        VideoCropAspect.portrait => 9 / 16,
        VideoCropAspect.square => 1.0,
        VideoCropAspect.landscape => 16 / 9,
        VideoCropAspect.original => null,
      };
      if (cropTarget == null) {
        video = AspectRatio(
          aspectRatio: player.value.aspectRatio,
          child: inner,
        );
      } else {
        // Approximate the baked centre-crop: the frame fills the
        // target aspect and the overflow is clipped, exactly the
        // region the crop filter keeps.
        video = AspectRatio(
          aspectRatio: cropTarget,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: 360,
                height: 360 / player.value.aspectRatio,
                child: inner,
              ),
            ),
          ),
        );
      }
    }
    final text = _overlay.text.trim();
    return GestureDetector(
      onTap: () {
        final p = _player;
        if (p == null) return;
        p.value.isPlaying ? p.pause() : p.play();
        setState(() {});
      },
      child: Container(
        height: 300,
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: video),
            if (player != null &&
                player.value.isInitialized &&
                _effect.name == 'Cinematic')
              const Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      heightFactor: 1 / 13,
                      widthFactor: 1,
                      child: ColoredBox(color: Colors.black),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: 1 / 13,
                      widthFactor: 1,
                      child: ColoredBox(color: Colors.black),
                    ),
                  ),
                ],
              ),
            if (player != null &&
                player.value.isInitialized &&
                _effect.name == 'Frame')
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 14),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black38, width: 3),
                  ),
                ),
              ),
            if (text.isNotEmpty)
              Align(
                alignment: switch (_textPos) {
                  OverlayPosition.top => const Alignment(0, -0.82),
                  OverlayPosition.center => Alignment.center,
                  OverlayPosition.bottom => const Alignment(0, 0.82),
                },
                child: Container(
                  padding: _textBg
                      ? const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5)
                      : EdgeInsets.zero,
                  decoration: _textBg
                      ? BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(6),
                        )
                      : null,
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          OverlayTextColors.byDrawtext(_textColor).swatch,
                      fontSize: 22 * _textScale,
                      fontWeight:
                          _textBold ? FontWeight.w800 : FontWeight.w500,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4),
                        Shadow(
                            color: Colors.black,
                            offset: Offset(1.5, 1.5),
                            blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filtersRow() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: VideoFilters.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = VideoFilters.all[i];
          final selected = f.name == _filter.name;
          return ChoiceChip(
            label: Text(f.name),
            selected: selected,
            onSelected: _posting ? null : (_) => _selectFilter(f),
            selectedColor: AppTheme.accent,
            backgroundColor: AppTheme.cardDark,
            labelStyle: TextStyle(
                color: selected ? Colors.white : AppTheme.mutedDark,
                fontWeight: FontWeight.w600),
            side: BorderSide.none,
          );
        },
      ),
    );
  }

  /// TikTok-panel style tiles: rounded square, emoji glyph, name
  /// underneath, cyan highlight when selected. Single-select.
  Widget _effectsRow() {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: VideoEffects.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final fx = VideoEffects.all[i];
          final selected = fx.name == _effect.name;
          return GestureDetector(
            onTap: _posting ? null : () => _selectEffect(fx),
            child: SizedBox(
              width: 62,
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? AppTheme.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(fx.emoji,
                          style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fx.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: selected ? Colors.white : AppTheme.mutedDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Face sticker picker (camera upgrade round): switch the
  /// recorded sticker or drop it. Only shown when the clip
  /// carries a real face track from the record screen.
  Widget _faceRow() {
    Widget tile({
      required String emoji,
      required String name,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: _posting ? null : onTap,
        child: SizedBox(
          width: 62,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        selected ? AppTheme.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: selected ? Colors.white : AppTheme.mutedDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          tile(
            emoji: '🚫',
            name: 'None',
            selected: _faceKind == null,
            onTap: () => setState(() => _faceKind = null),
          ),
          const SizedBox(width: 10),
          for (final s in FaceStickers.all) ...[
            tile(
              emoji: s.emoji,
              name: s.name,
              selected: _faceKind == s.kind,
              onTap: () => setState(() => _faceKind = s.kind),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _musicRow() {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Original sound'),
          selected: _musicMode == MusicMode.original,
          onSelected:
              _posting ? null : (_) => _setMusicMode(MusicMode.original),
          selectedColor: AppTheme.accent,
          backgroundColor: AppTheme.cardDark,
          labelStyle: TextStyle(
              color: _musicMode == MusicMode.original
                  ? Colors.white
                  : AppTheme.mutedDark,
              fontWeight: FontWeight.w600),
          side: BorderSide.none,
        ),
        ChoiceChip(
          label: const Text('Mute'),
          selected: _musicMode == MusicMode.mute,
          onSelected: _posting
              ? null
              : (_) => _setMusicMode(MusicMode.mute),
          selectedColor: AppTheme.accent,
          backgroundColor: AppTheme.cardDark,
          labelStyle: TextStyle(
              color: _musicMode == MusicMode.mute
                  ? Colors.white
                  : AppTheme.mutedDark,
              fontWeight: FontWeight.w600),
          side: BorderSide.none,
        ),
        ActionChip(
          avatar: const Icon(Icons.trending_up,
              size: 18, color: Colors.white70),
          label: const Text('Sounds'),
          onPressed: _posting ? null : _pickBuiltInSound,
          backgroundColor:
              _musicMode == MusicMode.replace && _soundId != null
                  ? AppTheme.accent
                  : AppTheme.cardDark,
          labelStyle: TextStyle(
              color: _musicMode == MusicMode.replace && _soundId != null
                  ? Colors.white
                  : AppTheme.mutedDark,
              fontWeight: FontWeight.w600),
          side: BorderSide.none,
        ),
        ActionChip(
          avatar: const Icon(Icons.library_music_outlined,
              size: 18, color: Colors.white70),
          label: Text(_musicPath == null ? 'Pick music' : 'Change music'),
          onPressed: _posting ? null : _pickMusic,
          backgroundColor: _musicMode == MusicMode.replace
              ? AppTheme.accent
              : AppTheme.cardDark,
          labelStyle: TextStyle(
              color: _musicMode == MusicMode.replace
                  ? Colors.white
                  : AppTheme.mutedDark,
              fontWeight: FontWeight.w600),
          side: BorderSide.none,
        ),
      ],
    );
  }

  Widget _positionRow() {
    return Row(
      children: [
        Text('Position:',
            style: TextStyle(color: AppTheme.mutedDark, fontSize: 13)),
        const SizedBox(width: 10),
        ...OverlayPosition.values.map((pos) {
          final selected = pos == _textPos;
          final label = switch (pos) {
            OverlayPosition.top => 'Top',
            OverlayPosition.center => 'Center',
            OverlayPosition.bottom => 'Bottom',
          };
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected:
                  _posting ? null : (_) => setState(() => _textPos = pos),
              selectedColor: AppTheme.accent,
              backgroundColor: AppTheme.cardDark,
              labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.mutedDark,
                  fontWeight: FontWeight.w600),
              side: BorderSide.none,
            ),
          );
        }),
      ],
    );
  }

  /// Frame-shape chips (editor round 2): the bake centre-crops
  /// the clip to the chosen aspect; Original keeps the source.
  Widget _cropRow() {
    const choices = <(VideoCropAspect, String)>[
      (VideoCropAspect.original, 'Original'),
      (VideoCropAspect.portrait, '9:16'),
      (VideoCropAspect.square, '1:1'),
      (VideoCropAspect.landscape, '16:9'),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final (aspect, label) in choices)
          ChoiceChip(
            label: Text(label),
            selected: _crop == aspect,
            onSelected:
                _posting ? null : (_) => setState(() => _crop = aspect),
            selectedColor: AppTheme.accent,
            backgroundColor: AppTheme.cardDark,
            labelStyle: TextStyle(
                color: _crop == aspect ? Colors.white : AppTheme.mutedDark,
                fontWeight: FontWeight.w600),
            side: BorderSide.none,
          ),
      ],
    );
  }

  /// Song-start slider (editor round 2): drag to choose which
  /// part of the attached track plays. Only shown when the track
  /// is longer than the kept clip, so a start range exists.
  Widget _musicStartRow() {
    final maxStart = _maxMusicStart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Song starts at',
                style: TextStyle(
                    color: AppTheme.mutedDark, fontSize: 12.5)),
            Text(
              '${_fmt(_musicStartSec)} of ${_fmt(_musicDurSec)}',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Slider(
          value: _musicStartSec.clamp(0, maxStart).toDouble(),
          min: 0,
          max: maxStart,
          activeColor: AppTheme.accent,
          inactiveColor: Colors.white24,
          onChanged: _posting
              ? null
              : (v) => setState(() => _musicStartSec = v),
        ),
      ],
    );
  }

  /// Text colour swatches (editor round 2).
  Widget _textColorRow() {
    return Row(
      children: [
        Text('Color:',
            style: TextStyle(color: AppTheme.mutedDark, fontSize: 13)),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              for (final c in OverlayTextColors.all)
                GestureDetector(
                  onTap: _posting
                      ? null
                      : () => setState(() => _textColor = c.drawtext),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _textColor == c.drawtext
                            ? AppTheme.accent
                            : Colors.white24,
                        width: _textColor == c.drawtext ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Text size + Bold + Background controls (editor round 2).
  Widget _textStyleRow() {
    Widget toggleChip(String label, bool value, ValueChanged<bool> set) {
      return ChoiceChip(
        label: Text(label),
        selected: value,
        onSelected: _posting ? null : (v) => setState(() => set(v)),
        selectedColor: AppTheme.accent,
        backgroundColor: AppTheme.cardDark,
        labelStyle: TextStyle(
            color: value ? Colors.white : AppTheme.mutedDark,
            fontWeight: FontWeight.w600),
        side: BorderSide.none,
      );
    }

    return Wrap(
      spacing: 8,
      children: [
        for (final (label, scale) in const [
          ('Small', 0.7),
          ('Medium', 1.0),
          ('Large', 1.4),
        ])
          ChoiceChip(
            label: Text(label),
            selected: _textScale == scale,
            onSelected:
                _posting ? null : (_) => setState(() => _textScale = scale),
            selectedColor: AppTheme.accent,
            backgroundColor: AppTheme.cardDark,
            labelStyle: TextStyle(
                color:
                    _textScale == scale ? Colors.white : AppTheme.mutedDark,
                fontWeight: FontWeight.w600),
            side: BorderSide.none,
          ),
        toggleChip('Bold', _textBold, (v) => _textBold = v),
        toggleChip('Background', _textBg, (v) => _textBg = v),
      ],
    );
  }
}
