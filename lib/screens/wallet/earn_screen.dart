import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_wallet.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/profile/help_pages.dart';
import 'package:vibeshort/screens/wallet/wallet_screen.dart';

/// Invite & Earn — the earning home (coins system, approved
/// Oct 27, 2026; numbers live in CoinRules).
///
/// Shows the coin balance (derived from the same ledger as the
/// Wallet) with its Rs equivalent, the user's invite code with
/// copy + share, invite stats, the daily check-in claim, how it
/// works, and the honest earning policy: coins are collected
/// now, cash withdrawals open only after the Play Store launch
/// and the start of ad revenue. No guaranteed-earnings language
/// anywhere on this screen.
class EarnScreen extends StatefulWidget {
  const EarnScreen({super.key});

  @override
  State<EarnScreen> createState() => _EarnScreenState();
}

class _EarnScreenState extends State<EarnScreen> {
  bool _claiming = false;

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

  Future<void> _claimCheckIn() async {
    setState(() => _claiming = true);
    final credited =
        await FirestoreService.instance.claimDailyCheckIn();
    if (!mounted) return;
    setState(() => _claiming = false);
    _toast(credited
        ? '+${CoinRules.dailyCheckInCoins} coins added. See you tomorrow!'
        : 'Already claimed today.');
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
      appBar: AppBar(title: const Text('Invite & Earn')),
      body: StreamBuilder<List<VibeTransaction>>(
        stream: fs.myTransactions(),
        builder: (context, txSnap) {
          final txs = txSnap.data ?? const <VibeTransaction>[];
          final coins = CoinRules.coinBalanceFromTransactions(txs);
          final inviteCoins =
              CoinRules.inviteCoinsFromTransactions(txs);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _balanceCard(coins),
              const SizedBox(height: 16),
              _checkInCard(),
              const SizedBox(height: 16),
              _inviteCard(inviteCoins),
              const SizedBox(height: 24),
              _sectionTitle('How it works'),
              const SizedBox(height: 8),
              _howItWorksCard(),
              const SizedBox(height: 24),
              _sectionTitle('Earning policy'),
              const SizedBox(height: 8),
              _policyCard(context),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WalletScreen()),
                ),
                icon: const Icon(Icons.account_balance_wallet_outlined,
                    size: 19),
                label: const Text('Open Wallet'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------

  Widget _balanceCard(int coins) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monetization_on_outlined,
                  color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text(
                'Your coins',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatCoins(coins),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '≈ ${formatCoinsAsPkr(coins)} • '
            '${formatCoins(CoinRules.coinsPerRupee * 100)} coins = '
            '${formatPkr(100)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Minimum withdrawal ${formatPkr(WalletRules.minWithdrawalPkr.toDouble())} '
            '= ${formatCoins(CoinRules.minWithdrawalCoins)} coins. '
            'Withdrawals open after the Play Store launch.',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _checkInCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined,
              color: AppTheme.accent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily check-in',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Get ${CoinRules.dailyCheckInCoins} coins every day.',
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          StreamBuilder<bool>(
            stream: FirestoreService.instance.dailyCheckInClaimed(),
            builder: (context, snap) {
              final claimed = snap.data ?? false;
              if (claimed) {
                return const Chip(
                  avatar: Icon(Icons.check, size: 16, color: Colors.white70),
                  label: Text('Claimed today'),
                  backgroundColor: Colors.white10,
                  labelStyle:
                      TextStyle(color: Colors.white70, fontSize: 12),
                  side: BorderSide.none,
                );
              }
              return ElevatedButton(
                onPressed: _claiming ? null : _claimCheckIn,
                child: _claiming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text('Claim +${CoinRules.dailyCheckInCoins}'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _inviteCard(int inviteCoins) {
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
          _sectionTitle('Your invite code'),
          const SizedBox(height: 8),
          StreamBuilder<String>(
            stream: fs.myReferralCode(),
            builder: (context, snap) {
              final code = snap.data ?? '';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            code.isEmpty ? '…' : code,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
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
                                  _toast('Invite code copied.');
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: code.isEmpty
                        ? null
                        : () => Share.share(
                            'Join me on VibeShort! Sign up with my invite '
                            'code $code — when you watch your first video, '
                            'we both earn coins.'),
                    icon: const Icon(Icons.share_outlined, size: 19),
                    label: const Text('Share invite'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<VibeReferral>>(
            stream: fs.myReferrals(),
            builder: (context, snap) {
              final list = snap.data ?? const <VibeReferral>[];
              final qualified = list
                  .where((r) => r.qualificationStatus == 'qualified')
                  .length;
              return Row(
                children: [
                  Expanded(
                    child: _stat('${list.length}', 'Friends joined'),
                  ),
                  Expanded(
                    child: _stat('$qualified', 'Completed'),
                  ),
                  Expanded(
                    child: _stat(formatCoins(inviteCoins),
                        'Coins from invites'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _howItWorksCard() {
    final steps = <(IconData, String)>[
      (
        Icons.share_outlined,
        'Share your invite code with friends.',
      ),
      (
        Icons.person_add_alt_1_outlined,
        'Your friend signs up with your code and watches their first video.',
      ),
      (
        Icons.monetization_on_outlined,
        'You get ${CoinRules.inviteRewardCoins} coins — and your friend '
            'gets ${CoinRules.welcomeRewardCoins} welcome coins.',
      ),
      (
        Icons.play_circle_outline,
        'Keep earning: ${CoinRules.dailyCheckInCoins} coins for the daily '
            'check-in and ${CoinRules.watchRewardCoins} coins per video '
            'watched (up to ${CoinRules.watchDailyCapCoins} a day).',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: steps
            .map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(s.$1, color: AppTheme.accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.$2,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4),
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

  Widget _policyCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: AppTheme.accent, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Coins are being collected now. Cash withdrawals open '
                  'after VibeShort launches on the Play Store and ad '
                  'revenue starts — payouts come only from that '
                  'revenue. Minimum withdrawal '
                  'Rs 500 (5,000 coins) to Easypaisa / JazzCash. '
                  'Earnings are never guaranteed.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const EarningPolicyScreen()),
            ),
            child: const Text('Read the full Earning Policy'),
          ),
        ],
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
}
