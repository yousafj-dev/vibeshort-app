import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/screens/create/edit_video_screen.dart';
import 'package:vibeshort/services/sounds_service.dart';
import 'package:vibeshort/services/video_edit_service.dart';
import 'package:vibeshort/widgets/sounds_sheet.dart';

/// In-app camera recorder (Editing phase + fix round): FULL-SCREEN
/// live preview (cover fit, portrait) with a TikTok-style layout:
///
///  * Bottom LIVE LOOKS carousel (item 1): 30 rich looks — colour
///    filters plus the grade effects that carry a preview matrix —
///    each a circular thumbnail tinted by its own matrix; tapping
///    one changes the live preview immediately, and the exact same
///    FFmpeg chain is baked in at post time.
///  * A second strip keeps the structural effects (Mirror, Glitch…)
///    which cannot render on a live camera feed — the honest
///    "applied when you post" note stays, and FFmpeg bakes them.
///  * Right-side vertical tools column: Flip, Flash (torch), Timer
///    (3s / 10s countdown), Effects shortcut. Front/back switching
///    ALSO works by double-tapping the preview.
///  * Duration chips: 15s / 60s, auto-stop at the limit.
///  * "Add sound" pill (item 6): pick a built-in royalty-free
///    track BEFORE recording; it plays while you record and is
///    mixed into the posted video automatically.
class CameraRecordScreen extends StatefulWidget {
  /// Called after a successful post (shell switches to Home).
  final VoidCallback? onPosted;

  /// A sound preselected before this screen opened (sound page
  /// round): "Use this sound" on a sound page — a library track
  /// or another video's original sound, already downloaded.
  /// It starts attached, plays during recording and is mixed
  /// in at post time, like a sound picked on this screen.
  final PreselectedSound? initialSound;

  const CameraRecordScreen({super.key, this.onPosted, this.initialSound});

  @override
  State<CameraRecordScreen> createState() => _CameraRecordScreenState();
}

enum _Strip { looks, effects }

class _CameraRecordScreenState extends State<CameraRecordScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _recording = false;
  int _elapsed = 0;
  Timer? _timer;
  String? _error;

  /// Chosen recording length (item 1): 15s or 60s, TikTok-style.
  int _durationLimit = 60;

  /// Self-timer: 0 = off, otherwise 3 or 10 seconds. While the
  /// countdown runs, [_countdown] holds the number on screen.
  int _timerDelay = 0;
  int? _countdown;
  Timer? _countTimer;

  bool _flashOn = false;

  /// Live look selected from the carousel. [_filter] / [_effect]
  /// stay in sync with it (they are what the edit screen receives);
  /// selecting a structural effect resets the look to Normal.
  LiveLook _look = LiveLooks.all.first;
  VideoFilter _filter = VideoFilters.all.first;
  VideoEffect _effect = VideoEffects.none;
  _Strip _strip = _Strip.looks;

  /// Sound attached before recording (item 6 + sound page
  /// round). The player performs the track during recording; the
  /// edit screen mixes the same cached file into the posted
  /// video. [_soundId] is set only for built-in library sounds;
  /// an ORIGINAL sound reused via "Use this sound" instead
  /// carries [_soundSourceVideoId] / [_soundOwnerId] attribution
  /// and a display name of 'original sound — @<owner>'.
  String? _soundId;
  String? _soundDisplayName;
  String? _soundSourceVideoId;
  String? _soundOwnerId;
  File? _soundFile;
  VideoPlayerController? _soundPlayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
    final pre = widget.initialSound;
    if (pre != null) _applyPreselectedSound(pre);
  }

  /// Attaches a sound handed in from a sound page ("Use this
  /// sound"): same state as an in-screen pick, plus the
  /// original-sound attribution fields when it has them.
  Future<void> _applyPreselectedSound(PreselectedSound pre) async {
    final file = File(pre.filePath);
    if (!await file.exists()) return;
    final player = VideoPlayerController.file(file);
    try {
      await player.initialize();
      await player.setLooping(true);
    } catch (e) {
      debugPrint('preselected sound init failed: $e');
      await player.dispose();
      return;
    }
    if (!mounted) {
      player.dispose();
      return;
    }
    setState(() {
      _soundId = pre.soundId;
      _soundDisplayName = pre.displayName;
      _soundSourceVideoId = pre.sourceVideoId;
      _soundOwnerId = pre.ownerId;
      _soundFile = file;
      _soundPlayer = player;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _countTimer?.cancel();
    _controller?.dispose();
    _soundPlayer?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_cameraIndex);
    }
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initializing = false;
            _error = 'No camera was found on this device.';
          });
        }
        return;
      }
      // Start with the back camera when there is one.
      final back = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = back >= 0 ? back : 0;
      await _initCamera(_cameraIndex);
    } catch (e) {
      debugPrint('camera setup failed: $e');
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Camera is not available. Please check permissions.';
        });
      }
    }
  }

  Future<void> _initCamera(int index) async {
    final old = _controller;
    _controller = null;
    await old?.dispose();
    final c = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
    );
    try {
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _initializing = false;
        // A fresh controller starts with the torch off; the front
        // camera has no torch at all.
        _flashOn = false;
      });
    } on CameraException catch (e) {
      debugPrint('camera init failed: ${e.code}');
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = e.code == 'CameraAccessDenied'
              ? 'Camera permission was denied. Please allow it in Settings.'
              : 'Camera could not start. Please try again.';
        });
      }
    }
  }

  bool get _isBackCamera =>
      _cameras.isNotEmpty &&
      _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;

  Future<void> _flip() async {
    if (_recording || _cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _initializing = true);
    await _initCamera(_cameraIndex);
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (!_isBackCamera) {
      _showError('Flash is only available on the back camera.');
      return;
    }
    try {
      final next = !_flashOn;
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _flashOn = next);
    } catch (e) {
      debugPrint('flash toggle failed: $e');
      _showError('Flash is not available on this camera.');
    }
  }

  void _cycleTimer() {
    if (_recording) return;
    setState(() {
      _timerDelay = _timerDelay == 0 ? 3 : (_timerDelay == 3 ? 10 : 0);
    });
  }

  void _selectLook(LiveLook look) {
    setState(() {
      _look = look;
      _filter = look.filter ?? VideoFilters.all.first;
      _effect = look.effect ?? VideoEffects.none;
    });
  }

  void _selectEffect(VideoEffect fx) {
    setState(() {
      _effect = fx;
      if (fx.ffmpegGraph != null) {
        _filter = VideoFilters.all.first;
        _look = LiveLooks.all.first;
      }
    });
  }

  // ---------------------------------------------------------------
  // Built-in sound (item 6)
  // ---------------------------------------------------------------

  Future<void> _pickSound() async {
    if (_recording) return;
    final choice =
        await showSoundsSheet(context, selectedId: _soundId);
    if (choice == null || !mounted) return;
    if (choice.cleared) {
      await _soundPlayer?.dispose();
      setState(() {
        _soundId = null;
        _soundDisplayName = null;
        _soundSourceVideoId = null;
        _soundOwnerId = null;
        _soundFile = null;
        _soundPlayer = null;
      });
      return;
    }
    final pick = choice.pick!;
    final player = VideoPlayerController.file(pick.file);
    try {
      await player.initialize();
      await player.setLooping(true);
    } catch (e) {
      debugPrint('sound player init failed: $e');
      _showError('That sound could not be played. Please try another.');
      await player.dispose();
      return;
    }
    await _soundPlayer?.dispose();
    if (!mounted) {
      player.dispose();
      return;
    }
    setState(() {
      _soundId = pick.sound.id;
      _soundDisplayName = pick.sound.name;
      _soundSourceVideoId = null;
      _soundOwnerId = null;
      _soundFile = pick.file;
      _soundPlayer = player;
    });
  }

  Future<void> _clearSound() async {
    await _soundPlayer?.dispose();
    if (!mounted) return;
    setState(() {
      _soundId = null;
      _soundDisplayName = null;
      _soundSourceVideoId = null;
      _soundOwnerId = null;
      _soundFile = null;
      _soundPlayer = null;
    });
  }

  // ---------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------

  Future<void> _toggleRecord() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_countdown != null) {
      // A tap during the countdown cancels it.
      _countTimer?.cancel();
      setState(() => _countdown = null);
      return;
    }
    if (_recording) {
      await _stop();
      return;
    }
    if (_timerDelay > 0) {
      setState(() => _countdown = _timerDelay);
      _countTimer?.cancel();
      _countTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        final left = (_countdown ?? 1) - 1;
        if (left <= 0) {
          t.cancel();
          setState(() => _countdown = null);
          _startRecording();
        } else {
          setState(() => _countdown = left);
        }
      });
      return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _recording) return;
    try {
      await c.startVideoRecording();
      // The picked sound performs along with the recording.
      final sp = _soundPlayer;
      if (sp != null) {
        await sp.seekTo(Duration.zero);
        await sp.play();
      }
      _timer?.cancel();
      _elapsed = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed++);
        if (_elapsed >= _durationLimit) _stop();
      });
      setState(() => _recording = true);
    } on CameraException catch (e) {
      debugPrint('start recording failed: ${e.code}');
      _showError('Recording could not start. Please try again.');
    }
  }

  Future<void> _stop() async {
    final c = _controller;
    if (c == null || !_recording) return;
    _timer?.cancel();
    setState(() => _recording = false);
    await _soundPlayer?.pause();
    try {
      final file = await c.stopVideoRecording();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EditVideoScreen(
            videoPath: file.path,
            initialFilterName: _filter.name,
            initialEffectName: _effect.name,
            initialSoundId: _soundId,
            initialSoundName: _soundDisplayName,
            initialSoundPath: _soundFile?.path,
            initialSoundSourceVideoId: _soundSourceVideoId,
            initialSoundOwnerId: _soundOwnerId,
            onPosted: widget.onPosted,
          ),
        ),
      );
    } on CameraException catch (e) {
      debugPrint('stop recording failed: ${e.code}');
      _showError('The recording could not be saved. Please try again.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _timeLabel {
    final m = (_elapsed ~/ 60).toString();
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    final total = _durationLimit == 60 ? '1:00' : '0:15';
    return '$m:$s / $total';
  }

  /// True when the selected effect has neither a live matrix nor an
  /// overlay treatment — the preview honestly cannot show it.
  bool get _effectNotPreviewable =>
      _effect.ffmpegGraph != null &&
      _effect.previewMatrix == null &&
      _effect.name != 'Frame';

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Record'),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                if (_initializing || c == null)
                  const Center(child: CircularProgressIndicator())
                else
                  // Double-tap switches front/back camera (item 1).
                  GestureDetector(
                    onDoubleTap: _flip,
                    child: _livePreview(c),
                  ),
                // Elapsed / limit chip
                Positioned(
                  top: MediaQuery.of(context).padding.top + 64,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_recording)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.circle,
                                  color: Colors.redAccent, size: 10),
                            ),
                          Text(_timeLabel,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                // Add-sound pill (item 6)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 108,
                  left: 0,
                  right: 0,
                  child: Center(child: _soundPill()),
                ),
                // Right-side tools column (item 1)
                Positioned(
                  right: 8,
                  top: MediaQuery.of(context).padding.top + 170,
                  child: _toolsColumn(),
                ),
                // Self-timer countdown
                if (_countdown != null)
                  Center(
                    child: Text(
                      '$_countdown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 110,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 18),
                        ],
                      ),
                    ),
                  ),
                // Bottom controls
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_effectNotPreviewable)
                        // Layout fix (sound page round): the notice
                        // is a compact pill in the normal column
                        // flow ABOVE the duration chips — in-flow,
                        // so it pushes the chips down instead of
                        // rendering over them — and its wide side
                        // margins keep it clear of the right-side
                        // tools column at every screen height.
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: 8, left: 64, right: 64),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '${_effect.name} is applied when you post — '
                              'it can\'t be previewed live.',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      _durationChips(),
                      const SizedBox(height: 10),
                      _stripToggle(),
                      const SizedBox(height: 10),
                      _strip == _Strip.looks ? _looksRow() : _effectsRow(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(width: 56),
                          GestureDetector(
                            onTap: _toggleRecord,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 4),
                              ),
                              child: Center(
                                child: Container(
                                  width: _recording ? 30 : 58,
                                  height: _recording ? 30 : 58,
                                  decoration: _recording
                                      ? BoxDecoration(
                                          color: AppTheme.accent2,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        )
                                      : const BoxDecoration(
                                          gradient:
                                              AppTheme.primaryGradient,
                                          shape: BoxShape.circle,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 56),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// The Add-sound pill: shows the picked track (with a clear
  /// button) or invites a pick. Hidden while recording.
  Widget _soundPill() {
    if (_recording) return const SizedBox.shrink();
    final soundName = _soundDisplayName;
    return Container(
      padding: EdgeInsets.only(
          left: 12, right: soundName == null ? 14 : 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _pickSound,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.music_note,
                    color: Colors.white, size: 17),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(
                    soundName ?? 'Add sound',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (soundName != null)
            IconButton(
              onPressed: _clearSound,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: Colors.white70, size: 17),
            ),
        ],
      ),
    );
  }

  /// Right-side vertical tools column (item 1): Flip, Flash,
  /// Timer, Effects — the TikTok camera layout.
  Widget _toolsColumn() {
    Widget tool(IconData icon, String label, VoidCallback onTap,
        {bool active = false, bool dimmed = false}) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black38,
              ),
              child: Icon(
                icon,
                color: dimmed
                    ? Colors.white38
                    : (active ? AppTheme.accent : Colors.white),
                size: 23,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: dimmed ? Colors.white38 : Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 4),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tool(Icons.flip_camera_ios_outlined, 'Flip', _flip),
        const SizedBox(height: 16),
        tool(
          _flashOn ? Icons.flash_on : Icons.flash_off,
          'Flash',
          _toggleFlash,
          active: _flashOn,
          dimmed: !_isBackCamera,
        ),
        const SizedBox(height: 16),
        tool(
          Icons.timer_outlined,
          _timerDelay == 0 ? 'Timer' : '${_timerDelay}s',
          _cycleTimer,
          active: _timerDelay != 0,
        ),
        const SizedBox(height: 16),
        tool(Icons.auto_fix_high, 'Effects', () {
          if (_recording) return;
          setState(() => _strip = _Strip.effects);
        }, active: _strip == _Strip.effects),
      ],
    );
  }

  /// 15s / 60s duration chips (item 1).
  Widget _durationChips() {
    Widget chip(int seconds) {
      final selected = _durationLimit == seconds;
      return GestureDetector(
        onTap: _recording
            ? null
            : () => setState(() => _durationLimit = seconds),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.black45,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '${seconds}s',
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        chip(15),
        const SizedBox(width: 8),
        chip(60),
      ],
    );
  }

  /// The camera preview scaled to COVER the whole screen (the
  /// standard cover recipe for the camera plugin), wrapped in the
  /// selected look: a [ColorFilter] matrix for colour filters and
  /// grade effects, plus overlay widgets for the two effects whose
  /// baked look has a structural part a matrix can't express —
  /// Cinematic's letterbox bars and Frame's white border.
  Widget _livePreview(CameraController c) {
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * c.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    Widget preview = Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(c)),
    );
    final matrix = _effect.ffmpegGraph != null
        ? _effect.previewMatrix
        : _filter.previewMatrix;
    if (matrix != null) {
      preview = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: preview,
      );
    }
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          preview,
          if (_effect.name == 'Cinematic') ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: size.height / 13,
              child: Container(color: Colors.black),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: size.height / 13,
              child: Container(color: Colors.black),
            ),
          ],
          if (_effect.name == 'Frame')
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 14),
              ),
              child: Container(
                decoration: BoxDecoration(
                  border:
                      Border.all(color: Colors.black38, width: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stripToggle() {
    Widget tab(String label, _Strip value) {
      final selected = _strip == value;
      return GestureDetector(
        onTap: _recording ? null : () => setState(() => _strip = value),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : Colors.black45,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        tab('Looks', _Strip.looks),
        const SizedBox(width: 8),
        tab('Effects', _Strip.effects),
      ],
    );
  }

  /// LIVE looks carousel (item 1): circular thumbnails over a small
  /// multi-colour "scene" gradient, each tinted by the look's own
  /// matrix so the thumbnail itself previews the grade; grade
  /// effects carry their emoji badge, Cinematic gets mini
  /// letterbox bars. Tapping applies the look to the live preview.
  Widget _looksRow() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: LiveLooks.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final look = LiveLooks.all[i];
          final selected = look.name == _look.name;
          Widget swatch = Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF7ED6FF), // sky
                  Color(0xFF00C2FF), // cyan
                  Color(0xFFFFB340), // sun
                  Color(0xFFFF7A59), // warm ground
                ],
                stops: [0.0, 0.45, 0.72, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          );
          if (look.previewMatrix != null) {
            swatch = ColorFiltered(
              colorFilter: ColorFilter.matrix(look.previewMatrix!),
              child: swatch,
            );
          }
          return GestureDetector(
            onTap: _recording ? null : () => _selectLook(look),
            child: SizedBox(
              width: 56,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppTheme.accent
                            : Colors.white38,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          swatch,
                          if (look.letterbox) ...[
                            const Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 6,
                              child: ColoredBox(color: Colors.black),
                            ),
                            const Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              height: 6,
                              child: ColoredBox(color: Colors.black),
                            ),
                          ],
                          if (look.effect != null)
                            Positioned(
                              right: 1,
                              bottom: 1,
                              child: Text(look.emoji,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    look.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 3),
                      ],
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

  /// Effects strip: emoji tiles like the edit screen's panel.
  /// Grade effects tint the live preview through their matrix;
  /// structural ones show the honest note above the strip.
  Widget _effectsRow() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: VideoEffects.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final fx = VideoEffects.all[i];
          final selected = fx.name == _effect.name;
          return GestureDetector(
            onTap: _recording ? null : () => _selectEffect(fx),
            child: SizedBox(
              width: 54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? AppTheme.accent
                            : Colors.white38,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(fx.emoji,
                          style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fx.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 3),
                      ],
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
}
