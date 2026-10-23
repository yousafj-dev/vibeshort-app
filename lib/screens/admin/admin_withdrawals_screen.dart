import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_wallet.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_common.dart';

/// Withdrawals review (blueprint Sections 4 + 5): pending payout
/// requests from Phase 3. Approve records the provider reference
/// and moves the ledger hold to 'paid'; Reject records the reason
/// and reverses the hold. Both go ONLY through ledger entries —
/// no balance is ever edited directly.
class AdminWithdrawalsScreen extends StatefulWidget {
  const AdminWithdrawalsScreen({super.key});

  @override
  State<AdminWithdrawalsScreen> createState() =>
      _AdminWithdrawalsScreenState();
}

class _AdminWithdrawalsScreenState extends State<AdminWithdrawalsScreen> {
  bool _busy = false;

  Future<void> _approve(VibeWithdrawal w) async {
    final ref = await promptText(
      context,
      title: 'Approve payout',
      label: 'Provider reference',
      hint: 'e.g. Easypaisa transaction ID',
      confirmLabel: 'Approve & mark paid',
    );
    if (ref == null || !mounted) return;
    await runAdminAction(
      context,
      action: () => FirestoreService.instance
          .approveWithdrawal(w, providerReference: ref),
      successMessage: 'Withdrawal approved and marked paid.',
      setBusy: (b) => setState(() => _busy = b),
    );
  }

  Future<void> _reject(VibeWithdrawal w) async {
    final reason = await promptText(
      context,
      title: 'Reject payout',
      label: 'Rejection reason',
      hint: 'The held amount returns to the user\'s available balance',
      confirmLabel: 'Reject',
    );
    if (reason == null || !mounted) return;
    await runAdminAction(
      context,
      action: () => FirestoreService.instance
          .rejectWithdrawal(w, reason: reason),
      successMessage: 'Withdrawal rejected. Hold reversed.',
      setBusy: (b) => setState(() => _busy = b),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Withdrawals')),
      body: StreamBuilder<List<VibeWithdrawal>>(
        stream: FirestoreService.instance.adminWithdrawals(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final list = snap.data ?? const <VibeWithdrawal>[];
          if (list.isEmpty) {
            return const Center(
              child: Text('No withdrawal requests yet.',
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

  Widget _tile(VibeWithdrawal w) {
    final pending = w.status == VibeWithdrawal.statusPendingReview;
    final statusColor = pending
        ? const Color(0xFFFFB340)
        : (w.status == VibeWithdrawal.statusRejected
            ? const Color(0xFFFF5C7A)
            : const Color(0xFF3DDC84));
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
              Text(
                formatPkr(w.amount),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              StatusChip(w.statusLabel, statusColor),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('User: ',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13)),
              UserNameText(w.userId,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${w.payoutMethod} • ${w.payoutAccount}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Requested ${fmtDate(w.createdAt)}'
            '${w.reviewedAt != null ? ' • Reviewed ${fmtDate(w.reviewedAt!)}' : ''}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
          ),
          if (pending) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : () => _approve(w),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _reject(w),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5C7A),
                      minimumSize: const Size(0, 40),
                      side: const BorderSide(color: Color(0xFFFF5C7A))),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
