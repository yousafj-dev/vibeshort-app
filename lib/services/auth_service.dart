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
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

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
    try {
      // Fast path only: a non-null currentUser is a definite
      // signed-in session. A null here proves NOTHING at cold
      // start (native restore may still be in flight), so in that
      // case only the first stream event resolves the state.
      _user = _authSafe.currentUser;
      if (_user != null) _authResolved = true;
      _authSafe.authStateChanges().listen((u) {
        _user = u;
        _authResolved = true;
        notifyListeners();
      });
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.init failed: $e');
      _authResolved = true;
    }
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
      await _cacheEmail(email.trim());
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
      await _cacheEmail(email.trim());
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
    notifyListeners();
  }

  /// The ONLY sign-out path in the app (explicit Log out button).
  Future<void> signOut() async {
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
