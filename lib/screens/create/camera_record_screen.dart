import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/screens/create/edit_video_screen.dart';
import 'package:vibeshort/services/video_edit_service.dart';

/// In-app camera recorder (Editing phase): FULL-SCREEN live preview
/// (cover fit, portrait), front/back flip, elapsed timer, 60-second
/// max with auto-stop — and LIVE filters + effects over the preview.
///
/// Colour filters and grade effects preview in real time through a
/// [ColorFilter] matrix wrapped around the camera preview; Cinematic
/// also gets its letterbox bars and Frame its white border as overlay
/// widgets, so what you record over is the look that gets baked in.
/// Structural effects (Mirror, Glitch…) cannot be rendered live on a
/// camera feed — selecting one says so honestly on screen, and it is
/// applied for real by FFmpeg at post time. The chosen filter/effect
/// is carried into the edit screen pre-selected, and the raw
/// recording is baked with that exact chain before upload.
class CameraRecordScreen extends StatefulWidget {
  /// Called after a successful post (shell switches to Home).
  final VoidCallback? onPosted;

  const CameraRecordScreen({super.key, this.onPosted});

  @override
  State<CameraRecordScreen> createState() => _CameraRecordScreenState();
}

enum _Strip { filters, effects }

class _CameraRecordScreenState extends State<CameraRecordScreen>
    with WidgetsBindingObserver {
  static const _maxSeconds = 60;

  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _recording = false;
  int _elapsed = 0;
  Timer? _timer;
  String? _error;

  /// Live look selected on the record screen (Normal / None by
  /// default). Filter and effect are mutually exclusive — the baked
  /// chain uses one or the other, exactly like the edit screen.
  VideoFilter _filter = VideoFilters.all.first;
  VideoEffect _effect = VideoEffects.none;
  _Strip _strip = _Strip.filters;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
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

  Future<void> _flip() async {
    if (_recording || _cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _initializing = true);
    await _initCamera(_cameraIndex);
  }

  void _selectFilter(VideoFilter f) {
    setState(() {
      _filter = f;
      if (f.ffmpegFilter != null) _effect = VideoEffects.none;
    });
  }

  void _selectEffect(VideoEffect fx) {
    setState(() {
      _effect = fx;
      if (fx.ffmpegGraph != null) _filter = VideoFilters.all.first;
    });
  }

  Future<void> _toggleRecord() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_recording) {
      await _stop();
      return;
    }
    try {
      await c.startVideoRecording();
      _timer?.cancel();
      _elapsed = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed++);
        if (_elapsed >= _maxSeconds) _stop();
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
    try {
      final file = await c.stopVideoRecording();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EditVideoScreen(
            videoPath: file.path,
            initialFilterName: _filter.name,
            initialEffectName: _effect.name,
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
    return '$m:$s / 1:00';
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
                  _livePreview(c),
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
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_effectNotPreviewable)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${_effect.name} is applied when you post — '
                            'it can\'t be previewed live.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                              shadows: [
                                Shadow(
                                    color: Colors.black87, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      _stripToggle(),
                      const SizedBox(height: 10),
                      _strip == _Strip.filters
                          ? _filtersRow()
                          : _effectsRow(),
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
                          IconButton(
                            onPressed: _flip,
                            iconSize: 34,
                            icon: const Icon(
                                Icons.flip_camera_ios_outlined,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
        tab('Filters', _Strip.filters),
        const SizedBox(width: 8),
        tab('Effects', _Strip.effects),
      ],
    );
  }

  /// Filter strip: the same 20 colour filters as the edit screen.
  /// Each chip is a circular swatch (a cyan→violet→amber gradient
  /// tinted by the filter's own matrix) with the name under it;
  /// tapping one tints the live preview immediately.
  Widget _filtersRow() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: VideoFilters.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final f = VideoFilters.all[i];
          final selected = f.name == _filter.name;
          Widget swatch = Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF00C2FF),
                  Color(0xFF7C4DFF),
                  Color(0xFFFFB340),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );
          if (f.previewMatrix != null) {
            swatch = ColorFiltered(
              colorFilter: ColorFilter.matrix(f.previewMatrix!),
              child: swatch,
            );
          }
          return GestureDetector(
            onTap: _recording ? null : () => _selectFilter(f),
            child: SizedBox(
              width: 54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppTheme.accent
                            : Colors.white38,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipOval(child: swatch),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    f.name,
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
      height: 76,
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
