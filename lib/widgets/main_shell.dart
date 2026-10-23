import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_moderation.dart';
import 'package:vibeshort/models/vibe_user.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/auth/auth_screen.dart';
import 'package:vibeshort/screens/discover/discover_screen.dart';
import 'package:vibeshort/screens/home/home_screen.dart';
import 'package:vibeshort/screens/inbox/inbox_screen.dart';
import 'package:vibeshort/screens/profile/profile_screen.dart';
import 'package:vibeshort/screens/upload/upload_screen.dart';

/// Bottom-nav shell (TikTok style, 5 tabs):
/// Home | Discover | Create (+) | Inbox | Profile.
/// The Inbox icon carries a live unread-notification badge.
///
/// Phase 4 wraps the shell in two safety gates (blueprint
/// Sections 5 + 9): a suspended account gets a full-screen
/// suspended state instead of the app, and an admin-enabled
/// maintenance notice shows as a banner to normal users.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.uid;
    if (uid == null) return _shell();
    return StreamBuilder<VibeUser?>(
      stream: FirestoreService.instance.userProfile(uid),
      builder: (context, snap) {
        final profile = snap.data;
        if (profile != null && profile.isSuspended) {
          return _suspendedScreen(profile);
        }
        return _shell(isAdmin: profile?.isAdmin ?? false);
      },
    );
  }

  Widget _shell({bool isAdmin = false}) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          if (!isAdmin) _maintenanceBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                const HomeScreen(),
                const DiscoverScreen(),
                UploadScreen(onPosted: () => setState(() => _index = 0)),
                InboxScreen(active: _index == 3),
                const ProfileScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: Container(
              width: 46,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 22),
            ),
            label: 'Create',
          ),
          BottomNavigationBarItem(
            icon: _inboxIcon(active: false),
            activeIcon: _inboxIcon(active: true),
            label: 'Inbox',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  /// The admin-controlled maintenance notice (Phase 4): visible
  /// to normal users only, never to the admin who set it.
  Widget _maintenanceBanner() {
    return StreamBuilder<VibeSettings>(
      stream: FirestoreService.instance.appSettings(),
      builder: (context, snap) {
        final s = snap.data;
        if (s == null ||
            !s.maintenanceOn ||
            s.maintenanceNotice.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          color: const Color(0xFFFFB340),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 14,
            right: 14,
            bottom: 9,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.campaign_outlined,
                  size: 18, color: Colors.black87),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.maintenanceNotice.trim(),
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Full-screen state for a suspended account (blueprint Section
  /// 9): the reason recorded by the admin is shown, and the only
  /// action is Log out.
  Widget _suspendedScreen(VibeUser profile) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 64, color: Color(0xFFFF5C7A)),
              const SizedBox(height: 18),
              const Text(
                'Account suspended',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                profile.suspensionReason.isNotEmpty
                    ? 'Reason: ${profile.suspensionReason}'
                    : 'Your account has been suspended by the VibeShort team for breaking the community rules.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted, height: 1.45),
              ),
              const SizedBox(height: 6),
              const Text(
                'While suspended you cannot watch, post or interact. If you think this is a mistake, contact the VibeShort team.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, height: 1.45),
              ),
              const SizedBox(height: 26),
              OutlinedButton.icon(
                onPressed: () async {
                  await AuthService.instance.signOut();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (_) => false,
                  );
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Log out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF5C7A),
                  minimumSize: const Size(180, 48),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Inbox icon with a live unread-count badge (hidden at zero).
  Widget _inboxIcon({required bool active}) {
    return StreamBuilder<int>(
      stream: FirestoreService.instance.unreadNotificationCount(),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(active ? Icons.inbox : Icons.inbox_outlined),
            if (count > 0)
              Positioned(
                right: -9,
                top: -5,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints:
                      const BoxConstraints(minWidth: 17, minHeight: 17),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B5C),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
