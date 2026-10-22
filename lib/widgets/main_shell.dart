import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/screens/home/home_screen.dart';
import 'package:vibeshort/screens/profile/profile_screen.dart';
import 'package:vibeshort/screens/upload/upload_screen.dart';

/// Bottom-nav shell: Home feed | Upload | Profile.
/// (Discover and Inbox are later blueprint phases.)
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
          UploadScreen(onPosted: () => setState(() => _index = 0)),
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
            label: 'Upload',
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
}
