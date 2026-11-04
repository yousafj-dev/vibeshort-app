import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/screens/auth/auth_screen.dart';
import 'package:vibeshort/widgets/main_shell.dart';

/// Splash: the Logo 1 "Play-V" intro (build 16), then routes to
/// auth or home.
///
/// Animation (mirrors the user-approved reference clip, ≈2.6s):
/// the V arm draws in top→bottom, the play triangle pops to
/// ~1.18× with a soft brand glow and settles, the "VibeShort"
/// wordmark fades/slides in, then the whole mark zooms IN and
/// crossfades into the first screen. A tap skips to the end of
/// the animation.
///
/// Routing waits for BOTH the intro AND the real auth state
/// ([AuthService.authResolved]) — Firebase Auth persists the
/// session natively on Android, so a signed-in user goes
/// straight home; login shows only when genuinely signed out.
///
/// test-apk-18 ROOT-CAUSE FIX ("login asked again and again"):
/// the build-16 splash added a 3.5s hard cap that routed on the
/// best-known state even while auth was UNRESOLVED. But
/// AuthService's restore window (fix round 3) deliberately holds
/// resolution for up to 12s when the first auth event arrives
/// null while a session marker exists — exactly the cold-start
/// pattern after the app is swiped from Recents. The cap fired
/// at 3.5s with _user still null and dropped the user on the
/// login screen, seconds before the native session landed; and
/// because the splash was gone, the restored session never
/// re-routed him. The pre-16 splash had no cap and simply kept
/// waiting, which is why persistence "worked" before. The cap
/// is now a SETTLE check, not a routing decision: at 3.5s an
/// unresolved gate is settled from the LIVE FirebaseAuth
/// session when one exists (signed in → home); with no live
/// session the splash keeps waiting for real resolution, and a
/// 20s last-resort backstop (past the full 12s restore window)
/// settles from live state either way so the user can never be
/// trapped here.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AuthService _auth;
  late final AnimationController _ctrl;
  Timer? _capTimer;
  Timer? _backstopTimer;
  bool _delayDone = false;
  bool _capReached = false;
  bool _routed = false;

  /// Mark canvas in logical px (glyph aspect 600:556).
  static const double _markW = 156;
  static const double _markH = _markW * 556 / 600;

  /// Play-triangle centroid inside the glyph box, as an
  /// Alignment, so the pop scales around the triangle itself.
  static const Alignment _triCenter = Alignment(0.316, 0.108);

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthService>();
    _auth.addListener(_maybeRoute);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _delayDone = true;
          _maybeRoute();
        }
      });
    _ctrl.forward();
    // Settle check (test-apk-18): if auth is still unresolved at
    // 3.5s, _maybeRoute settles the gate from the LIVE native
    // session when one exists. It never routes to login on an
    // unresolved state — see the class doc for the root cause.
    _capTimer = Timer(const Duration(milliseconds: 3500), () {
      _capReached = true;
      _maybeRoute();
    });
    // Last-resort backstop: AuthService guarantees resolution
    // within its 12s restore window, so this should never fire —
    // but if the auth stream somehow never delivers, settle from
    // live state (either way) instead of trapping the user here.
    _backstopTimer = Timer(const Duration(seconds: 20), () {
      _auth.settleFromLiveSession(force: true);
      _maybeRoute();
    });
    _maybeRoute();
  }

  @override
  void dispose() {
    _capTimer?.cancel();
    _backstopTimer?.cancel();
    _ctrl.dispose();
    _auth.removeListener(_maybeRoute);
    super.dispose();
  }

  void _skip() {
    if (_ctrl.isCompleted) return;
    _ctrl.value = 1.0;
    _delayDone = true;
    _maybeRoute();
  }

  void _maybeRoute() {
    if (_routed || !mounted) return;
    if (!_delayDone) return;
    if (!_auth.authResolved) {
      // Unresolved: the ONLY early exit is a live native session
      // (test-apk-18). Settling through the service keeps its
      // marker/listener state consistent; if it resolves, fall
      // through and route in this same call. Otherwise keep
      // waiting — routing to login from here, on a guess, was
      // the "login again and again" bug.
      if (_capReached && _auth.hasLiveSession) {
        _auth.settleFromLiveSession();
      }
      // Settling notifies listeners, which re-enters this method
      // and may already have routed — bail out in that case.
      if (_routed || !_auth.authResolved) return;
    }
    _routed = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) =>
            _auth.isSignedIn ? const MainShell() : const AuthScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // ---- animation phase helpers (t = controller value 0..1) ----

  double _phase(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  /// Triangle pop: grows past full size (~1.18×) then settles.
  double _popScale(double p) {
    if (p <= 0) return 0.4;
    if (p < 0.6) {
      final e = Curves.easeOut.transform(p / 0.6);
      return 0.4 + (1.18 - 0.4) * e;
    }
    final e = Curves.easeInOut.transform((p - 0.6) / 0.4);
    return 1.18 + (1.0 - 1.18) * e;
  }

  @override
  Widget build(BuildContext context) {
    // Watched only so the "restoring session" spinner clears.
    final auth = context.watch<AuthService>();
    final resolved = auth.authResolved;
    final restoring = auth.restoringSession;
    return Scaffold(
      // The splash is a brand moment: it stays on the logo's
      // dark ground in BOTH themes (like the launcher icon).
      backgroundColor: AppTheme.bgDark,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final t = _ctrl.value;
              final armP = Curves.easeOut.transform(_phase(t, 0.0, 0.30));
              final popP = _phase(t, 0.26, 0.55);
              final wordP =
                  Curves.easeOut.transform(_phase(t, 0.45, 0.68));
              final tagP =
                  Curves.easeOut.transform(_phase(t, 0.52, 0.72));
              final zoomP =
                  Curves.easeIn.transform(_phase(t, 0.76, 1.0));
              final markScale = 1.0 + 1.6 * zoomP; // → ~2.6×
              final markOpacity = 1.0 - _phase(t, 0.90, 1.0);
              final glow = 0.22 +
                  0.38 * (popP > 0 && popP < 1 ? 1.0 : 0.55) +
                  0.25 * zoomP;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: markOpacity,
                    child: Transform.scale(
                      scale: markScale,
                      child: SizedBox(
                        width: _markW,
                        height: _markH,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            // Soft brand glow behind the mark.
                            Container(
                              width: _markW * 1.9,
                              height: _markW * 1.9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppTheme.accent
                                        .withOpacity(glow.clamp(0.0, 0.85)),
                                    AppTheme.accent2
                                        .withOpacity(glow * 0.55),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                              ),
                            ),
                            // V arm: draws in top → bottom.
                            ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: armP,
                                child: Opacity(
                                  opacity: (armP * 1.4).clamp(0.0, 1.0),
                                  child: Image.asset(
                                    'assets/images/logo_arm.png',
                                    width: _markW,
                                    height: _markH,
                                    cacheWidth: 480,
                                  ),
                                ),
                              ),
                            ),
                            // Play triangle: pops with overshoot.
                            Opacity(
                              opacity: _phase(popP, 0.0, 0.3),
                              child: Transform.scale(
                                scale: _popScale(popP),
                                alignment: _triCenter,
                                child: Image.asset(
                                  'assets/images/logo_tri.png',
                                  width: _markW,
                                  height: _markH,
                                  cacheWidth: 480,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: wordP * (1.0 - _phase(t, 0.76, 0.88)),
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1.0 - wordP)),
                      child: const Text(
                        'VibeShort',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: tagP * (1.0 - _phase(t, 0.76, 0.88)),
                    child: Text(
                      'Feel the vibe',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.mutedDark,
                      ),
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
                  // Fix round 3: a previous session exists but the
                  // native restore is lagging — say so instead of
                  // silently dropping the user on the login screen.
                  if (restoring) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Restoring your session…',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.mutedDark),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
