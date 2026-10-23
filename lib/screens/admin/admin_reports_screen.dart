import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_moderation.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_common.dart';
import 'package:vibeshort/screens/home/video_viewer_screen.dart';

/// Reports queue (blueprint Section 5): every report with its
/// target, reason and reporter; the admin resolves or dismisses
/// with a recorded decision reason. This is the flow the roadmap
/// completion check names: "Admin can resolve a test report
/// securely."
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  bool _busy = false;

  Future<void> _decide(VibeReport report, {required bool dismiss}) async {
    final reason = await promptText(
      context,
      title: dismiss ? 'Dismiss report' : 'Resolve report',
      label: 'Decision reason',
      hint: dismiss
          ? 'e.g. Reviewed — no policy violation found'
          : 'e.g. Action taken against the reported content',
      confirmLabel: dismiss ? 'Dismiss' : 'Resolve',
    );
    if (reason == null || !mounted) return;
    await runAdminAction(
      context,
      action: () => FirestoreService.instance
          .resolveReport(report, dismiss: dismiss, reason: reason),
      successMessage: dismiss ? 'Report dismissed.' : 'Report resolved.',
      setBusy: (b) => setState(() => _busy = b),
    );
  }

  Future<void> _viewVideo(String videoId) async {
    final video = await FirestoreService.instance.getVideo(videoId);
    if (!mounted) return;
    if (video == null) {
      showAdminSnack(context, 'Video not found (it may be deleted).');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoViewerScreen(videos: [video]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Reports queue')),
      body: StreamBuilder<List<VibeReport>>(
        stream: FirestoreService.instance.adminReports(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final reports = snap.data ?? const <VibeReport>[];
          if (reports.isEmpty) {
            return const Center(
              child: Text('No reports yet.',
                  style: TextStyle(color: AppTheme.muted)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: reports.length,
            itemBuilder: (context, i) => _tile(reports[i]),
          );
        },
      ),
    );
  }

  Widget _tile(VibeReport r) {
    final statusColor = r.isOpen
        ? const Color(0xFFFFB340)
        : (r.status == VibeReport.statusResolved
            ? const Color(0xFF3DDC84)
            : AppTheme.muted);
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
            children: [
              Icon(
                r.targetType == 'video'
                    ? Icons.ondemand_video_outlined
                    : Icons.person_outline,
                size: 18,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 8),
              Text(
                '${r.targetLabel} report',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              StatusChip(
                  r.isOpen
                      ? 'Open'
                      : (r.status == VibeReport.statusResolved
                          ? 'Resolved'
                          : 'Dismissed'),
                  statusColor),
            ],
          ),
          const SizedBox(height: 8),
          Text('Reason: ${r.reason}',
              style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Reported by ',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
              UserNameText(r.reporterId,
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12.5)),
              const Text(' • ',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
              Text(fmtDate(r.createdAt),
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12.5)),
            ],
          ),
          if (r.targetType == 'user') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Target user: ',
                    style:
                        TextStyle(color: AppTheme.muted, fontSize: 12.5)),
                UserNameText(r.targetId,
                    style: const TextStyle(
                        color: AppTheme.muted, fontSize: 12.5)),
              ],
            ),
          ],
          if (!r.isOpen && r.resolution.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Decision: ${r.resolution}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              if (r.targetType == 'video')
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _viewVideo(r.targetId),
                  icon: const Icon(Icons.play_arrow, size: 17),
                  label: const Text('View video'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24)),
                ),
              if (r.isOpen) ...[
                ElevatedButton(
                  onPressed: _busy ? null : () => _decide(r, dismiss: false),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                  child: const Text('Resolve'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _decide(r, dismiss: true),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 40),
                      side: const BorderSide(color: Colors.white24)),
                  child: const Text('Dismiss'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
