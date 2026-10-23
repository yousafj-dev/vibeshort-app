import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_moderation.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_common.dart';
import 'package:vibeshort/screens/home/video_viewer_screen.dart';

/// Video moderation (blueprint Section 5): every video that has
/// at least one report, grouped from the reports stream, with the
/// Keep / Remove decisions. Remove sets moderation_status so the
/// video leaves all feeds; Keep dismisses its open reports with
/// the review decision recorded.
class AdminVideosScreen extends StatefulWidget {
  const AdminVideosScreen({super.key});

  @override
  State<AdminVideosScreen> createState() => _AdminVideosScreenState();
}

class _AdminVideosScreenState extends State<AdminVideosScreen> {
  bool _busy = false;

  Future<void> _keep(VibeVideo video, int openReports) async {
    final reason = await promptText(
      context,
      title: 'Keep this video',
      label: 'Review decision',
      hint: 'e.g. Reviewed — content follows the policy',
      confirmLabel: 'Keep video',
    );
    if (reason == null || !mounted) return;
    await runAdminAction(
      context,
      action: () =>
          FirestoreService.instance.keepVideo(video.id, reason: reason),
      successMessage: 'Video kept. Its open reports were dismissed.',
      setBusy: (b) => setState(() => _busy = b),
    );
  }

  Future<void> _remove(VibeVideo video) async {
    final ok = await confirmAction(
      context,
      title: 'Remove this video?',
      message:
          'It will disappear from all feeds immediately. This is recorded in the audit log.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    final reason = await promptText(
      context,
      title: 'Removal reason',
      label: 'Policy reason',
      hint: 'e.g. Violates the spam policy',
      confirmLabel: 'Remove video',
    );
    if (reason == null || !mounted) return;
    await runAdminAction(
      context,
      action: () =>
          FirestoreService.instance.removeVideo(video.id, reason: reason),
      successMessage: 'Video removed from all feeds.',
      setBusy: (b) => setState(() => _busy = b),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Video moderation')),
      body: StreamBuilder<List<VibeReport>>(
        stream: FirestoreService.instance.adminReports(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final reports = (snap.data ?? const <VibeReport>[])
              .where((r) => r.targetType == 'video')
              .toList();
          // Group by video: total reports + open reports.
          final byVideo = <String, List<VibeReport>>{};
          for (final r in reports) {
            byVideo.putIfAbsent(r.targetId, () => []).add(r);
          }
          if (byVideo.isEmpty) {
            return const Center(
              child: Text('No reported videos.',
                  style: TextStyle(color: AppTheme.muted)),
            );
          }
          final ids = byVideo.keys.toList()
            ..sort((a, b) {
              final ao = byVideo[a]!.where((r) => r.isOpen).length;
              final bo = byVideo[b]!.where((r) => r.isOpen).length;
              return bo.compareTo(ao);
            });
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: ids.length,
            itemBuilder: (context, i) {
              final id = ids[i];
              final rs = byVideo[id]!;
              final open = rs.where((r) => r.isOpen).length;
              return FutureBuilder<VibeVideo?>(
                future: FirestoreService.instance.getVideo(id),
                builder: (context, vsnap) {
                  if (vsnap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.accent)),
                    );
                  }
                  final video = vsnap.data;
                  if (video == null) {
                    return _missingTile(id, rs.length, open);
                  }
                  return _videoTile(video, rs, open);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _missingTile(String id, int total, int open) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'Video $id — $total report(s), $open open. The video document no longer exists.',
        style: const TextStyle(color: AppTheme.muted),
      ),
    );
  }

  Widget _videoTile(VibeVideo video, List<VibeReport> rs, int open) {
    final reasons = rs.map((r) => r.reason).toSet().join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: video.thumbUrl.isNotEmpty
                    ? Image.network(video.thumbUrl,
                        width: 54,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumbFallback())
                    : _thumbFallback(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.caption.isEmpty
                          ? '(no caption)'
                          : video.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('by ',
                            style: TextStyle(
                                color: AppTheme.muted, fontSize: 12.5)),
                        UserNameText(video.uid,
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12.5)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$open open • ${rs.length} total report(s)',
                      style: const TextStyle(
                          color: AppTheme.muted, fontSize: 12.5),
                    ),
                    Text(
                      'Reasons: $reasons',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (video.isRemoved)
                const StatusChip('Removed', Color(0xFFFF5C7A)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                VideoViewerScreen(videos: [video]),
                          ),
                        ),
                icon: const Icon(Icons.play_arrow, size: 17),
                label: const Text('Watch'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24)),
              ),
              if (!video.isRemoved) ...[
                ElevatedButton(
                  onPressed: _busy ? null : () => _keep(video, open),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                  child: const Text('Keep'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _remove(video),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5C7A),
                      minimumSize: const Size(0, 40),
                      side: const BorderSide(color: Color(0xFFFF5C7A))),
                  child: const Text('Remove'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      width: 54,
      height: 72,
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: const Icon(Icons.play_circle_outline,
          color: Colors.white70, size: 24),
    );
  }
}
