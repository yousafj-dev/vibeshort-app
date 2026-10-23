import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_user.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_common.dart';

/// User management (blueprint Section 5): search accounts, see
/// account status, suspend / restore with a recorded reason.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _query = '';
  bool _busy = false;

  Future<void> _suspend(VibeUser user) async {
    final reason = await promptText(
      context,
      title: 'Suspend @${user.username}',
      label: 'Suspension reason',
      hint: 'Shown to the user on the suspended screen',
      confirmLabel: 'Suspend',
    );
    if (reason == null || !mounted) return;
    await runAdminAction(
      context,
      action: () => FirestoreService.instance
          .suspendUser(user.uid, reason: reason),
      successMessage: '@${user.username} suspended.',
      setBusy: (b) => setState(() => _busy = b),
    );
  }

  Future<void> _restore(VibeUser user) async {
    final ok = await confirmAction(
      context,
      title: 'Restore @${user.username}?',
      message: 'The account becomes active again and can post.',
      confirmLabel: 'Restore',
    );
    if (!ok || !mounted) return;
    await runAdminAction(
      context,
      action: () => FirestoreService.instance.restoreUser(user.uid),
      successMessage: '@${user.username} restored.',
      setBusy: (b) => setState(() => _busy = b),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('User management')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search name, username or email',
                prefixIcon: Icon(Icons.search, color: AppTheme.muted),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<VibeUser>>(
              stream: FirestoreService.instance.allUsers(limit: 500),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.accent));
                }
                var users = snap.data ?? const <VibeUser>[];
                if (_query.isNotEmpty) {
                  users = users
                      .where((u) =>
                          u.username.toLowerCase().contains(_query) ||
                          u.displayName.toLowerCase().contains(_query) ||
                          u.email.toLowerCase().contains(_query))
                      .toList();
                }
                users = [...users]..sort((a, b) {
                    if (a.isSuspended != b.isSuspended) {
                      return a.isSuspended ? -1 : 1;
                    }
                    return a.username.compareTo(b.username);
                  });
                if (users.isEmpty) {
                  return const Center(
                    child: Text('No accounts match.',
                        style: TextStyle(color: AppTheme.muted)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: users.length,
                  itemBuilder: (context, i) => _tile(users[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(VibeUser u) {
    final isMe = u.uid == AuthService.instance.uid;
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
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.bg,
                backgroundImage:
                    u.photoUrl.isNotEmpty ? NetworkImage(u.photoUrl) : null,
                child: u.photoUrl.isEmpty
                    ? Text(
                        u.displayOrFallback.isNotEmpty
                            ? u.displayOrFallback[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.username.isNotEmpty
                          ? '@${u.username}'
                          : u.displayOrFallback,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700),
                    ),
                    if (u.email.isNotEmpty)
                      Text(u.email,
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (u.isAdmin)
                const StatusChip('Admin', AppTheme.accent2),
              const SizedBox(width: 6),
              StatusChip(
                u.isSuspended ? 'Suspended' : 'Active',
                u.isSuspended
                    ? const Color(0xFFFF5C7A)
                    : const Color(0xFF3DDC84),
              ),
            ],
          ),
          if (u.isSuspended && u.suspensionReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Reason: ${u.suspensionReason}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13)),
          ],
          if (!isMe) ...[
            const SizedBox(height: 10),
            if (u.isSuspended)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _restore(u),
                icon: const Icon(Icons.restart_alt, size: 17),
                label: const Text('Restore account'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24)),
              )
            else
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _suspend(u),
                icon: const Icon(Icons.block, size: 17),
                label: const Text('Suspend account'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF5C7A),
                    side: const BorderSide(color: Color(0xFFFF5C7A))),
              ),
          ],
        ],
      ),
    );
  }
}
