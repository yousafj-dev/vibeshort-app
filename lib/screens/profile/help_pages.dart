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
              style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                  color: AppTheme.text.withOpacity(0.7), height: 1.5, fontSize: 14),
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
          'Your balance grows from the coins you earn (invites, daily check-in, watching videos) — 1,000 coins = Rs 100. Every coin is recorded in the Wallet ledger so it can be checked. Once you reach the Rs 500 minimum (5,000 coins), you can withdraw to Easypaisa, JazzCash or your bank account — requests are reviewed first, then the money is sent to your account. See Invite & Earn → Earning Policy for the full rules.'
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
          'Your Wallet balance, coin ledger and withdrawal requests are stored inside the app. When you request a withdrawal, the payout account title and number (or IBAN) you enter are stored with the request so it can be reviewed and paid.'
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
          'Every action earns the coins shown in the app — watching, invites and daily check-ins are credited to your Wallet automatically, and every coin is recorded in your ledger so your balance can always be checked. Cash withdrawals are made under the Earning Policy shown in the app (Invite & Earn → Earning Policy): once you reach the minimum, you can request a withdrawal to Easypaisa, JazzCash or your bank account, and requests are reviewed before any payout is sent.'
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
          'Cash withdrawals',
          'You can collect coins from today, and cash withdrawals are open. Once your available balance reaches the Rs 500 minimum (5,000 coins), request a withdrawal from the Wallet to your Easypaisa, JazzCash or bank account. Every request is reviewed first; once it is approved, the money is sent to the account you gave.'
        ),
        (
          'Your balance',
          'Every coin you earn is credited to your Wallet ledger as you earn it — your recorded balance stays yours and can be checked in the app at any time.'
        ),
        (
          'Withdrawal rules',
          'Minimum withdrawal is Rs 500 (5,000 coins), paid to Easypaisa, JazzCash or your bank account. Only your available balance can be withdrawn. Every request is reviewed manually before any payout is made, and a rejected request returns the held amount to your balance.'
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
