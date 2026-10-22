import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/services/storage_service.dart';

/// Upload tab: pick from gallery or record with the camera
/// (max 60s), preview, add a caption, post.
class UploadScreen extends StatefulWidget {
  /// Called after a successful post (shell switches to Home).
  final VoidCallback? onPosted;

  const UploadScreen({super.key, this.onPosted});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final _captionCtrl = TextEditingController();
  File? _file;
  VideoPlayerController? _preview;
  bool _uploading = false;
  double _progress = 0;

  @override
  void dispose() {
    _captionCtrl.dispose();
    _preview?.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (picked == null) return;
      final file = File(picked.path);
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.play();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      _preview?.dispose();
      setState(() {
        _file = file;
        _preview = ctrl;
      });
    } catch (e) {
      debugPrint('pickVideo failed: $e');
      _toast(source == ImageSource.camera
          ? 'Could not open the camera. Please check the camera permission.'
          : 'Could not pick the video. Please try again.');
    }
  }

  Future<void> _post() async {
    final file = _file;
    if (file == null || _uploading) return;
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      final url = await StorageService.instance.uploadVideo(
        file,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await FirestoreService.instance.addVideo(
        videoUrl: url,
        caption: _captionCtrl.text,
      );
      _toast('Your video is live!');
      _preview?.pause();
      setState(() {
        _file = null;
        _captionCtrl.clear();
      });
      widget.onPosted?.call();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Create')),
      body: _file == null ? _pickerView() : _editorView(),
    );
  }

  Widget _pickerView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_call_outlined,
              size: 64, color: AppTheme.muted),
          const SizedBox(height: 16),
          const Text(
            'Create a video',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Record something new or pick a clip from your gallery (up to 60 seconds).',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => _pick(ImageSource.camera),
            icon: const Icon(Icons.videocam),
            label: const Text('Record video'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pick(ImageSource.gallery),
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
        ],
      ),
    );
  }

  Widget _editorView() {
    final ctrl = _preview;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 380,
              color: Colors.black,
              child: ctrl != null && ctrl.value.isInitialized
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: ctrl.value.size.width,
                        height: ctrl.value.size.height,
                        child: VideoPlayer(ctrl),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accent)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionCtrl,
            maxLines: 3,
            maxLength: 150,
            decoration: const InputDecoration(
              hintText: 'Write a caption… #hashtags welcome',
            ),
          ),
          const SizedBox(height: 8),
          if (_uploading) ...[
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              color: AppTheme.accent,
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 8),
            Text(
              'Uploading… ${(_progress * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed: _uploading ? null : _post,
            icon: const Icon(Icons.upload),
            label: const Text('Post video'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _uploading
                ? null
                : () {
                    _preview?.pause();
                    setState(() => _file = null);
                  },
            child: const Text('Choose a different video'),
          ),
        ],
      ),
    );
  }
}
