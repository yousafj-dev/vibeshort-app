import 'package:cloud_firestore/cloud_firestore.dart';

/// Wallet constants from the blueprint (Sections 3 + 4): the
/// minimum payout and eligibility rules must be transparent and
/// published in the app BEFORE any real payout exists. Single
/// place to change them.
class WalletRules {
  WalletRules._();

  static const String currency = 'PKR';

  /// Minimum withdrawal request, in PKR.
  static const int minWithdrawalPkr = 500;

  /// Payout methods a withdrawal can be requested to. The account
  /// number itself is only ever stored as the request's payout
  /// reference (blueprint Section 8) — never shown to other users.
  static const List<String> payoutMethods = ['Easypaisa', 'JazzCash'];
}

/// Coins earning rules (approved Oct 27, 2026): users collect
/// COINS now; cash withdrawals open only after the Play Store
/// launch, once ad revenue starts, and payouts come only from
/// that revenue (see the in-app Earning Policy page). EVERY
/// reward number lives here so a rule change is a one-line edit.
///
/// Coin credits are written into the SAME ledger as everything
/// else, with the PKR amount converted at [coinsPerRupee] — so
/// the ledger-derived PKR balance and the coin balance can never
/// disagree, and 5,000 coins is exactly the Rs 500 minimum.
class CoinRules {
  CoinRules._();

  /// 1,000 coins = Rs 100, i.e. 10 coins = Rs 1.
  static const int coinsPerRupee = 10;

  /// Credited to the inviter once the invited friend has watched
  /// their first video to (near-)completion.
  static const int inviteRewardCoins = 100;

  /// Welcome coins for the invited friend, credited at the same
  /// qualification moment as the inviter reward.
  static const int welcomeRewardCoins = 50;

  /// Daily check-in reward, once per calendar day.
  static const int dailyCheckInCoins = 10;

  /// Per video watched to (near-)completion…
  static const int watchRewardCoins = 2;

  /// …up to this many coins per day from watching.
  static const int watchDailyCapCoins = 50;

  /// Minimum withdrawal expressed in coins (= Rs 500).
  static int get minWithdrawalCoins =>
      WalletRules.minWithdrawalPkr * coinsPerRupee;

  // Ledger entry types for coin credits.
  static const String typeReferralInviter = 'referral_inviter';
  static const String typeReferralWelcome = 'referral_welcome';
  static const String typeDailyCheckIn = 'daily_checkin';
  static const String typeWatchReward = 'watch_reward';

  static const Set<String> coinTypes = {
    typeReferralInviter,
    typeReferralWelcome,
    typeDailyCheckIn,
    typeWatchReward,
  };

  static bool isCoinType(String type) => coinTypes.contains(type);

  /// Ledger amount (PKR) stored for a credit of [coins] coins.
  static double pkrForCoins(int coins) => coins / coinsPerRupee;

  /// Coin balance derived from the ledger (same source of truth
  /// as the PKR balance): sums the coin-type credits that count
  /// (available + pending; reversed/rejected count to nothing).
  static int coinBalanceFromTransactions(List<VibeTransaction> txs) {
    var pkr = 0.0;
    for (final t in txs) {
      if (!isCoinType(t.type)) continue;
      if (t.status == 'available' || t.status == 'pending') {
        pkr += t.amount;
      }
    }
    return (pkr * coinsPerRupee).round();
  }

  /// Coins earned from invites only (the Earn screen stat).
  static int inviteCoinsFromTransactions(List<VibeTransaction> txs) {
    var pkr = 0.0;
    for (final t in txs) {
      if (t.type != typeReferralInviter) continue;
      if (t.status == 'available' || t.status == 'pending') {
        pkr += t.amount;
      }
    }
    return (pkr * coinsPerRupee).round();
  }
}

/// One entry in the transaction ledger, `vibeshort_transactions`.
///
/// THE LEDGER IS THE SOURCE OF TRUTH for all balances (blueprint
/// Sections 4 + 8): a balance is always derived by summing ledger
/// entries, never edited directly. Amounts are signed — credits
/// positive, withdrawal holds and payouts negative.
///
/// [status] is one of: pending | available | paid | reversed |
/// rejected (the exact lifecycle the blueprint prescribes).
class VibeTransaction {
  final String id;
  final String userId;

  /// 'reward' | 'referral_reward' | 'withdrawal' | 'adjustment',
  /// plus the coin credits: CoinRules.typeReferralInviter /
  /// typeReferralWelcome / typeDailyCheckIn / typeWatchReward
  /// (amount stored in PKR converted at CoinRules.coinsPerRupee).
  final String type;
  final double amount;
  final String currency;
  final String status;
  final String idempotencyKey;

  /// What this entry belongs to, e.g. a withdrawal request id or a
  /// campaign id — the audit trail reference.
  final String reference;
  final DateTime createdAt;

  const VibeTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.currency = WalletRules.currency,
    required this.status,
    this.idempotencyKey = '',
    this.reference = '',
    required this.createdAt,
  });

  factory VibeTransaction.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final raw = d['created_at'];
    return VibeTransaction(
      id: doc.id,
      userId: (d['user_id'] ?? '') as String,
      type: (d['type'] ?? '') as String,
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      currency: (d['currency'] ?? WalletRules.currency) as String,
      status: (d['status'] ?? '') as String,
      idempotencyKey: (d['idempotency_key'] ?? '') as String,
      reference: (d['reference'] ?? '') as String,
      createdAt: raw is Timestamp ? raw.toDate() : DateTime.now(),
    );
  }

  /// Short human label for the history list.
  String get label {
    switch (type) {
      case 'reward':
        return 'Creator reward';
      case 'referral_reward':
        return 'Referral reward';
      case CoinRules.typeReferralInviter:
        return 'Invite reward';
      case CoinRules.typeReferralWelcome:
        return 'Welcome bonus';
      case CoinRules.typeDailyCheckIn:
        return 'Daily check-in';
      case CoinRules.typeWatchReward:
        return 'Watch reward';
      case 'withdrawal':
        return 'Withdrawal';
      case 'adjustment':
        return 'Adjustment';
      default:
        return type.isEmpty ? 'Transaction' : type;
    }
  }

  /// True for coin credits (their history rows are shown in
  /// coins, not rupees).
  bool get isCoin => CoinRules.isCoinType(type);

  /// This entry expressed in coins (coin credits only).
  int get amountCoins => (amount * CoinRules.coinsPerRupee).round();
}

/// Balances DERIVED from ledger entries. This is the only way the
/// app computes a balance — the wallet doc's cached fields are a
/// cross-check copy, never the display source.
class WalletBalances {
  /// Rewards credited but not yet cleared for withdrawal.
  final double pending;

  /// Cleared funds that can be withdrawn right now (pending
  /// withdrawal holds already subtracted).
  final double available;

  /// Total successfully paid out, all time (positive number).
  final double paid;

  const WalletBalances({
    this.pending = 0,
    this.available = 0,
    this.paid = 0,
  });

  factory WalletBalances.fromTransactions(List<VibeTransaction> txs) {
    var pending = 0.0;
    var available = 0.0;
    var paid = 0.0;
    for (final t in txs) {
      switch (t.status) {
        case 'pending':
          if (t.type == 'withdrawal') {
            // A pending withdrawal HOLDS funds: its (negative)
            // amount reduces what is available until it is paid
            // out or rejected/reversed.
            available += t.amount;
          } else {
            pending += t.amount;
          }
          break;
        case 'available':
          available += t.amount;
          break;
        case 'paid':
          if (t.type == 'withdrawal') paid += -t.amount;
          break;
        default:
          // 'reversed' / 'rejected' entries stay in the ledger for
          // audit but count towards nothing.
          break;
      }
    }
    return WalletBalances(pending: pending, available: available, paid: paid);
  }
}

/// Cached wallet view, `vibeshort_wallets/{uid}` (blueprint
/// Section 8: "cached balance fields if needed; ledger remains
/// source of truth"). Written only alongside ledger writes.
class VibeWallet {
  final String userId;
  final String currency;
  final double cachedPending;
  final double cachedAvailable;
  final double cachedPaid;

  const VibeWallet({
    required this.userId,
    this.currency = WalletRules.currency,
    this.cachedPending = 0,
    this.cachedAvailable = 0,
    this.cachedPaid = 0,
  });

  factory VibeWallet.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return VibeWallet(
      userId: (d['user_id'] ?? doc.id) as String,
      currency: (d['currency'] ?? WalletRules.currency) as String,
      cachedPending: (d['cached_pending'] as num?)?.toDouble() ?? 0,
      cachedAvailable: (d['cached_available'] as num?)?.toDouble() ?? 0,
      cachedPaid: (d['cached_paid'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One withdrawal request, `vibeshort_withdrawal_requests`
/// (blueprint Section 8: id, user_id, amount, payout method
/// reference, status, review timestamps). Requests are created in
/// [statusPendingReview]; approval/rejection happens in the Admin
/// phase — the app never fakes an approval.
class VibeWithdrawal {
  static const String statusPendingReview = 'pending_review';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
  static const String statusPaid = 'paid';

  final String id;
  final String userId;
  final double amount;
  final String currency;
  final String payoutMethod;

  /// The Easypaisa/JazzCash account number the user asked to be
  /// paid to. Private: only ever read back by its owner here.
  final String payoutAccount;
  final String status;
  final String idempotencyKey;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const VibeWithdrawal({
    required this.id,
    required this.userId,
    required this.amount,
    this.currency = WalletRules.currency,
    required this.payoutMethod,
    required this.payoutAccount,
    required this.status,
    this.idempotencyKey = '',
    required this.createdAt,
    this.reviewedAt,
  });

  String get statusLabel {
    switch (status) {
      case statusApproved:
        return 'Approved';
      case statusRejected:
        return 'Rejected';
      case statusPaid:
        return 'Paid';
      case statusPendingReview:
      default:
        return 'Pending review';
    }
  }

  factory VibeWithdrawal.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final raw = d['created_at'];
    final rev = d['reviewed_at'];
    return VibeWithdrawal(
      id: doc.id,
      userId: (d['user_id'] ?? '') as String,
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      currency: (d['currency'] ?? WalletRules.currency) as String,
      payoutMethod: (d['payout_method'] ?? '') as String,
      payoutAccount: (d['payout_account'] ?? '') as String,
      status: (d['status'] ?? statusPendingReview) as String,
      idempotencyKey: (d['idempotency_key'] ?? '') as String,
      createdAt: raw is Timestamp ? raw.toDate() : DateTime.now(),
      reviewedAt: rev is Timestamp ? rev.toDate() : null,
    );
  }
}

/// One recorded referral, `vibeshort_referrals` (blueprint
/// Section 8: referrer_id, referred_user_id, code,
/// qualification_status, reward_transaction_id). Groundwork only:
/// a record starts as 'pending' and NO reward money is created by
/// this phase — qualification and rewards are decided later under
/// the published rules, with abuse checks (blueprint Section 4).
class VibeReferral {
  final String id;
  final String referrerId;
  final String referredUserId;
  final String code;

  /// 'pending' | 'qualified' | 'rejected'
  final String qualificationStatus;
  final String? rewardTransactionId;
  final DateTime createdAt;

  const VibeReferral({
    required this.id,
    required this.referrerId,
    required this.referredUserId,
    required this.code,
    this.qualificationStatus = 'pending',
    this.rewardTransactionId,
    required this.createdAt,
  });

  factory VibeReferral.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final raw = d['created_at'];
    return VibeReferral(
      id: doc.id,
      referrerId: (d['referrer_id'] ?? '') as String,
      referredUserId: (d['referred_user_id'] ?? '') as String,
      code: (d['code'] ?? '') as String,
      qualificationStatus: (d['qualification_status'] ?? 'pending') as String,
      rewardTransactionId: d['reward_transaction_id'] as String?,
      createdAt: raw is Timestamp ? raw.toDate() : DateTime.now(),
    );
  }
}

/// Formats a coin count with thousands separators, e.g. 1,250.
String formatCoins(int coins) {
  final sign = coins < 0 ? '-' : '';
  final digits = coins.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '$sign$buf';
}

/// The Rs equivalent of a coin count, e.g. "Rs 125".
String formatCoinsAsPkr(int coins) =>
    formatPkr(CoinRules.pkrForCoins(coins));

/// Formats a PKR amount the way the wallet shows it: whole rupees
/// with thousands separators, e.g. Rs 1,250.
String formatPkr(double amount) {
  final whole = amount.round();
  final sign = whole < 0 ? '-' : '';
  final digits = whole.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${sign}Rs $buf';
}
