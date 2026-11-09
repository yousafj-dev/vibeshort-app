import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
  apiKey: 'AIzaSyBy9f8qG58HhBUQVm7jzlwpi1cJtAl-yDk',
  authDomain: 'quizistan-academy.firebaseapp.com',
  projectId: 'quizistan-academy',
  storageBucket: 'quizistan-academy.firebasestorage.app',
  messagingSenderId: '606589084724',
  // test-apk-20: VibeShort now runs under its OWN registered
  // Android identity. On Nov 9, 2026 the package com.vibeshort.app
  // was registered in the Firebase console (app nickname
  // "VibeShort") and the values below come from that
  // registration's google-services.json. What was wrong before:
  // the appId below used to be the Android appId registered for
  // com.chaska.app (an interim borrowed identity adopted in fix
  // round 3), and the apiKey was not one of the keys in this
  // project's current google-services.json at all. Firebase
  // Auth's Android session store and token refresh are keyed to
  // the registered app identity, so a session created at login
  // was not recognised on the next cold start and the app asked
  // for login again and again. Auth users and Firestore data are
  // project-wide, so accounts and content are unaffected.
  appId: '1:606589084724:android:f25634e87b5f0740eb5661',
);

/// Initializes the default Firebase app, with ONE retry after a
/// short pause. A transient native init failure at cold start
/// must never masquerade as "logged out": [AuthService] treats
/// firebaseReady == false as an offline session and routes to
/// the login screen, so a single flaky attempt used to look
/// exactly like a lost login.
///
/// test-apk-19: the retry NO LONGER deletes the default app
/// first. The old code called Firebase.app().delete() between
/// attempts — deleting the default app destroys the persisted
/// Auth session store attached to it, so ONE flaky init on a
/// device holding a healthy session could wipe that session
/// permanently (a plausible contributor to the recurring
/// "login again and again" reports: the session would be gone
/// before AuthService ever got to look for it). Instead, if the
/// second attempt fails because the first actually created the
/// app (duplicate-app), the existing app is used as-is.
Future<bool> _initFirebase() async {
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
    return true;
  } catch (e) {
    debugPrint('VibeShort: Firebase init attempt 1 failed: $e');
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
    return true;
  } catch (e) {
    debugPrint('VibeShort: Firebase init attempt 2 failed: $e');
    // Attempt 1 may have created the default app before its
    // error surfaced; if a default app exists now, use it —
    // NEVER delete it (see the doc above).
    try {
      Firebase.app();
      debugPrint('VibeShort: using existing default Firebase app');
      return true;
    } catch (_) {
      return false;
    }
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
  if (AuthService.firebaseReady) {
    // Automatic crash reporting (Firebase Crashlytics): fatal
    // Flutter errors and uncaught async/platform errors are
    // reported with device model + Android version + cause, so
    // crashes on testers' phones can be diagnosed remotely.
    // Only wired when Firebase initialized — Crashlytics needs
    // the default app to exist.
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
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
      child: ValueListenableBuilder<bool>(
        // Dark / Light mode (build 16): the persisted choice is
        // loaded into PrefsService before runApp, so the first
        // frame already has the right theme; toggling it in
        // Settings rebuilds MaterialApp (and with it the whole
        // tree, whose chrome colors read AppTheme's mode-aware
        // getters at build time).
        valueListenable: PrefsService.themeNotifier,
        builder: (context, light, _) => MaterialApp(
          title: 'VibeShort',
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.light() : AppTheme.dark(),
          // Feed cards subscribe to this observer so playback
          // pauses while another page covers the feed.
          navigatorObservers: [appRouteObserver],
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
