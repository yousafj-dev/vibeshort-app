import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_user.dart';
import 'package:vibeshort/services/firestore_service.dart';

/// Blocked accounts (Settings → Privacy): everyone I blocked
/// (Phase 4 blocking), each with an Unblock button. A blocked
/// creator's videos stay out of my feeds until I unblock them.
class BlockedAccountsScreen extends StatelessWidget {
  const BlockedAccountsScreen({super.key});

  Future<void> _unblock(BuildContext context, VibeUser user) async {
    try {
      await FirestoreService.instance.unblockUser(user.uid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('@${user.username} unblocked.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Blocked accounts')),
      body: StreamBuilder<List<VibeUser>>(
        stream: FirestoreService.instance.blockedUsers(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final users = snap.data ?? const <VibeUser>[];
          if (users.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'You have not blocked anyone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, i) {
              final u = users[i];
              final name = u.displayOrFallback;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.card,
                  backgroundImage:
                      u.photoUrl.isNotEmpty ? NetworkImage(u.photoUrl) : null,
                  child: u.photoUrl.isEmpty
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700))
                      : null,
                ),
                title: Text(name,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text('@${u.username}',
                    style: const TextStyle(color: AppTheme.muted)),
                trailing: OutlinedButton(
                  onPressed: () => _unblock(context, u),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text('Unblock'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
