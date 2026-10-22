import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/screens/discover/discover_screen.dart';
import 'package:vibeshort/screens/home/home_screen.dart';
import 'package:vibeshort/screens/inbox/inbox_screen.dart';
import 'package:vibeshort/screens/profile/profile_screen.dart';
import 'package:vibeshort/screens/upload/upload_screen.dart';
import 'package:vibeshort/services/firestore_service.dart';

/// Bottom-nav shell (TikTok style, 5 tabs):
/// Home | Discover | Create (+) | Inbox | Profile.
/// The Inbox icon carries a live unread-notification badge.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: IndexedStack(
        index: _index,
        children: [
          const HomeScreen(),
          const DiscoverScreen(),
          UploadScreen(onPosted: () => setState(() => _index = 0)),
          InboxScreen(active: _index == 3),
          const ProfileScreen(),
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
