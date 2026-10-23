import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_user.dart';
import 'package:vibeshort/screens/profile/public_profile_screen.dart';

/// A simple user list (followers / following) opened by tapping
/// a profile stat. Tapping a row opens that user's profile.
/// With [hidden] set, the list is replaced by a "Hidden by user"
/// note — the Following-list visibility preference (settings
/// pack) applied to someone else's profile.
class UserListScreen extends StatelessWidget {
  final String title;
  final Stream<List<VibeUser>> users;
  final bool hidden;

  const UserListScreen({
    super.key,
    required this.title,
    required this.users,
    this.hidden = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(title)),
      body: hidden
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 48, color: AppTheme.muted),
                    SizedBox(height: 12),
                    Text(
                      'Hidden by user',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'This user chose to keep this list private.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
            )
          : StreamBuilder<List<VibeUser>>(
              stream: users,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.accent));
                }
                final list = snap.data ?? const <VibeUser>[];
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Nothing to show yet.',
                        style: TextStyle(color: AppTheme.muted)),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final u = list[i];
                    final name = u.displayOrFallback;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.card,
                        backgroundImage: u.photoUrl.isNotEmpty
                            ? NetworkImage(u.photoUrl)
                            : null,
                        child: u.photoUrl.isEmpty
                            ? Text(
                                name.isNotEmpty
                                    ? name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700))
                            : null,
                      ),
                      title: Text(name,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text('@${u.username}',
                          style: const TextStyle(color: AppTheme.muted)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                PublicProfileScreen(uid: u.uid)),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
