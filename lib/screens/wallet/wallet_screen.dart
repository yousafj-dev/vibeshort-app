import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_notification.dart' show timeAgoLabel;
import 'package:vibeshort/models/vibe_wallet.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';

/// Wallet (Phase 3, blueprint Sections 2-4 + 8).
///
/// Shows the balance breakdown (pending / available / paid —
/// always DERIVED from the transaction ledger, the source of
/// truth), the transaction history, withdrawal requests, the
/// published payout rules and the user's referral code.
///
/// Monetization is in TEST MODE: no payment provider is connected
/// yet, so balances start at Rs 0, nothing here is a promise of
/// earnings, and withdrawal requests are only recorded for manual
/// review (the Admin phase) — they are never auto-approved.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    // Creates the wallet doc + referral code on first open.
    FirestoreService.instance.ensureWalletAndReferralCode();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(
          child:
              Text('Please log in.', style: TextStyle(color: AppTheme.muted)),
        ),
      );
    }
    final fs = FirestoreService.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Wallet')),
      body: StreamBuilder<List<VibeTransaction>>(
        stream: fs.myTransactions(),
        builder: (context, txSnap) {
          final txs = txSnap.data ?? const <VibeTransaction>[];
          final balances = WalletBalances.fromTransactions(txs);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _testModeNote(),
              const SizedBox(height: 16),
              _balanceCard(balances),
              const SizedBox(height: 16),
              _withdrawSection(context, balances),
              const SizedBox(height: 24),
              _sectionTitle('Withdrawal requests'),
              const SizedBox(height: 8),
              StreamBuilder<List<VibeWithdrawal>>(
                stream: fs.myWithdrawals(),
                builder: (context, snap) {
                  final list = snap.data ?? const <VibeWithdrawal>[];
                  if (list.isEmpty) {
                    return const Text(
                      'No withdrawal requests yet.',
                      style: TextStyle(color: AppTheme.muted),
                    );
                  }
                  return Column(
                    children: list.map(_withdrawalRow).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              _sectionTitle('Refer & earn'),
              const SizedBox(height: 8),
              _referralCard(context),
              const SizedBox(height: 24),
              _sectionTitle('Payout rules'),
              const SizedBox(height: 8),
              _rulesCard(),
              const SizedBox(height: 24),
              _sectionTitle('Transaction history'),
              const SizedBox(height: 8),
              if (txSnap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.accent),
                  ),
                )
              else if (txs.isEmpty)
                const Text(
                  'No transactions yet. Your ledger is empty and your balance is Rs 0.',
                  style: TextStyle(color: AppTheme.muted),
                )
              else
                ...txs.map(_transactionRow),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------

  Widget _testModeNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppTheme.accent, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Monetization is in test mode. Real payouts will begin '
              'only after payment-provider setup is complete. Your '
              'balance below comes only from your transaction ledger '
              '— nothing is added by hand.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(WalletBalances b) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available balance',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            formatPkr(b.available),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _balanceStat('Pending', formatPkr(b.pending))),
              Expanded(child: _balanceStat('Paid out', formatPkr(b.paid))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balanceStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _withdrawSection(BuildContext context, WalletBalances b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => _showWithdrawDialog(context, b),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 19),
          label: const Text('Request withdrawal'),
        ),
        const SizedBox(height: 8),
        Text(
          'Minimum withdrawal ${formatPkr(WalletRules.minWithdrawalPkr.toDouble())} '
          'from your available balance. Every request is reviewed '
          'manually before any payout.',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _referralCard(BuildContext context) {
    final fs = FirestoreService.instance;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your referral code',
            style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          StreamBuilder<String>(
            stream: fs.myReferralCode(),
            builder: (context, snap) {
              final code = snap.data ?? '';
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      code.isEmpty ? '…' : code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined,
                        color: Colors.white70, size: 20),
                    onPressed: code.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                                ClipboardData(text: code));
                            _toast('Referral code copied.');
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined,
                        color: Colors.white70, size: 20),
                    onPressed: code.isEmpty
                        ? null
                        : () => Share.share(
                            'Join me on VibeShort! Use my referral code '
                            '$code when you sign up.'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          const Text(
            'Friends enter this code when they sign up. Referral '
            'rewards apply only to verified, qualifying referrals — '
            'self-referrals and fake accounts do not qualify.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<VibeReferral>>(
            stream: fs.myReferrals(),
            builder: (context, snap) {
              final list = snap.data ?? const <VibeReferral>[];
              if (list.isEmpty) {
                return const Text(
                  'No referrals yet.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${list.length} ${list.length == 1 ? 'friend' : 'friends'} joined with your code:',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  ...list.map(
                    (r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.person_add_alt_1_outlined,
                              size: 16, color: AppTheme.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Joined • ${timeAgoLabel(r.createdAt)}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12.5),
                            ),
                          ),
                          _chip(r.qualificationStatus),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _rulesCard() {
    final rules = <String>[
      'Minimum withdrawal is ${formatPkr(WalletRules.minWithdrawalPkr.toDouble())}.',
      'Only your available balance can be withdrawn. Pending rewards cannot be withdrawn.',
      'Every withdrawal request is reviewed manually before any payout is made.',
      'If a request is rejected, the held amount returns to your available balance in the ledger.',
      'Rewards depend on campaigns and eligibility rules. Earnings are never guaranteed.',
      'For a dispute, contact support and quote the transaction reference from your history.',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rules
            .map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(color: AppTheme.accent)),
                    Expanded(
                      child: Text(
                        r,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Rows
  // ---------------------------------------------------------------

  Widget _withdrawalRow(VibeWithdrawal w) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatPkr(w.amount)} → ${w.payoutMethod}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                Text(
                  timeAgoLabel(w.createdAt),
                  style:
                      const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          _chip(w.statusLabel),
        ],
      ),
    );
  }

  Widget _transactionRow(VibeTransaction t) {
    final positive = t.amount >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            positive ? Icons.arrow_downward : Icons.arrow_upward,
            color: positive ? AppTheme.accent : Colors.white54,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                Text(
                  timeAgoLabel(t.createdAt),
                  style:
                      const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${positive ? '+' : ''}${formatPkr(t.amount)}',
                style: TextStyle(
                  color: positive ? AppTheme.accent : Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              _chip(t.status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  // ---------------------------------------------------------------
  // Withdrawal dialog (blueprint Section 3 journey)
  // ---------------------------------------------------------------

  Future<void> _showWithdrawDialog(
      BuildContext context, WalletBalances balances) async {
    final uid = AuthService.instance.uid;
    if (uid == null) return;
    // One idempotency key per dialog session: a double-tap or a
    // retried submit reuses it and can never create a duplicate
    // request (the service checks it before writing).
    final idempotencyKey =
        'wd_${uid}_${DateTime.now().microsecondsSinceEpoch}';
    final amountCtrl = TextEditingController();
    final accountCtrl = TextEditingController();
    var method = WalletRules.payoutMethods.first;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: const Text('Request withdrawal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available: ${formatPkr(balances.available)} • '
                  'Minimum: ${formatPkr(WalletRules.minWithdrawalPkr.toDouble())}',
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Amount (Rs)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  dropdownColor: AppTheme.card,
                  decoration: const InputDecoration(
                    hintText: 'Payout method',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                  items: WalletRules.payoutMethods
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setLocal(() => method = v ?? method),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: accountCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'Account number (e.g. 03XX-XXXXXXX)',
                    prefixIcon: Icon(Icons.phone_android_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your request will be recorded as Pending review. '
                  'No payout is sent automatically in test mode.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
                      setLocal(() => busy = true);
                      try {
                        await FirestoreService.instance.submitWithdrawal(
                          amount: amount,
                          payoutMethod: method,
                          payoutAccount: accountCtrl.text.trim(),
                          idempotencyKey: idempotencyKey,
                        );
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        _toast(
                            'Withdrawal request submitted. Status: Pending review.');
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setLocal(() => busy = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(e
                                .toString()
                                .replaceFirst('Exception: ', '')),
                          ),
                        );
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    accountCtrl.dispose();
  }
}
