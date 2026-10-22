import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/screens/auth/auth_screen.dart';
import 'package:vibeshort/widgets/main_shell.dart';

/// Splash: VibeShort logo + name, then routes to auth or home.
///
/// Routing waits for BOTH the minimum brand display AND the real
/// auth state ([AuthService.authResolved]). Firebase Auth persists
/// the session natively on Android, so once the persisted state is
/// known, a signed-in user goes straight home — login is only
/// shown when genuinely signed out (or after an explicit logout).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final AuthService _auth;
  Timer? _timer;
  bool _delayDone = false;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthService>();
    _auth.addListener(_maybeRoute);
    _timer = Timer(const Duration(milliseconds: 1400), () {
      _delayDone = true;
      _maybeRoute();
    });
    _maybeRoute();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auth.removeListener(_maybeRoute);
    super.dispose();
  }

  void _maybeRoute() {
    if (_routed || !mounted) return;
    if (!_delayDone || !_auth.authResolved) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            _auth.isSignedIn ? const MainShell() : const AuthScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched only so the "restoring session" spinner clears.
    final resolved = context.watch<AuthService>().authResolved;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Center(
                child: Text(
                  'V',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'VibeShort',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Feel the vibe',
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 28),
            // Session still restoring — subtle progress cue.
            if (!resolved)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
