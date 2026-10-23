import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/screens/create/camera_record_screen.dart';
import 'package:vibeshort/screens/create/edit_video_screen.dart';

/// Create hub (the + tab): "Record video" opens the in-app camera
/// with LIVE filters and effects over the preview; "Pick from
/// gallery" chooses an existing clip. Both routes land on the edit
/// screen (live-look preview, trim, filters, effects, music, text,
/// caption) where the chosen edits are baked in before posting.
class UploadScreen extends StatefulWidget {
  /// Called after a successful post (shell switches to Home).
  final VoidCallback? onPosted;

  const UploadScreen({super.key, this.onPosted});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _picking = false;
  String? _error;

  void _openRecorder() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraRecordScreen(onPosted: widget.onPosted),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    // Re-entrancy guard: image_picker throws
    // PlatformException(already_active) if a pick is already running.
    if (_picking) return;
    _picking = true;
    setState(() => _error = null);
    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 60),
      );
      if (picked == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditVideoScreen(
            videoPath: picked.path,
            onPosted: widget.onPosted,
          ),
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('pickVideo PlatformException: ${e.code}');
      if (!mounted) return;
      setState(() => _error = e.code == 'already_active'
          ? 'The picker is already open, please wait a moment.'
          : 'Could not pick the video. Please try again.');
    } catch (e) {
      debugPrint('pickVideo failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Could not pick a video. Please try again.');
    } finally {
      _picking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Create')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.video_call_outlined,
                size: 64, color: AppTheme.muted),
            const SizedBox(height: 16),
            const Text(
              'Create a video',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Record with live filters and effects, or pick a clip from '
              'your gallery (up to 60 seconds) and edit it before posting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _openRecorder,
              icon: const Icon(Icons.videocam),
              label: const Text('Record video'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _picking ? null : _pickFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Pick from gallery'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFFFF5C7A), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
