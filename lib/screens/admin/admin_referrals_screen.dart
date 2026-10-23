import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_wallet.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_common.dart';

/// Referral controls (blueprint Section 5): track who referred
/// whom and with which code, see qualification status, and mark
/// abusive referrals ineligible (recorded in the audit log).
class AdminReferralsScreen extends StatefulWidget {
  const AdminReferralsScreen({super.key});

  @override
  State<AdminReferralsScreen> createState() => _AdminReferralsScreenState();
}

class _AdminReferralsScreenState extends State<AdminReferralsScreen> {
  bool _busy = false;

  Future<void> _markIneligible(VibeReferral r) async {
    final reason = await promptText(
      context,
      title: 'Mark referral ineligible',
      label: 'Reason',
      hint: 'e.g. Self-referral / fake account pattern',
      confirmLabel: 'Mark ineligible',
    );
    if (reason == null || !mounted) return;
    await runAdminAction(
      context,
      action: () => FirestoreService.instance
          .markReferralIneligible(r, reason: reason),
      successMessage: 'Referral marked ineligible.',
      setBusy: (b) => setState(() => _busy = b),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Referral controls')),
      body: StreamBuilder<List<VibeReferral>>(
        stream: FirestoreService.instance.adminReferrals(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final list = snap.data ?? const <VibeReferral>[];
          if (list.isEmpty) {
            return const Center(
              child: Text('No referrals recorded yet.',
                  style: TextStyle(color: AppTheme.muted)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: list.length,
            itemBuilder: (context, i) => _tile(list[i]),
          );
        },
      ),
    );
  }

  Widget _tile(VibeReferral r) {
    final status = r.qualificationStatus;
    final color = status == 'qualified'
        ? const Color(0xFF3DDC84)
        : status == 'rejected'
            ? const Color(0xFFFF5C7A)
            : const Color(0xFFFFB340);
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
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    UserNameText(r.referrerId,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                    const Text('  referred  ',
                        style: TextStyle(color: AppTheme.muted)),
                    UserNameText(r.referredUserId,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              StatusChip(
                status == 'rejected'
                    ? 'Ineligible'
                    : (status == 'qualified' ? 'Qualified' : 'Pending'),
                color,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Code: ${r.code} • ${fmtDate(r.createdAt)}'
            '${r.rewardTransactionId != null ? ' • Reward tx: ${r.rewardTransactionId}' : ''}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
          ),
          if (status == 'pending') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _markIneligible(r),
              icon: const Icon(Icons.block, size: 16),
              label: const Text('Mark ineligible'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF5C7A),
                  side: const BorderSide(color: Color(0xFFFF5C7A))),
            ),
          ],
        ],
      ),
    );
  }
}
