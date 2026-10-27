import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_panel_screen.dart';
import 'package:vibeshort/screens/auth/auth_screen.dart';
import 'package:vibeshort/screens/profile/activity_center_screen.dart';
import 'package:vibeshort/screens/profile/creator_dashboard_screen.dart';
import 'package:vibeshort/screens/profile/offline_videos_screen.dart';
import 'package:vibeshort/screens/profile/qr_code_screen.dart';
import 'package:vibeshort/screens/profile/settings_screen.dart';
import 'package:vibeshort/screens/wallet/earn_screen.dart';
import 'package:vibeshort/screens/wallet/wallet_screen.dart';

/// The profile side menu (☰ on My Profile), TikTok layout:
/// Wallet / Activity center / Offline videos / Your QR code /
/// Creator dashboard / Settings and privacy — plus the Admin
/// panel for admins and Log out. Only real features are listed.
class ProfileMenuScreen extends StatelessWidget {
  const ProfileMenuScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await context.read<AuthService>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _item(
            context,
            icon: Icons.monetization_on_outlined,
            label: 'Invite & Earn',
            subtitle: 'Invite friends, collect coins',
            screen: const EarnScreen(),
          ),
          _item(
            context,
            icon: Icons.account_balance_wallet_outlined,
            label: 'Wallet',
            subtitle: 'Balance, withdrawals and referrals',
            screen: const WalletScreen(),
          ),
          _item(
            context,
            icon: Icons.history,
            label: 'Activity center',
            subtitle: 'Liked videos and watch history',
            screen: const ActivityCenterScreen(),
          ),
          _item(
            context,
            icon: Icons.offline_pin_outlined,
            label: 'Offline videos',
            subtitle: 'Videos saved on this device',
            screen: const OfflineVideosScreen(),
          ),
          _item(
            context,
            icon: Icons.qr_code_2,
            label: 'Your QR code',
            subtitle: 'Share your profile with a code',
            screen: const QrCodeScreen(),
          ),
          _item(
            context,
            icon: Icons.insights_outlined,
            label: 'Creator dashboard',
            subtitle: 'Your videos, likes, followers and views',
            screen: const CreatorDashboardScreen(),
          ),
          _item(
            context,
            icon: Icons.settings_outlined,
            label: 'Settings and privacy',
            subtitle: 'Account, security, privacy and more',
            screen: const SettingsScreen(),
          ),
          // Admin panel entry — admins only (existing Phase 4 rule).
          StreamBuilder<bool>(
            stream: FirestoreService.instance.myIsAdmin(),
            builder: (context, snap) {
              if (snap.data != true) return const SizedBox.shrink();
              return _item(
                context,
                icon: Icons.shield_outlined,
                label: 'Admin panel',
                subtitle: 'Moderation, users, payouts, audit log',
                screen: const AdminPanelScreen(),
                accent: true,
              );
            },
          ),
          const Divider(color: Colors.white10, height: 24),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFFF5C7A)),
            title: const Text('Log out',
                style: TextStyle(color: Color(0xFFFF5C7A))),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Widget screen,
    bool accent = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: accent ? AppTheme.accent : Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      subtitle:
          Text(subtitle, style: const TextStyle(color: AppTheme.muted)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      ),
    );
  }
}
