import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_moderation.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_common.dart';

/// Audit log (blueprint Section 5): the read-only trail of every
/// admin action — who did it, what, to which target, and why.
class AdminAuditScreen extends StatelessWidget {
  const AdminAuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Audit log')),
      body: StreamBuilder<List<VibeAuditLog>>(
        stream: FirestoreService.instance.auditLogs(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final logs = snap.data ?? const <VibeAuditLog>[];
          if (logs.isEmpty) {
            return const Center(
              child: Text('No admin actions recorded yet.',
                  style: TextStyle(color: AppTheme.muted)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: logs.length,
            itemBuilder: (context, i) => _tile(logs[i]),
          );
        },
      ),
    );
  }

  Widget _tile(VibeAuditLog log) {
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
              const Icon(Icons.receipt_long_outlined,
                  size: 17, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  log.actionLabel,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              Text(fmtDate(log.createdAt),
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            children: [
              const Text('Admin: ',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
              UserNameText(log.adminId,
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12.5)),
              const Text('  •  Target: ',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
              Text('${log.targetType} ',
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12.5)),
              if (log.targetType == 'user' ||
                  log.targetType == 'referral')
                UserNameText(log.targetId,
                    style: const TextStyle(
                        color: AppTheme.muted, fontSize: 12.5))
              else
                Text(
                  log.targetId.length > 18
                      ? '${log.targetId.substring(0, 18)}…'
                      : log.targetId,
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12.5),
                ),
            ],
          ),
          if (log.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Reason: ${log.reason}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
