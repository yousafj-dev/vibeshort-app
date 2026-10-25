import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Email/password auth for VibeShort.
///
/// Session persistence is the design rule: FirebaseAuth persists the
/// session natively on Android, and the splash gate waits for
/// [authResolved] — the first real auth-state event — before routing,
/// so a signed-in user is NEVER dropped on the login screen at cold
/// start (this was the "login every time" bug in the previous app).
///
/// Fix round 3 hardened this further, after "login every time I
/// close the app from Recents" was reported on the shipped build:
///  * The app now runs under a REGISTERED ANDROID appId (see
///    main.dart) — the web appId left the native session store
///    without a proper Android app identity to key on.
///  * A session marker (uid) is kept in SharedPreferences. When a
///    marker exists but the first auth event says "signed out",
///    the gate does NOT route to login immediately: it enters a
///    restore window ([restoringSession]) and keeps listening —
///    native restore can lag on slow devices, and a Firestore
///    profile fetch is never part of the gate at all, so a near-
///    zero-bandwidth connection cannot bounce a signed-in user
///    to the login screen. Only an EXPLICIT sign-out (Log out /
///    Switch account / Delete account) clears the marker, and
///    only then does a null event resolve instantly.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// Session-marker keys (fix round 3). The marker records only
  /// THAT a session existed and its uid — never a credential.
  static const String _kSessionUid = 'vibeshort_session_uid';
  static const String _kExplicitOut = 'vibeshort_explicit_signout';

  /// Set by main() after the Firebase.initializeApp() attempt.
  static bool firebaseReady = false;

  static const String offlineMsg =
      'Could not connect. Please check your internet connection and try again.';

  FirebaseAuth? _auth;
  User? _user;
  bool _initialized = false;

  /// True once the REAL session state is known: either a non-null
  /// [FirebaseAuth.currentUser] at startup, or the first
  /// authStateChanges event (which always fires once with the
  /// persisted user — or null when genuinely signed out).
  bool _authResolved = false;
  bool get authResolved => _authResolved;

  /// Fix round 3: a session marker existed at startup but the
  /// first auth event reported signed-out, so the gate is holding
  /// in the restore window instead of bouncing to login. The
  /// splash shows a "restoring session" cue while this is true.
  bool _restoringSession = false;
  bool get restoringSession => _restoringSession;
  Timer? _restoreTimer;
  bool _hadSessionMarker = false;

  FirebaseAuth get _authSafe {
    _auth ??= FirebaseAuth.instance;
    return _auth!;
  }

  User? get currentUser => _user;
  bool get isSignedIn => _user != null;
  String? get uid => _user?.uid;

  /// Friendly display name: the profile display name when set, else
  /// the email prefix, or 'user'.
  String get displayName {
    final dn = _user?.displayName;
    if (dn != null && dn.trim().isNotEmpty) return dn.trim();
    final email = _user?.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return 'user';
  }

  String? get photoUrl => _user?.photoURL;
  String? get email => _user?.email;

  void _ensureReady() {
    if (!firebaseReady) throw Exception(offlineMsg);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (!firebaseReady) {
      // Offline mode: nothing to restore; the gate can decide now.
      _authResolved = true;
      return;
    }
    // Fix round 3: read the session marker BEFORE subscribing, so
    // the very first null event can be judged against it.
    try {
      final p = await SharedPreferences.getInstance();
      _hadSessionMarker = p.getString(_kSessionUid) != null &&
          p.getBool(_kExplicitOut) != true;
    } catch (_) {
      _hadSessionMarker = false;
    }
    try {
      // Fast path only: a non-null currentUser is a definite
      // signed-in session. A null here proves NOTHING at cold
      // start (native restore may still be in flight), so in that
      // case only the first stream event resolves the state.
      _user = _authSafe.currentUser;
      if (_user != null) {
        _authResolved = true;
        _markSession(_user!.uid);
      }
      // Both streams are listened to: userChanges also fires for
      // token/profile restores that authStateChanges can lag on.
      _authSafe.authStateChanges().listen(_onAuthEvent);
      _authSafe.userChanges().listen(_onAuthEvent);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.init failed: $e');
      _authResolved = true;
    }
  }

  /// Single handler for auth-state events (fix round 3).
  ///
  /// A non-null user is definitive: signed in, marker written,
  /// gate resolved. A null user is definitive ONLY when there is
  /// no session marker (never signed in, or an explicit sign-out
  /// already cleared it) — with a marker, the native restore may
  /// simply be lagging after process death, so the gate holds in
  /// the restore window for up to 12 s (re-checking currentUser
  /// once mid-window) before it accepts "signed out".
  void _onAuthEvent(User? u) {
    if (u != null) {
      final wasRestoring = _restoringSession;
      _user = u;
      _restoringSession = false;
      _restoreTimer?.cancel();
      _authResolved = true;
      _markSession(u.uid);
      if (wasRestoring) {
        debugPrint('AuthService: session restored after null event');
      }
      notifyListeners();
      return;
    }
    _user = null;
    if (!_hadSessionMarker || _authResolved) {
      _authResolved = true;
      notifyListeners();
      return;
    }
    // Marker present + first null: hold, don't bounce.
    if (!_restoringSession) {
      _restoringSession = true;
      debugPrint('AuthService: null event with session marker — '
          'holding in restore window');
      // Mid-window re-check: on some devices currentUser lands
      // before any further stream event fires.
      Timer(const Duration(seconds: 3), () {
        final cu = _authSafe.currentUser;
        if (cu != null) _onAuthEvent(cu);
      });
      _restoreTimer = Timer(const Duration(seconds: 12), () {
        if (!_restoringSession) return;
        _restoringSession = false;
        // The native session is genuinely gone. Drop the stale
        // marker so the NEXT cold start resolves instantly, and
        // let the gate route to login this once — the sign-in
        // that follows re-persists under the fixed app identity.
        _hadSessionMarker = false;
        _markSession(null);
        _authResolved = true;
        notifyListeners();
      });
      notifyListeners();
    }
  }

  /// Writes/clears the fix-round-3 session marker. Fire-and-forget:
  /// a prefs failure must never break an auth flow.
  Future<void> _markSession(String? uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (uid == null) {
        await p.remove(_kSessionUid);
      } else {
        await p.setString(_kSessionUid, uid);
        await p.setBool(_kExplicitOut, false);
      }
    } catch (_) {}
  }

  /// Marks an EXPLICIT sign-out (the only paths that may clear
  /// the session marker): Log out, Switch account, Delete account.
  Future<void> _markExplicitSignOut() async {
    _hadSessionMarker = false;
    _restoringSession = false;
    _restoreTimer?.cancel();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kSessionUid);
      await p.setBool(_kExplicitOut, true);
    } catch (_) {}
  }

  /// Creates the account and returns the new user's uid. Profile
  /// fields (display name / username) are applied by the caller via
  /// Firestore + [updateDisplayName] right after.
  Future<String> signUp(String email, String password) async {
    _ensureReady();
    final pw = password;
    try {
      final cred = await _authSafe.createUserWithEmailAndPassword(
        email: email.trim(),
        password: pw,
      );
      _user = cred.user;
      _hadSessionMarker = true;
      await _cacheEmail(email.trim());
      await _markSession(cred.user!.uid);
      notifyListeners();
      return cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  Future<void> signIn(String email, String password) async {
    _ensureReady();
    final pw = password;
    try {
      final cred = await _authSafe.signInWithEmailAndPassword(
        email: email.trim(),
        password: pw,
      );
      _user = cred.user;
      _hadSessionMarker = true;
      await _cacheEmail(email.trim());
      await _markSession(cred.user!.uid);
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  /// Sends a Firebase password-reset email. Friendly English
  /// errors only — never a raw FirebaseAuthException message.
  Future<void> sendPasswordReset(String email) async {
    _ensureReady();
    final trimmed = email.trim();
    if (!trimmed.contains('@')) {
      throw Exception('Please enter a valid email address.');
    }
    try {
      await _authSafe.sendPasswordResetEmail(email: trimmed);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No account exists for this email.');
        case 'invalid-email':
          throw Exception('Please enter a valid email address.');
        case 'network-request-failed':
          throw Exception(
              'No internet connection. Please check and try again.');
        default:
          throw Exception(
              'Could not send the reset link. Please try again.');
      }
    }
  }

  Future<void> updateDisplayName(String name) async {
    _ensureReady();
    final u = _user;
    if (u == null) throw Exception('Please log in first.');
    try {
      await u.updateDisplayName(name);
      await u.reload();
      _user = _authSafe.currentUser;
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  /// Updates the FirebaseAuth profile photo URL and refreshes the
  /// cached user so the UI picks the new value up.
  Future<void> updatePhotoUrl(String url) async {
    _ensureReady();
    final u = _user;
    if (u == null) throw Exception('Please log in first.');
    try {
      await u.updatePhotoURL(url);
      await u.reload();
      _user = _authSafe.currentUser;
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  /// Re-proves the user's identity with their current password —
  /// required by Firebase before sensitive operations (password
  /// change, account deletion). Throws a friendly Exception.
  Future<void> reauthenticate(String currentPassword) async {
    _ensureReady();
    final u = _user;
    final email = u?.email;
    if (u == null || email == null) {
      throw Exception('Please log in first.');
    }
    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await u.reauthenticateWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw Exception('Current password is incorrect.');
      }
      throw Exception(_friendly(e));
    }
  }

  /// Changes the account password after a successful
  /// [reauthenticate] with the current one.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _ensureReady();
    if (newPassword.length < 6) {
      throw Exception('New password must be at least 6 characters.');
    }
    await reauthenticate(currentPassword);
    try {
      await _user!.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  /// Deletes the FirebaseAuth user itself. Call AFTER the
  /// account's Firestore data has been removed and a fresh
  /// [reauthenticate] — Firebase requires a recent login for
  /// deletion.
  Future<void> deleteCurrentUser() async {
    _ensureReady();
    final u = _user;
    if (u == null) throw Exception('Please log in first.');
    try {
      await u.delete();
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendly(e));
    }
    _user = null;
    await _markExplicitSignOut();
    notifyListeners();
  }

  /// The ONLY sign-out path in the app (explicit Log out button).
  Future<void> signOut() async {
    await _markExplicitSignOut();
    if (!firebaseReady) {
      _user = null;
      notifyListeners();
      return;
    }
    try {
      await _authSafe.signOut();
    } catch (e) {
      debugPrint('AuthService.signOut failed: $e');
    }
    _user = null;
    notifyListeners();
  }

  Future<void> _cacheEmail(String email) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('vibeshort_last_email', email);
    } catch (_) {}
  }

  Future<String?> lastEmail() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString('vibeshort_last_email');
    } catch (_) {
      return null;
    }
  }

  String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'This email is not registered. Please create an account first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'This email is already registered. Please log in.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'network-request-failed':
        return 'No internet connection. Please check and try again.';
      default:
        return 'Something went wrong (${e.code}). Please try again.';
    }
  }
}
