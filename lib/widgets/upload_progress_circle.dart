import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/upload_manager_service.dart';

/// TikTok-style background-upload indicator for the home feed:
/// a small circle on the right edge (below the action rail, just
/// above the bottom nav) with a progress ring and the live
/// percentage number inside while [UploadManagerService] uploads.
///
/// States mirror the manager's phase:
///  * uploading — ring + "42%" counting up;
///  * done — a check for a few seconds, then it hides itself;
///  * failed — a red alert circle: tap retries the upload, the
///    small × badge dismisses it.
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
          case UploadPhase.uploading:
            return _circle(
              child: Stack(
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
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 4)
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
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
