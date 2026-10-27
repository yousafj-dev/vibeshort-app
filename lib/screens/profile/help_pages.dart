import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';

/// Static support pages (settings pack): Help Center FAQ,
/// Privacy Policy and Terms. Short, honest text written for
/// what the app actually does today — no boilerplate promises.

class _StaticPage extends StatelessWidget {
  final String title;
  final List<(String, String)> sections;

  const _StaticPage({required this.title, required this.sections});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final (heading, body) in sections) ...[
            Text(
              heading,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                  color: Colors.white70, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _StaticPage(
      title: 'Help Center',
      sections: [
        (
          'How do I post a video?',
          'Tap the + button at the bottom, record with the in-app camera or pick a clip from your gallery, add a caption (use #hashtags so people can find it), then post. You can add filters, effects, music and text before posting.'
        ),
        (
          'Why is my Wallet balance Rs 0?',
          'Your balance grows from the coins you earn (invites, daily check-in, watching videos) — 1,000 coins = Rs 100. Every coin is recorded in the Wallet ledger so it can be checked. Cash withdrawals open only after VibeShort launches on the Play Store and ad revenue starts; see Invite & Earn → Earning Policy for the full rules.'
        ),
        (
          'How do I report a video or a user?',
          'On a video, tap "More" (the ⋮ button) and choose Report video. On a profile, use the ⋮ menu and choose Report user. The VibeShort team reviews reports and can remove videos or suspend accounts.'
        ),
        (
          'What does a private account do?',
          'With a private account (Settings and privacy → Private account), your videos leave the For You feed and Discover for everyone except you and your followers. People can still find your profile and follow you.'
        ),
        (
          'How do I delete my account?',
          'Go to Settings and privacy → Delete account. Your profile, your videos and your watch history are removed from the app and your login is deleted. This cannot be undone.'
        ),
        (
          'A video is stuck or will not play',
          'Check your connection, or turn on Data Saver (Settings and privacy → Data Saver) for a lighter stream. If one video never plays, it may have been removed by moderation.'
        ),
      ],
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _StaticPage(
      title: 'Privacy Policy',
      sections: [
        (
          'What we store',
          'Your account information (name, username, email, profile photo and bio), the videos and comments you post, your likes, follows, watch history, reports and your in-app settings. This data is stored in Google Firebase (the quizistan-academy project) under the vibeshort_users and vibeshort_videos collections.'
        ),
        (
          'Video files',
          'Video files and profile photos are stored with Cloudinary, our media host. When you delete a video or your account, the app removes its records from VibeShort; media files already delivered to Cloudinary are handled under their retention policies.'
        ),
        (
          'What stays on your phone',
          'Offline videos you save, your Data Saver choice and your login session are stored on your device only. Clearing the app cache does not delete your offline videos.'
        ),
        (
          'Wallet data',
          'The Wallet runs in test mode: balances and withdrawal requests are bookkeeping records inside the app. No real payment details are collected and no real money is transferred.'
        ),
        (
          'Sharing',
          'We do not sell your personal information. Your public profile (name, username, photo, bio and videos) is visible to other VibeShort users unless your account is private.'
        ),
        (
          'Your control',
          'You can edit your profile, block users, switch your account to private, or delete your account and its app-side data at any time from Settings and privacy.'
        ),
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _StaticPage(
      title: 'Terms and Policies',
      sections: [
        (
          'Your account',
          'You are responsible for your account and for everything posted from it. Keep your password private. One person, one account; fake or impersonating accounts can be suspended.'
        ),
        (
          'Your content',
          'You keep ownership of the videos you post and give VibeShort permission to store and show them inside the app. Do not post content that is illegal, harmful, hateful, or that you do not have the right to share (including other people\'s copyrighted videos).'
        ),
        (
          'Moderation',
          'Reported content is reviewed by the VibeShort team. Videos can be removed and accounts can be suspended, with the reason recorded, when these terms or community safety require it.'
        ),
        (
          'Wallet and rewards',
          'Coins and Wallet balances are ledger records inside the app. They are not money and not a payment promise. Cash withdrawals open only after the Play Store launch and the start of ad revenue, under the Earning Policy shown in the app (Invite & Earn → Earning Policy). Earnings are never guaranteed.'
        ),
        (
          'Availability',
          'VibeShort is provided as-is while it grows. Features may change, and the service may be paused for maintenance with a notice in the app.'
        ),
      ],
    );
  }
}

class EarningPolicyScreen extends StatelessWidget {
  const EarningPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _StaticPage(
      title: 'Earning Policy',
      sections: [
        (
          'What coins are',
          'Coins are reward points inside VibeShort. You collect them in your Wallet, and every coin is recorded in your transaction ledger so your balance can always be checked. 1,000 coins = Rs 100 (10 coins = Rs 1). Coins are not money and cannot be transferred to another account.'
        ),
        (
          'How to earn coins',
          'Invite a friend: when a friend signs up with your invite code AND watches their first video, you get 100 coins and your friend gets 50 welcome coins. Daily check-in: 10 coins once a day. Watching videos: 2 coins per video watched, up to 50 coins a day from watching.'
        ),
        (
          'When cash withdrawals open',
          'You can collect coins from today. Cash withdrawals open only AFTER VibeShort launches on the Play Store and advertising revenue starts coming in. Until then, withdrawal requests can be recorded in the Wallet but no cash is paid out.'
        ),
        (
          'Where the money comes from',
          'Payouts are made only from VibeShort\'s advertising revenue. If there is no revenue, there is no payout — earnings are never guaranteed, and no reward shown in the app is a promise of payment.'
        ),
        (
          'Withdrawal rules',
          'Minimum withdrawal is Rs 500 (5,000 coins), paid to Easypaisa or JazzCash. Only your available balance can be withdrawn. Every request is reviewed manually before any payout is made, and a rejected request returns the held amount to your balance.'
        ),
        (
          'Fair use',
          'Self-referrals, fake accounts, multiple accounts on one device and any trick used to farm coins do not qualify and can have their coins removed. An invite reward is paid only after the invited friend has really joined and watched a video.'
        ),
        (
          'Changes',
          'Coin rates and rules are published in the app and may change as the app grows. Any change will be announced in the app before it applies.'
        ),
      ],
    );
  }
}
