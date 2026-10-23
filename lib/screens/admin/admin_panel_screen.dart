import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_audit_screen.dart';
import 'package:vibeshort/screens/admin/admin_referrals_screen.dart';
import 'package:vibeshort/screens/admin/admin_reports_screen.dart';
import 'package:vibeshort/screens/admin/admin_settings_screen.dart';
import 'package:vibeshort/screens/admin/admin_users_screen.dart';
import 'package:vibeshort/screens/admin/admin_videos_screen.dart';
import 'package:vibeshort/screens/admin/admin_withdrawals_screen.dart';

/// Admin panel home (Phase 4, blueprint Section 5): a dashboard
/// summary plus one entry per module. This screen is only
/// reachable when the signed-in user's Firestore doc carries
/// role == 'admin' (the entry point is hidden otherwise, and
/// every service action re-verifies the role).
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late Future<Map<String, int>> _totals;

  @override
  void initState() {
    super.initState();
    _totals = FirestoreService.instance.adminDashboardTotals();
  }

  void _refresh() {
    setState(() {
      _totals = FirestoreService.instance.adminDashboardTotals();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Admin panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Platform moderation & management',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, int>>(
            future: _totals,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accent)),
                );
              }
              if (snap.hasError) {
                return Text(
                  snap.error
                      .toString()
                      .replaceFirst('Exception: ', ''),
                  style: const TextStyle(color: AppTheme.muted),
                );
              }
              final t = snap.data ?? const {};
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.4,
                children: [
                  _totalCard('${t['users'] ?? 0}', 'Total users'),
                  _totalCard('${t['videos'] ?? 0}', 'Total videos'),
                  _totalCard('${t['views'] ?? 0}', 'Total views'),
                  _totalCard('${t['openReports'] ?? 0}', 'Open reports'),
                  _totalCard(
                      '${t['pendingWithdrawals'] ?? 0}', 'Pending payouts'),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _moduleTile(
            icon: Icons.flag_outlined,
            title: 'Reports queue',
            subtitle: 'Review and resolve user reports',
            screen: const AdminReportsScreen(),
          ),
          _moduleTile(
            icon: Icons.ondemand_video_outlined,
            title: 'Video moderation',
            subtitle: 'Keep or remove reported videos',
            screen: const AdminVideosScreen(),
          ),
          _moduleTile(
            icon: Icons.people_outline,
            title: 'User management',
            subtitle: 'Search, suspend and restore accounts',
            screen: const AdminUsersScreen(),
          ),
          _moduleTile(
            icon: Icons.payments_outlined,
            title: 'Withdrawals',
            subtitle: 'Approve or reject payout requests',
            screen: const AdminWithdrawalsScreen(),
          ),
          _moduleTile(
            icon: Icons.group_add_outlined,
            title: 'Referral controls',
            subtitle: 'Track referrals and flag abuse',
            screen: const AdminReferralsScreen(),
          ),
          _moduleTile(
            icon: Icons.settings_outlined,
            title: 'App settings',
            subtitle: 'Maintenance notice shown in the app',
            screen: const AdminSettingsScreen(),
          ),
          _moduleTile(
            icon: Icons.receipt_long_outlined,
            title: 'Audit log',
            subtitle: 'Every admin action, recorded',
            screen: const AdminAuditScreen(),
          ),
        ],
      ),
    );
  }

  Widget _totalCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _moduleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget screen,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListTile(
          leading: Icon(icon, color: AppTheme.accent),
          title: Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
          trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => screen),
          ),
        ),
      ),
    );
  }
}
