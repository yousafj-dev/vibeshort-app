import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibeshort/core/route_observer.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/prefs_service.dart';
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
  // Fix round 3 (login not persisting): this used to be the
  // project's WEB appId ('...:web:...'). Firebase Auth's Android
  // session store is keyed to a REGISTERED ANDROID app identity —
  // running an Android build under a web appId leaves the session
  // in memory only, so every process death (e.g. swipe away from
  // Recents) came back signed out, even though the app-side gate
  // was correct. The value below is the Android appId registered
  // for this project in the Firebase console (interim identity
  // for com.vibeshort.app until the package gets its own console
  // registration; Auth users and Firestore data are project-wide,
  // so accounts and content are unaffected).
  appId: '1:606589084724:android:a5536fead83abb85eb5661',
);

/// Initializes the default Firebase app, with ONE retry after a
/// short pause. A transient native init failure at cold start
/// must never masquerade as "logged out": [AuthService] treats
/// firebaseReady == false as an offline session and routes to
/// the login screen, so a single flaky attempt used to look
/// exactly like a lost login.
Future<bool> _initFirebase() async {
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
    return true;
  } catch (e) {
    debugPrint('VibeShort: Firebase init attempt 1 failed: $e');
  }
  // Drop a half-created default app before retrying.
  try {
    await Firebase.app().delete();
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 700));
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
    return true;
  } catch (e) {
    debugPrint('VibeShort: Firebase init attempt 2 failed: $e');
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local device prefs (Data Saver) — read synchronously by the
  // video card, so load them before the first frame.
  await PrefsService.load();
  // Firebase is optional at runtime: the app still opens (with a
  // friendly offline message on actions) when init fails.
  AuthService.firebaseReady = await _initFirebase();
  debugPrint(AuthService.firebaseReady
      ? 'VibeShort: Firebase ready'
      : 'VibeShort: Firebase init failed (offline mode)');
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
        // Feed cards subscribe to this observer so playback
        // pauses while another page covers the feed.
        navigatorObservers: [appRouteObserver],
        home: const SplashScreen(),
      ),
    );
  }
}
