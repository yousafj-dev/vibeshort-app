import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_user.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/services/offline_service.dart';
import 'package:vibeshort/services/prefs_service.dart';
import 'package:vibeshort/screens/admin/admin_panel_screen.dart';
import 'package:vibeshort/screens/auth/auth_screen.dart';
import 'package:vibeshort/screens/profile/blocked_accounts_screen.dart';
import 'package:vibeshort/screens/profile/edit_profile_screen.dart';
import 'package:vibeshort/screens/profile/help_pages.dart';

/// Settings and privacy (settings pack), TikTok-style grouped
/// list: Account / Security / Privacy / Interactions /
/// In-app notifications / Cache & data / Support & about /
/// Login. Preferences are REAL: privacy + notification +
/// visibility prefs live on my `vibeshort_users` doc, Data Saver
/// is a device pref, and every row does what it says.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _dataSaver = PrefsService.dataSaver;
  int? _cacheBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    try {
      final tmp = await getTemporaryDirectory();
      var total = await _dirSize(tmp);
      total += await OfflineService.totalSizeBytes();
      if (mounted) setState(() => _cacheBytes = total);
    } catch (_) {
      if (mounted) setState(() => _cacheBytes = 0);
    }
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    if (await dir.exists()) {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    }
    return total;
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      final tmp = await getTemporaryDirectory();
      if (await tmp.exists()) {
        await for (final e in tmp.list()) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      _snack('Cache cleared. Offline videos were not touched.');
    } catch (_) {
      _snack('Could not clear the cache.');
    }
    if (!mounted) return;
    setState(() => _clearing = false);
    _loadCacheSize();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _err(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _setPref(Map<String, dynamic> fields) async {
    try {
      await FirestoreService.instance.updateMySettings(fields);
    } catch (e) {
      _snack(_err(e));
    }
  }

  // ---------------------------------------------------------------
  // Security actions
  // ---------------------------------------------------------------

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pwField(current, 'Current password'),
            const SizedBox(height: 10),
            _pwField(next, 'New password (min 6 characters)'),
            const SizedBox(height: 10),
            _pwField(confirm, 'Confirm new password'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (next.text != confirm.text) {
      _snack('New passwords do not match.');
      return;
    }
    try {
      await AuthService.instance.changePassword(
        currentPassword: current.text,
        newPassword: next.text,
      );
      _snack('Password changed.');
    } catch (e) {
      _snack(_err(e));
    }
  }

  Widget _pwField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      obscureText: true,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.muted),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    // Double confirm, then a password prompt (Firebase needs a
    // fresh login before it will delete the user).
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Delete your account?'),
        content: const Text(
            'Your profile, your videos, your watch history and your login will be deleted. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue',
                style: TextStyle(color: Color(0xFFFF5C7A))),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final pw = TextEditingController();
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Confirm with your password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Enter your current password to permanently delete this account.',
                style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 10),
            _pwField(pw, 'Current password'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete my account',
                style: TextStyle(color: Color(0xFFFF5C7A))),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;
    try {
      final auth = AuthService.instance;
      await auth.reauthenticate(pw.text);
      await FirestoreService.instance.deleteMyAccountData();
      await auth.deleteCurrentUser();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _logout({required bool confirmed}) async {
    if (!confirmed) {
      final ok = await showDialog<bool>(
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
      if (ok != true || !mounted) return;
    }
    await context.read<AuthService>().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _pickVisibility({
    required String title,
    required String current,
    required String field,
  }) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const ['Everyone', 'Only me'])
              RadioListTile<String>(
                value: option,
                groupValue: current,
                activeColor: AppTheme.accent,
                title: Text(option,
                    style: const TextStyle(color: Colors.white)),
                onChanged: (v) => Navigator.of(ctx).pop(v),
              ),
          ],
        ),
      ),
    );
    if (choice != null && choice != current) {
      await _setPref({field: choice});
    }
  }

  // ---------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(
            child: Text('Please log in.',
                style: TextStyle(color: AppTheme.muted))),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Settings and privacy')),
      body: StreamBuilder<VibeUser?>(
        stream: FirestoreService.instance.userProfile(uid),
        builder: (context, snap) {
          final profile = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              _group('ACCOUNT', [
                _row(
                  icon: Icons.badge_outlined,
                  label: 'Account information',
                  subtitle: 'Email, name, username and user ID',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => _AccountInfoScreen(profile: profile)),
                  ),
                ),
                _row(
                  icon: Icons.edit_outlined,
                  label: 'Edit profile',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const EditProfileScreen()),
                  ),
                ),
              ]),
              _group('SECURITY', [
                _row(
                  icon: Icons.lock_outline,
                  label: 'Change password',
                  onTap: _changePassword,
                ),
                _row(
                  icon: Icons.delete_forever_outlined,
                  label: 'Delete account',
                  danger: true,
                  onTap: _deleteAccount,
                ),
              ]),
              _group('PRIVACY', [
                SwitchListTile(
                  secondary: const Icon(Icons.lock_outline,
                      color: Colors.white),
                  title: const Text('Private account',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Only your followers see your videos in feeds and Discover',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
                  value: profile?.isPrivate ?? false,
                  activeColor: AppTheme.accent,
                  onChanged: (v) => _setPref({'isPrivate': v}),
                ),
                _row(
                  icon: Icons.block,
                  label: 'Blocked accounts',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const BlockedAccountsScreen()),
                  ),
                ),
              ]),
              _group('INTERACTIONS', [
                _row(
                  icon: Icons.favorite_border,
                  label: 'Who can see my liked videos',
                  value: profile?.likedVisibility ?? 'Everyone',
                  onTap: () => _pickVisibility(
                    title: 'Liked videos visibility',
                    current: profile?.likedVisibility ?? 'Everyone',
                    field: 'likedVisibility',
                  ),
                ),
                _row(
                  icon: Icons.people_outline,
                  label: 'Who can see my following list',
                  value: profile?.followingVisibility ?? 'Everyone',
                  onTap: () => _pickVisibility(
                    title: 'Following list visibility',
                    current: profile?.followingVisibility ?? 'Everyone',
                    field: 'followingVisibility',
                  ),
                ),
              ]),
              _group('IN-APP NOTIFICATIONS', [
                _switch(
                  icon: Icons.favorite_border,
                  label: 'Likes',
                  value: profile?.notifLikes ?? true,
                  field: 'notifLikes',
                ),
                _switch(
                  icon: Icons.mode_comment_outlined,
                  label: 'Comments',
                  value: profile?.notifComments ?? true,
                  field: 'notifComments',
                ),
                _switch(
                  icon: Icons.person_add_alt_outlined,
                  label: 'Follows',
                  value: profile?.notifFollows ?? true,
                  field: 'notifFollows',
                ),
              ]),
              _group('CACHE & DATA', [
                SwitchListTile(
                  secondary: const Icon(Icons.data_saver_on_outlined,
                      color: Colors.white),
                  title: const Text('Data Saver',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Play a lighter 540p stream in the feed',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
                  value: _dataSaver,
                  activeColor: AppTheme.accent,
                  onChanged: (v) async {
                    setState(() => _dataSaver = v);
                    await PrefsService.setDataSaver(v);
                  },
                ),
                _row(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Free up space',
                  subtitle: _cacheBytes == null
                      ? 'Cache and offline videos on this device'
                      : 'Using ${_formatBytes(_cacheBytes!)} (cache + offline videos)',
                  onTap: _clearing ? null : _clearCache,
                  trailing: _clearing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Clear cache',
                          style: TextStyle(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w700)),
                ),
              ]),
              _group('SUPPORT & ABOUT', [
                _row(
                  icon: Icons.help_outline,
                  label: 'Help Center',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const HelpCenterScreen()),
                  ),
                ),
                _row(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen()),
                  ),
                ),
                _row(
                  icon: Icons.description_outlined,
                  label: 'Terms and Policies',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TermsScreen()),
                  ),
                ),
                _row(
                  icon: Icons.info_outline,
                  label: 'About',
                  value: 'VibeShort · Version 1.0.0',
                ),
              ]),
              // Admin panel entry — admins only (existing Phase 4 rule).
              StreamBuilder<bool>(
                stream: FirestoreService.instance.myIsAdmin(),
                builder: (context, snap) {
                  if (snap.data != true) return const SizedBox.shrink();
                  return _group('ADMINISTRATION', [
                    _row(
                      icon: Icons.shield_outlined,
                      label: 'Admin panel',
                      subtitle: 'Moderation, users, payouts, audit log',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AdminPanelScreen()),
                      ),
                    ),
                  ]);
                },
              ),
              _group('LOGIN', [
                _row(
                  icon: Icons.switch_account_outlined,
                  label: 'Switch account',
                  onTap: () => _logout(confirmed: true),
                ),
                _row(
                  icon: Icons.logout,
                  label: 'Log out',
                  danger: true,
                  onTap: () => _logout(confirmed: false),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _group(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: rows),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    String? subtitle,
    String? value,
    bool danger = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final color = danger ? const Color(0xFFFF5C7A) : Colors.white;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style:
                  const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
      trailing: trailing ??
          (value != null
              ? Text(value,
                  style: const TextStyle(color: AppTheme.muted))
              : (onTap != null
                  ? const Icon(Icons.chevron_right, color: AppTheme.muted)
                  : null)),
      onTap: onTap,
    );
  }

  Widget _switch({
    required IconData icon,
    required String label,
    required bool value,
    required String field,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      value: value,
      activeColor: AppTheme.accent,
      onChanged: (v) => _setPref({field: v}),
    );
  }
}

/// Read-only account information rows (Settings → Account).
class _AccountInfoScreen extends StatelessWidget {
  final VibeUser? profile;

  const _AccountInfoScreen({required this.profile});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final rows = <(String, String)>[
      ('Email', profile?.email.isNotEmpty == true ? profile!.email : (auth.email ?? '—')),
      ('Display name', profile?.displayOrFallback ?? auth.displayName),
      ('Username', profile?.username.isNotEmpty == true ? '@${profile!.username}' : '—'),
      ('User ID', auth.uid ?? '—'),
    ];
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Account information')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (final (label, value) in rows)
                  ListTile(
                    title: Text(label,
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 13)),
                    subtitle: Text(value,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'To change your name, username or photo, use Edit profile.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
