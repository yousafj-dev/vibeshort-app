import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/services/storage_service.dart';
import 'package:vibeshort/services/video_edit_service.dart';

/// Edit + post screen (Editing phase). Every video — recorded in
/// the in-app camera (with a filter/effect already chosen live) or
/// picked from the gallery — lands here before posting.
///
/// The preview applies the selected look live (a ColorFilter matrix
/// approximation for colour filters and grade effects), the trim
/// window loops in the preview, and the overlay text is drawn at its
/// chosen position. On post, FFmpeg bakes the exact filter/effect
/// chain, trim, music change and text into the uploaded video (see
/// [VideoEditService]). With no edits chosen the original file is
/// uploaded untouched.
class EditVideoScreen extends StatefulWidget {
  final String videoPath;

  /// Look chosen LIVE on the record screen — pre-selected here so
  /// the posted video gets exactly that baked in.
  final String? initialFilterName;
  final String? initialEffectName;

  /// Called after a successful post (shell switches to Home).
  final VoidCallback? onPosted;

  const EditVideoScreen({
    super.key,
    required this.videoPath,
    this.initialFilterName,
    this.initialEffectName,
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
  OverlayPosition _textPos = OverlayPosition.bottom;

  // Trim window in seconds (start 0, end = full duration = untrimmed).
  double _trimStartSec = 0;
  double _trimEndSec = 0;

  bool _posting = false;
  bool _processing = false;
  double _progress = 0;
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
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final c = VideoPlayerController.file(File(widget.videoPath));
    await c.initialize();
    await c.setLooping(true);
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
        overlayText: _overlay.text,
        overlayPosition: _textPos,
        trimStart: _trimActive
            ? Duration(milliseconds: (_trimStartSec * 1000).round())
            : Duration.zero,
        trimEnd: _trimActive && _trimEndSec < _durationSec - 0.05
            ? Duration(milliseconds: (_trimEndSec * 1000).round())
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
      });
    } catch (e) {
      debugPrint('pickMusic failed: $e');
      if (mounted) {
        setState(
            () => _error = 'Could not pick a music file. Please try again.');
      }
    }
  }

  void _setMusicMode(MusicMode mode) {
    setState(() => _musicMode = mode);
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

    setState(() {
      _posting = true;
      _processing = _hasEdits;
      _progress = 0;
      _error = null;
    });

    File toUpload = File(widget.videoPath);
    try {
      if (_hasEdits) {
        toUpload = await VideoEditService.instance.processVideo(
          input: toUpload,
          options: _options,
          videoDuration: player.value.duration,
          videoHeight: player.value.size.height.round(),
        );
      }
    } catch (e) {
      // Processing failed: do NOT silently upload the unedited file.
      if (!mounted) return;
      setState(() {
        _posting = false;
        _processing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      return;
    }

    if (!mounted) return;
    setState(() => _processing = false);
    try {
      final url = await StorageService.instance.uploadVideo(
        toUpload,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      String? soundName;
      if (_musicMode == MusicMode.replace) {
        // Posting with picked music: name the sound after the track.
        soundName = (_musicName ?? 'Music')
            .replaceAll(RegExp(r'\.[^.]+$'), '')
            .replaceAll('_', ' ');
      }
      await FirestoreService.instance.addVideo(
        videoUrl: url,
        caption: _caption.text,
        soundName: soundName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your video is live!')),
      );
      widget.onPosted?.call();
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  static String _fmt(double secs) {
    final s = secs.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Edit video'),
        actions: [
          TextButton(
            onPressed: _posting ? null : _post,
            child: const Text('Post',
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
                _sectionLabel('Filters'),
                const SizedBox(height: 8),
                _filtersRow(),
                const SizedBox(height: 16),
                _sectionLabel('Effects'),
                const SizedBox(height: 2),
                const Text(
                    'Grade effects preview live; the rest are applied '
                    'exactly when you post.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                const SizedBox(height: 8),
                _effectsRow(),
                const SizedBox(height: 16),
                _sectionLabel('Music'),
                const SizedBox(height: 8),
                _musicRow(),
                if (_musicMode == MusicMode.replace &&
                    _musicName != null) ...[
                  const SizedBox(height: 6),
                  Text('Music: $_musicName',
                      style: const TextStyle(
                          color: AppTheme.muted, fontSize: 12)),
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
                if (_posting && !_processing) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: AppTheme.card,
                    color: AppTheme.accent,
                    minHeight: 8,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Uploading… ${(_progress * 100).round()}%',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
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
          if (_processing)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.accent),
                    SizedBox(height: 16),
                    Text('Processing…',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 6),
                    Text('Applying your edits to the video',
                        style:
                            TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ),
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
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 12.5)),
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
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 12.5)),
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
      video = AspectRatio(
        aspectRatio: player.value.aspectRatio,
        child: inner,
      );
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
          color: AppTheme.card,
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
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 4),
                      Shadow(
                          color: Colors.black,
                          offset: Offset(1.5, 1.5),
                          blurRadius: 2),
                    ],
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
            backgroundColor: AppTheme.card,
            labelStyle: TextStyle(
                color: selected ? Colors.white : AppTheme.muted,
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
                      color: AppTheme.card,
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
                      color: selected ? Colors.white : AppTheme.muted,
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
          backgroundColor: AppTheme.card,
          labelStyle: TextStyle(
              color: _musicMode == MusicMode.original
                  ? Colors.white
                  : AppTheme.muted,
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
          backgroundColor: AppTheme.card,
          labelStyle: TextStyle(
              color: _musicMode == MusicMode.mute
                  ? Colors.white
                  : AppTheme.muted,
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
              : AppTheme.card,
          labelStyle: TextStyle(
              color: _musicMode == MusicMode.replace
                  ? Colors.white
                  : AppTheme.muted,
              fontWeight: FontWeight.w600),
          side: BorderSide.none,
        ),
      ],
    );
  }

  Widget _positionRow() {
    return Row(
      children: [
        const Text('Position:',
            style: TextStyle(color: AppTheme.muted, fontSize: 13)),
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
              backgroundColor: AppTheme.card,
              labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.muted,
                  fontWeight: FontWeight.w600),
              side: BorderSide.none,
            ),
          );
        }),
      ],
    );
  }
}
