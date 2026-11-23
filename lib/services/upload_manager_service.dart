import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/services/storage_service.dart';

/// Lifecycle of the one background upload the app runs at a time.
enum UploadPhase { idle, uploading, done, failed }

/// Background upload manager (TikTok-style flow): the editor
/// bakes the video ("Applying effects" progress, unchanged), then
/// hands the finished file + post metadata to this singleton and
/// returns straight to the home feed. The upload itself — the
/// same Cloudinary upload + Firestore video doc the old blocking
/// post flow ran inline — happens here, off-screen, reporting
/// progress for the feed's circular indicator
/// (see `widgets/upload_progress_circle.dart`).
///
/// One upload at a time: [startUpload] returns false while one
/// is running, and the caller tells the user to wait. A failed
/// upload keeps its file + metadata so the feed circle can offer
/// a one-tap retry; [dismiss] drops it.
class UploadManagerService extends ChangeNotifier {
  UploadManagerService._();

  static final UploadManagerService instance = UploadManagerService._();

  UploadPhase _phase = UploadPhase.idle;
  double _progress = 0;
  String? _error;

  /// The pending post, retained across the run so a failure can
  /// be retried without re-collecting anything. [_title] is the
  /// caption the user wrote (may be empty).
  File? _file;
  String _title = '';
  String? _soundName;
  String? _soundId;
  String? _soundSourceVideoId;
  String? _soundOwnerId;

  /// How long the "done" check state lingers before the circle
  /// hides itself.
  Timer? _doneTimer;

  UploadPhase get phase => _phase;
  double get progress => _progress;
  String? get error => _error;
  String get title => _title;
  bool get isUploading => _phase == UploadPhase.uploading;

  /// Starts a background upload of [file] with the post metadata
  /// the create flow collected. Returns false — and changes
  /// nothing — when an upload is already running.
  bool startUpload({
    required File file,
    required String caption,
    String? soundName,
    String? soundId,
    String? soundSourceVideoId,
    String? soundOwnerId,
  }) {
    if (_phase == UploadPhase.uploading) return false;
    _doneTimer?.cancel();
    _file = file;
    _title = caption;
    _soundName = soundName;
    _soundId = soundId;
    _soundSourceVideoId = soundSourceVideoId;
    _soundOwnerId = soundOwnerId;
    _run();
    return true;
  }

  /// Re-runs the retained upload after a failure.
  void retry() {
    if (_phase != UploadPhase.failed || _file == null) return;
    _run();
  }

  /// Drops the retained upload (failed-state dismiss, or clears
  /// a lingering done state). Never interrupts a running upload.
  void dismiss() {
    if (_phase == UploadPhase.uploading) return;
    _doneTimer?.cancel();
    _phase = UploadPhase.idle;
    _progress = 0;
    _error = null;
    _file = null;
    _title = '';
    notifyListeners();
  }

  Future<void> _run() async {
    final file = _file;
    if (file == null) return;
    _phase = UploadPhase.uploading;
    _progress = 0;
    _error = null;
    notifyListeners();
    try {
      final url = await StorageService.instance.uploadVideo(
        file,
        onProgress: (p) {
          if (_phase != UploadPhase.uploading) return;
          _progress = p;
          notifyListeners();
        },
      );
      await FirestoreService.instance.addVideo(
        videoUrl: url,
        caption: _title,
        soundName: _soundName,
        soundId: _soundId,
        soundSourceVideoId: _soundSourceVideoId,
        soundOwnerId: _soundOwnerId,
      );
      _progress = 1;
      _phase = UploadPhase.done;
      notifyListeners();
      // Brief check state, then the circle hides itself. The new
      // video doc reaches the feed through its live Firestore
      // stream, so no manual refresh is forced on the user.
      _doneTimer?.cancel();
      _doneTimer = Timer(const Duration(seconds: 3), () {
        if (_phase == UploadPhase.done) dismiss();
      });
    } catch (e) {
      _phase = UploadPhase.failed;
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }
}
