import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:video_player/video_player.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/screens/create/edit_video_screen.dart';
import 'package:vibeshort/services/face_effects.dart';
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
///  * Camera upgrade round: pinch-to-zoom + - / + steppers by
///    the record button (zoom applies live, also mid-recording),
///    and a Face strip with REAL ML Kit face-tracking stickers —
///    drawn live over the face, logged while recording, and
///    baked into the posted video by the edit screen's FFmpeg
///    pass. The preview stack (filter matrix + overlays) is never
///    torn down when recording starts, so the chosen look stays
///    visible for the whole recording.
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

enum _Strip { looks, effects, face }

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

  // -------------------------------------------------------------
  // Camera upgrade round: zoom + face effects
  // -------------------------------------------------------------

  /// Zoom state (item 1): bounds come from the device camera;
  /// [_zoom] is applied LIVE via setZoomLevel, so pinch and the
  /// +/- steppers work while recording too.
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;
  double? _pendingZoom;
  bool _zoomInFlight = false;
  bool _zoomLabelVisible = false;
  Timer? _zoomLabelTimer;

  /// Selected face sticker (item 3); null = no face effect.
  FaceStickerKind? _faceKind;

  /// On-device ML Kit detector (free, no API key, nothing leaves
  /// the phone). Landmarks on for the eye-anchored stickers.
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableTracking: true,
      minFaceSize: 0.12,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  bool _streaming = false;
  bool _detectBusy = false;
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);

  /// Latest detected faces (upright image coordinates) for the
  /// live overlay, plus the upright size of the analysed frames.
  List<FaceGeometry> _faceGeo = [];
  Size? _uprightSize;

  /// Face positions logged while recording (the bake's source).
  final Stopwatch _recWatch = Stopwatch();
  List<FaceTrackSample> _track = [];

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
    _zoomLabelTimer?.cancel();
    _stopFaceStream();
    _faceDetector.close();
    _controller?.dispose();
    _soundPlayer?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      // The image stream dies with the controller.
      _streaming = false;
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
      // Zoom bounds are per-camera (item 1).
      try {
        _minZoom = await c.getMinZoomLevel();
        _maxZoom = await c.getMaxZoomLevel();
      } catch (e) {
        debugPrint('zoom bounds failed: $e');
        _minZoom = 1.0;
        _maxZoom = 1.0;
      }
      _zoom = 1.0.clamp(_minZoom, _maxZoom).toDouble();
      // A face sticker survives camera (re)starts: rebind the
      // detection stream to the fresh controller.
      if (_faceKind != null && _controller == c) {
        _startFaceStream();
      }
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
    await _stopFaceStream();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() {
      _initializing = true;
      _faceGeo = [];
    });
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
  // Zoom (camera upgrade round, item 1)
  // ---------------------------------------------------------------

  /// Applies a zoom level, clamped to what THIS camera reports.
  /// Calls are coalesced: pinch gestures fire faster than the
  /// platform channel answers, so only the latest value matters.
  /// Works mid-recording — CameraX applies zoom to the live
  /// preview and the recording alike.
  Future<void> _setZoom(double z) async {
    _pendingZoom = z.clamp(_minZoom, _maxZoom).toDouble();
    if (_zoomInFlight) return;
    _zoomInFlight = true;
    while (_pendingZoom != null) {
      final target = _pendingZoom!;
      _pendingZoom = null;
      final c = _controller;
      if (c == null || !c.value.isInitialized) break;
      try {
        await c.setZoomLevel(target);
      } catch (e) {
        debugPrint('setZoomLevel failed: $e');
        break;
      }
      if (!mounted) break;
      setState(() {
        _zoom = target;
        _zoomLabelVisible = true;
      });
      _zoomLabelTimer?.cancel();
      _zoomLabelTimer =
          Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _zoomLabelVisible = false);
      });
    }
    _zoomInFlight = false;
  }

  void _stepZoom(double delta) => _setZoom(_zoom + delta);

  // ---------------------------------------------------------------
  // Face detection (camera upgrade round, item 3)
  // ---------------------------------------------------------------

  void _selectFaceSticker(FaceStickerKind? kind) {
    setState(() {
      _faceKind = kind;
      _strip = _Strip.face;
      if (kind == null) _faceGeo = [];
    });
    if (kind == null) {
      _stopFaceStream();
    } else {
      _startFaceStream();
    }
  }

  Future<void> _startFaceStream() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _streaming) return;
    try {
      await c.startImageStream(_onCameraFrame);
      _streaming = true;
    } catch (e) {
      debugPrint('face stream start failed: $e');
    }
  }

  Future<void> _stopFaceStream() async {
    final c = _controller;
    if (c == null || !_streaming) return;
    _streaming = false;
    try {
      await c.stopImageStream();
    } catch (e) {
      debugPrint('face stream stop failed: $e');
    }
  }

  /// Throttled frame handler: at most one detection in flight and
  /// one per ~130ms — plenty for a sticker that is baked in 0.5s
  /// segments, and gentle on the phone.
  void _onCameraFrame(CameraImage image) {
    if (_detectBusy) return;
    final now = DateTime.now();
    if (now.difference(_lastDetect).inMilliseconds < 130) return;
    _lastDetect = now;
    _detectBusy = true;
    _detectFaces(image).whenComplete(() => _detectBusy = false);
  }

  Future<void> _detectFaces(CameraImage image) async {
    if (_faceKind == null) return;
    final input = _toInputImage(image);
    if (input == null) return;
    List<Face> faces;
    try {
      faces = await _faceDetector.processImage(input);
    } catch (e) {
      debugPrint('face detection failed: $e');
      return;
    }
    final geo = faces.map(_geometryOf).toList();
    if (!mounted) return;
    setState(() => _faceGeo = geo);
    if (_recording && geo.isNotEmpty) {
      // Log the primary (largest) face — the bake follows it.
      final primary = geo.reduce((a, b) =>
          a.faceRect.width * a.faceRect.height >=
                  b.faceRect.width * b.faceRect.height
              ? a
              : b);
      _track.add(FaceTrackSample(
          _recWatch.elapsedMilliseconds / 1000.0, primary));
    }
  }

  FaceGeometry _geometryOf(Face face) {
    Offset? pt(FaceLandmarkType type) {
      final p = face.landmarks[type]?.position;
      return p == null ? null : Offset(p.x.toDouble(), p.y.toDouble());
    }

    return FaceGeometry(
      faceRect: face.boundingBox,
      leftEye: pt(FaceLandmarkType.leftEye),
      rightEye: pt(FaceLandmarkType.rightEye),
    );
  }

  /// Converts a camera frame into an ML Kit input with the
  /// correct rotation for the current device orientation, and
  /// records the UPRIGHT frame size (the coordinate space ML Kit
  /// reports faces in).
  InputImage? _toInputImage(CameraImage image) {
    final c = _controller;
    if (c == null || _cameras.isEmpty) return null;
    final camera = _cameras[_cameraIndex];
    final rotation = _inputRotation(camera, c.value.deviceOrientation);
    if (rotation == null) return null;
    final rawFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    final Uint8List bytes;
    final int bytesPerRow;
    final InputImageFormat format;
    if (image.format.group == ImageFormatGroup.yuv420) {
      // The camera plugin delivers YUV_420_888 on Android; ML Kit
      // wants NV21 bytes there.
      bytes = _yuv420ToNv21(image);
      bytesPerRow = image.width;
      format = InputImageFormat.nv21;
    } else if (rawFormat == InputImageFormat.nv21 ||
        rawFormat == InputImageFormat.bgra8888) {
      bytes = image.planes[0].bytes;
      bytesPerRow = image.planes[0].bytesPerRow;
      format = rawFormat!;
    } else {
      return null;
    }
    _uprightSize =
        (rotation == InputImageRotation.rotation90deg ||
                rotation == InputImageRotation.rotation270deg)
            ? Size(image.height.toDouble(), image.width.toDouble())
            : Size(image.width.toDouble(), image.height.toDouble());
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  InputImageRotation? _inputRotation(
      CameraDescription camera, DeviceOrientation orientation) {
    const compensation = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final comp = compensation[orientation];
    if (comp == null) return null;
    final raw = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + comp) % 360
        : (camera.sensorOrientation - comp + 360) % 360;
    return InputImageRotationValue.fromRawValue(raw);
  }

  /// YUV_420_888 (three planes, possibly strided / semi-planar)
  /// → NV21 (Y plane + interleaved VU), the layout ML Kit
  /// requires for byte inputs on Android.
  Uint8List _yuv420ToNv21(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final out = Uint8List(w * h * 3 ~/ 2);
    final yPixel = yPlane.bytesPerPixel ?? 1;
    if (yPixel == 1) {
      for (var row = 0; row < h; row++) {
        out.setRange(
            row * w, row * w + w, yPlane.bytes, row * yPlane.bytesPerRow);
      }
    } else {
      var i = 0;
      for (var row = 0; row < h; row++) {
        for (var col = 0; col < w; col++) {
          out[i++] = yPlane.bytes[row * yPlane.bytesPerRow + col * yPixel];
        }
      }
    }
    final uPixel = uPlane.bytesPerPixel ?? 1;
    final vPixel = vPlane.bytesPerPixel ?? 1;
    var i = w * h;
    for (var row = 0; row < h ~/ 2; row++) {
      for (var col = 0; col < w ~/ 2; col++) {
        out[i++] = vPlane.bytes[row * vPlane.bytesPerRow + col * vPixel];
        out[i++] = uPlane.bytes[row * uPlane.bytesPerRow + col * uPixel];
      }
    }
    return out;
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
    var started = false;
    try {
      await c.startVideoRecording();
      started = true;
    } on CameraException catch (e) {
      debugPrint('start recording failed: ${e.code}');
      if (_streaming) {
        // Some devices refuse to record while the face-detection
        // image stream is bound. Drop the stream and retry once;
        // the face overlay then holds its last position and the
        // bake holds the last logged face for the rest of the clip.
        await _stopFaceStream();
        try {
          await c.startVideoRecording();
          started = true;
        } on CameraException catch (e2) {
          debugPrint('start recording retry failed: ${e2.code}');
        }
      }
    }
    if (!started) {
      _showError('Recording could not start. Please try again.');
      return;
    }
    // Face-track logging starts with the recording (item 3).
    _track = [];
    _recWatch
      ..reset()
      ..start();
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
  }

  Future<void> _stop() async {
    final c = _controller;
    if (c == null || !_recording) return;
    _timer?.cancel();
    setState(() => _recording = false);
    await _soundPlayer?.pause();
    _recWatch.stop();
    // The face track rides along only when a sticker was selected
    // AND at least one face was actually logged — never faked.
    final track = (_faceKind != null &&
            _track.isNotEmpty &&
            _uprightSize != null)
        ? FaceTrackData(
            recordedKind: _faceKind!,
            imageSize: _uprightSize!,
            samples: List.of(_track),
          )
        : null;
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
            faceTrack: track,
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
                  // Double-tap switches front/back camera (item 1);
                  // pinch zooms (camera upgrade round, item 1).
                  GestureDetector(
                    onDoubleTap: _flip,
                    onScaleStart: (d) => _baseZoom = _zoom,
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2) {
                        _setZoom(_baseZoom * d.scale);
                      }
                    },
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
                      switch (_strip) {
                        _Strip.looks => _looksRow(),
                        _Strip.effects => _effectsRow(),
                        _Strip.face => _faceRow(),
                      },
                      const SizedBox(height: 12),
                      if (_zoomLabelVisible)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_zoom.toStringAsFixed(1)}×',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _zoomStepper(Icons.remove, () => _stepZoom(-0.5)),
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
                          _zoomStepper(Icons.add, () => _stepZoom(0.5)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Zoom stepper flanking the record button (camera upgrade
  /// round, item 1): tap = ±0.5×, clamped to the camera's range.
  Widget _zoomStepper(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black45,
          border: Border.all(color: Colors.white30),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
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
          // Face sticker overlay (camera upgrade round, item 3):
          // drawn from the latest ML Kit faces, on top of the
          // filtered preview, UNDER the letterbox/frame overlays.
          // It stays up while recording — the preview stack is
          // never torn down when recording starts (item 2).
          if (_faceKind != null &&
              _faceGeo.isNotEmpty &&
              _uprightSize != null)
            Positioned.fill(
              child: CustomPaint(
                painter: _FaceOverlayPainter(
                  faces: _faceGeo,
                  imageSize: _uprightSize!,
                  kind: _faceKind!,
                  mirrored: !_isBackCamera,
                ),
              ),
            ),
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
        const SizedBox(width: 8),
        tab('Face', _Strip.face),
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

  /// Face strip (camera upgrade round, item 3): "None" plus the
  /// real face-following stickers. Selecting one starts on-device
  /// face detection; the sticker follows the face LIVE and is
  /// baked into the posted video at the logged positions.
  Widget _faceRow() {
    Widget tile({
      required String emoji,
      required String name,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: _recording ? null : onTap,
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
                    color: selected ? AppTheme.accent : Colors.white38,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 3),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 78,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          tile(
            emoji: '🚫',
            name: 'None',
            selected: _faceKind == null,
            onTap: () => _selectFaceSticker(null),
          ),
          const SizedBox(width: 10),
          for (final s in FaceStickers.all) ...[
            tile(
              emoji: s.emoji,
              name: s.name,
              selected: _faceKind == s.kind,
              onTap: () => _selectFaceSticker(s.kind),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

/// Paints the selected face sticker over every detected face.
/// Coordinates arrive in UPRIGHT image space and are mapped onto
/// the (cover-fit, full-screen) canvas with the same centred
/// cover math the camera preview uses; the front camera's
/// mirrored preview flips X.
class _FaceOverlayPainter extends CustomPainter {
  final List<FaceGeometry> faces;
  final Size imageSize;
  final FaceStickerKind kind;
  final bool mirrored;

  const _FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    required this.kind,
    required this.mirrored,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    final scale = math.max(
        size.width / imageSize.width, size.height / imageSize.height);
    final dx = (size.width - imageSize.width * scale) / 2;
    final dy = (size.height - imageSize.height * scale) / 2;
    for (final face in faces) {
      final r = stickerRectFor(kind, face);
      final left = mirrored
          ? size.width - (r.right * scale + dx)
          : r.left * scale + dx;
      final screenRect = Rect.fromLTWH(
          left, r.top * scale + dy, r.width * scale, r.height * scale);
      paintFaceSticker(canvas, screenRect, kind);
    }
  }

  @override
  bool shouldRepaint(_FaceOverlayPainter oldDelegate) => true;
}
