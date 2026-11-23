import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/services/storage_service.dart';
import 'package:vibeshort/services/video_edit_service.dart';

/// Lifecycle of the one background post job the app runs at a
/// time. [preparing] is the FFmpeg bake ("Applying effects");
/// [uploading] is the Cloudinary upload + Firestore doc that
/// follows it. A post with no edits skips [preparing] entirely.
enum UploadPhase { idle, preparing, uploading, done, failed }

/// Background post manager (TikTok-style flow): when the user
/// taps Post, the editor hands this singleton either the finished
/// file (no edits) or a [BakeRecipe] (edits chosen) plus the post
/// metadata, and returns straight to the home feed. The whole job
/// — bake first when there is one, then the same Cloudinary
/// upload + Firestore video doc the old blocking post flow ran
/// inline — happens here, off-screen, reporting per-stage
/// progress for the feed's circular indicator (see
/// `widgets/upload_progress_circle.dart`).
///
/// One job at a time: [startJob] returns false while a job is
/// running, and the caller tells the user to wait. A failed job
/// keeps its recipe/file + metadata so the feed circle can offer
/// a one-tap retry (resuming at the failed stage); [dismiss]
/// drops it. While the bake runs, [cancelJob] aborts it.
class UploadManagerService extends ChangeNotifier {
  UploadManagerService._();

  static final UploadManagerService instance = UploadManagerService._();

  UploadPhase _phase = UploadPhase.idle;
  double _progress = 0;
  String? _error;

  /// The pending post, retained across the run so a failure can
  /// be retried without re-collecting anything. [_file] is the
  /// file to upload: set immediately for an unedited post, or
  /// filled in by the bake stage when a [_bakeRecipe] was given.
  /// [_title] is the caption the user wrote (may be empty).
  File? _file;
  BakeRecipe? _bakeRecipe;
  String _title = '';
  String? _soundName;
  String? _soundId;
  String? _soundSourceVideoId;
  String? _soundOwnerId;

  /// Set by [cancelJob] while the bake runs; the bake's failure
  /// then unwinds the job silently (back to idle) instead of
  /// landing in the failed state.
  bool _cancelRequested = false;

  /// How long the "done" check state lingers before the circle
  /// hides itself.
  Timer? _doneTimer;

  UploadPhase get phase => _phase;

  /// Progress (0.0–1.0) within the CURRENT stage: the bake while
  /// [phase] is [UploadPhase.preparing], the upload while it is
  /// [UploadPhase.uploading].
  double get progress => _progress;
  String? get error => _error;
  String get title => _title;
  bool get isPreparing => _phase == UploadPhase.preparing;
  bool get isUploading => _phase == UploadPhase.uploading;

  /// True while any stage of a job is running.
  bool get isBusy =>
      _phase == UploadPhase.preparing || _phase == UploadPhase.uploading;

  /// Starts a background post job. Pass [file] for an unedited
  /// clip (uploaded as-is) or [bakeRecipe] when edits were chosen
  /// (baked in the background first, then uploaded). Returns
  /// false — and changes nothing — when a job is already running.
  bool startJob({
    File? file,
    BakeRecipe? bakeRecipe,
    required String caption,
    String? soundName,
    String? soundId,
    String? soundSourceVideoId,
    String? soundOwnerId,
  }) {
    if (isBusy) return false;
    if (file == null && bakeRecipe == null) return false;
    _doneTimer?.cancel();
    _file = file;
    _bakeRecipe = bakeRecipe;
    _title = caption;
    _soundName = soundName;
    _soundId = soundId;
    _soundSourceVideoId = soundSourceVideoId;
    _soundOwnerId = soundOwnerId;
    _run();
    return true;
  }

  /// Re-runs the retained job after a failure, resuming at the
  /// failed stage: a job whose bake never produced a file bakes
  /// again; a job that failed mid-upload re-uploads the baked
  /// file without re-baking.
  void retry() {
    if (_phase != UploadPhase.failed) return;
    if (_file == null && _bakeRecipe == null) return;
    _run();
  }

  /// Cancels the job while its bake is running (the feed circle's
  /// Cancel action). The bake aborts and the job is dropped
  /// silently — nothing is uploaded and no error is shown. Does
  /// nothing in any other phase (an upload in flight cannot be
  /// cancelled).
  Future<void> cancelJob() async {
    if (_phase != UploadPhase.preparing) return;
    _cancelRequested = true;
    await _bakeRecipe?.cancel();
  }

  /// Drops the retained job (failed-state dismiss, or clears a
  /// lingering done state). Never interrupts a running job.
  void dismiss() {
    if (isBusy) return;
    _doneTimer?.cancel();
    _phase = UploadPhase.idle;
    _progress = 0;
    _error = null;
    _clearJob();
    notifyListeners();
  }

  void _clearJob() {
    _file = null;
    _bakeRecipe = null;
    _title = '';
    _soundName = null;
    _soundId = null;
    _soundSourceVideoId = null;
    _soundOwnerId = null;
  }

  Future<void> _run() async {
    _error = null;
    _cancelRequested = false;
    try {
      // Stage 1 — bake (only when a recipe was handed over and
      // no baked file exists yet; a retry after an upload failure
      // already has its file and skips straight to stage 2).
      final recipe = _bakeRecipe;
      if (_file == null && recipe != null) {
        _phase = UploadPhase.preparing;
        _progress = 0;
        notifyListeners();
        final baked = await recipe.bake(
          onProgress: (p) {
            if (_phase != UploadPhase.preparing) return;
            _progress = p;
            notifyListeners();
          },
        );
        // A cancel that landed just as the bake finished still
        // wins: drop the job instead of uploading.
        if (_cancelRequested) {
          _phase = UploadPhase.idle;
          _progress = 0;
          _clearJob();
          notifyListeners();
          return;
        }
        _file = baked;
      }
      final file = _file;
      if (file == null) return;

      // Stage 2 — upload the (possibly baked) file and create
      // the video doc, exactly as the old inline flow did.
      _phase = UploadPhase.uploading;
      _progress = 0;
      notifyListeners();
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
      if (_cancelRequested) {
        // User-cancelled bake: unwind quietly, no failed state,
        // no error SnackBar.
        _phase = UploadPhase.idle;
        _progress = 0;
        _error = null;
        _clearJob();
        notifyListeners();
        return;
      }
      _phase = UploadPhase.failed;
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }
}
