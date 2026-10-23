import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_panel_screen.dart';
import 'package:vibeshort/screens/auth/auth_screen.dart';

/// Simple settings: account info + the app's only Log out.
/// Phase 4: admins also get the Admin panel entry here — it is
/// rendered only while the signed-in user's role is 'admin'.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
    final auth = context.watch<AuthService>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Account',
              style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.email_outlined, color: Colors.white),
                  title: const Text('Email',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                  subtitle: Text(auth.email ?? '—',
                      style: const TextStyle(color: Colors.white)),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.person_outline, color: Colors.white),
                  title: const Text('Name',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                  subtitle: Text(auth.displayName,
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Phase 4: Admin panel entry — admins only.
          StreamBuilder<bool>(
            stream: FirestoreService.instance.myIsAdmin(),
            builder: (context, snap) {
              if (snap.data != true) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Administration',
                      style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.shield_outlined,
                          color: AppTheme.accent),
                      title: const Text('Admin panel',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                          'Moderation, users, payouts, audit log',
                          style: TextStyle(
                              color: AppTheme.muted, fontSize: 12.5)),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppTheme.muted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AdminPanelScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              );
            },
          ),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout, size: 19),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF5C7A),
              minimumSize: const Size.fromHeight(50),
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text('VibeShort v1.0.0 — Phase 4',
                style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
