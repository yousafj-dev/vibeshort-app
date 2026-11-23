import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/upload_manager_service.dart';

/// TikTok-style background-post indicator for the home feed:
/// a small circle on the right edge (below the action rail, just
/// above the bottom nav) with a progress ring and the live
/// percentage number inside while [UploadManagerService] runs a
/// post job.
///
/// States mirror the manager's phase:
///  * preparing — ring + bake "%" with a small "Preparing" label
///    under the circle; tapping the circle offers Cancel
///    (confirm dialog) which aborts the bake and drops the post;
///  * uploading — ring + upload "%" counting up;
///  * done — a check for a few seconds, then it hides itself;
///  * failed — a red alert circle: tap retries the job (resuming
///    at the failed stage), the small × badge dismisses it.
/// Renders nothing while idle.
class UploadProgressCircle extends StatelessWidget {
  const UploadProgressCircle({super.key});

  static const double _size = 54;

  @override
  Widget build(BuildContext context) {
    final mgr = UploadManagerService.instance;
    return AnimatedBuilder(
      animation: mgr,
      builder: (context, _) {
        switch (mgr.phase) {
          case UploadPhase.idle:
            return const SizedBox.shrink();
          case UploadPhase.preparing:
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _confirmCancel(context),
                  child: _circle(child: _ring(mgr)),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Preparing',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Colors.black87, blurRadius: 4)
                    ],
                  ),
                ),
              ],
            );
          case UploadPhase.uploading:
            return _circle(child: _ring(mgr));
          case UploadPhase.done:
            return _circle(
              child: Icon(Icons.check_circle,
                  color: AppTheme.accent, size: 30),
            );
          case UploadPhase.failed:
            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: mgr.retry,
                  child: _circle(
                    borderColor: const Color(0xFFFF5C7A),
                    child: const Icon(Icons.cloud_off,
                        color: Color(0xFFFF5C7A), size: 26),
                  ),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: mgr.dismiss,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black87,
                        border: Border.all(color: Colors.white38),
                      ),
                      child: const Icon(Icons.close,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
        }
      },
    );
  }

  /// The progress ring with the live percentage inside — shared
  /// by the preparing and uploading states.
  Widget _ring(UploadManagerService mgr) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CircularProgressIndicator(
          value: mgr.progress > 0 ? mgr.progress : null,
          strokeWidth: 3.2,
          backgroundColor: Colors.white24,
          color: AppTheme.accent,
        ),
        Center(
          child: Text(
            '${(mgr.progress * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
            ),
          ),
        ),
      ],
    );
  }

  /// Cancel confirmation for the bake stage: confirms, then asks
  /// the manager to abort the bake and drop the post.
  Future<void> _confirmCancel(BuildContext context) async {
    final mgr = UploadManagerService.instance;
    if (!mgr.isPreparing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this post?'),
        content: const Text(
            'Stop preparing the video and discard the post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep preparing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel post'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await mgr.cancelJob();
    }
  }

  Widget _circle({required Widget child, Color? borderColor}) {
    return Container(
      width: _size,
      height: _size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black54,
        border: Border.all(color: borderColor ?? Colors.white24),
      ),
      child: child,
    );
  }
}
