import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/screens/splash/splash_screen.dart';

/// VibeShort's Firebase config — explicit options in Dart (no
/// google-services.json). This is the shared quizistan-academy
/// project; all VibeShort data lives in namespaced collections
/// (vibeshort_users / vibeshort_videos), so nothing collides with
/// the other apps using this project.
const FirebaseOptions _firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAwD-dF5rY_ULv9e-7uLhQKAMGQ78c93EA',
  authDomain: 'quizistan-academy.firebaseapp.com',
  projectId: 'quizistan-academy',
  storageBucket: 'quizistan-academy.firebasestorage.app',
  messagingSenderId: '606589084724',
  appId: '1:606589084724:web:7ab93e8b60b09713deb5661',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase is optional at runtime: the app still opens (with a
  // friendly offline message on actions) when init fails.
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
    AuthService.firebaseReady = true;
    debugPrint('VibeShort: Firebase ready');
  } catch (e) {
    debugPrint('VibeShort: Firebase init failed (offline mode): $e');
    AuthService.firebaseReady = false;
  }
  runApp(const VibeShortApp());
}

class VibeShortApp extends StatelessWidget {
  const VibeShortApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // lazy: false — start auth resolution at app start, not on
      // first read, so the persisted session is known by the time
      // the splash gate decides where to route.
      lazy: false,
      create: (_) => AuthService.instance..init(),
      child: MaterialApp(
        title: 'VibeShort',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const SplashScreen(),
      ),
    );
  }
}
