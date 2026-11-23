import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Email/password auth for VibeShort.
///
/// Session persistence is the design rule, implemented the
/// STANDARD way (test-apk-19): FirebaseAuth persists the session
/// natively on Android; at startup this service reads
/// [FirebaseAuth.currentUser] and subscribes to
/// `authStateChanges()` — the stream whose first event reflects
/// the persisted state — and the splash gate waits for
/// [authResolved] before routing.
///
/// Why the standard pattern replaced the earlier patchwork: the
/// fix-round-3 "restore window" held resolution for up to 12 s
/// whenever the first auth event arrived null with a session
/// marker present, and test-apk-18 kept that window. On the
/// user's phone the native restore never landed inside the
/// window, so every cold start showed "Restoring your session…"
/// for ~10 s and then dropped him on the login screen anyway —
/// and the window's expiry CLEARED the session marker, making
/// the damage permanent. A healthy Firebase cold start resolves
/// in about a second; a 10-second wait is itself a defect.
///
/// The rules now:
///  * A non-null user (currentUser at startup, or any event) is
///    definitive: signed in, session marker written, resolved.
///  * A null event resolves signed-out IMMEDIATELY when there is
///    no session marker (never signed in) or an explicit sign-out
///    flag is set (Log out / Switch account / Delete account).
///  * A null event WITH a marker gets one SHORT fuse (6 s, with
///    a mid-fuse currentUser re-check and an idTokenChanges
///    second signal — test-apk-75): if a live user surfaces
///    in that time the gate resolves signed-in, otherwise it
///    resolves signed-out and records a "restore miss" for
///    diagnosis — the marker is KEPT (only an explicit sign-out,
///    an account deletion, or a fresh sign-in may change it), so
///    one bad restore can never break every future launch.
///  * If the native restore lands only AFTER the gate resolved
///    signed-out (slow device), the late non-null event still
///    flips this service to signed-in, and the login screen
///    follows it home on its own (test-apk-75) — a lost race
///    can no longer strand a signed-in user on the login form.
///    An explicit sign-out removes the native session, so no
///    late event can ever resurrect one.
///  * BOUNDED WAIT (test-apk-75): the fuse above only starts
///    when a null event ARRIVES. Build 74's splash hang (the
///    user's screenshot: spinner + "Restoring your session…"
///    that eventually lands on login) was the case where NO
///    event arrived at all — the native auth listener was
///    starved by other cold-start work — so no fuse ran and
///    the only exit was the splash's 8 s backstop resolving
///    signed-out from an empty cache. A 5 s deadline timer,
///    started at subscription time and independent of any
///    stream, now probes the persisted native user directly:
///    a live user resolves the gate signed-in on the spot,
///    and with a marker present nothing else is decided by a
///    timer at all (backstop + self-heal own the rest). A
///    slow network can therefore never strand a logged-in
///    user on the splash or bounce him to login.
///  * Once resolved signed-in, a stray null event (token-refresh
///    / reload edge) never tears the session down; only an
///    explicit sign-out does.
///  * The splash is the ONLY automatic router to the login
///    screen, and it routes only on a resolved state. Every
///    other trip to the login screen in the app follows an
///    explicit user tap (Log out / Delete account).
///
/// APP-MANAGED RESTORE (the final layer): the test-apk-88
/// diagnostic build proved — with a fresh login, on the same
/// build, with the same apiKey — that on the user's phone the
/// native Firebase Auth store is EMPTY at the next cold start:
/// currentUser is null from the first instant, the first auth
/// event is null, and there is no persisted session to refresh,
/// while this service's SharedPreferences session marker
/// survives untouched. Native persistence therefore cannot be
/// relied on for this install base. So, in addition to
/// everything above: every successful sign-in / sign-up saves
/// the credentials to the platform secure storage (Android
/// Keystore-backed, via flutter_secure_storage), and when the
/// gate would otherwise resolve signed-out WITH a session
/// marker and no explicit sign-out, it first makes ONE silent
/// signInWithEmailAndPassword attempt with the stored
/// credentials (see [_tryStoredRestore]). Success resolves the
/// gate signed-in through the normal event handler (and the
/// login screen's self-heal carries the user home if routing
/// already flipped). A network failure keeps the stored
/// credentials for the next launch; an invalid-credential
/// failure deletes them — the user then logs in manually once
/// and that login re-saves them. An explicit sign-out deletes
/// the stored credentials, so a deliberate logout is never
/// silently undone.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// Session-marker keys. The marker records only THAT a session
  /// existed and its uid — never a credential. It is written on
  /// sign-in / sign-up and on every resolved signed-in event,
  /// and cleared ONLY by an explicit sign-out or account
  /// deletion (test-apk-19: the old restore-window expiry also
  /// cleared it, which turned one slow restore into a permanent
  /// every-launch bounce — timeouts NEVER clear it now).
  static const String _kSessionUid = 'vibeshort_session_uid';
  static const String _kExplicitOut = 'vibeshort_explicit_signout';

  /// Restore-miss diagnostics (test-apk-19): how often the gate
  /// resolved signed-out while a session marker existed (the
  /// "session restore never landed" fingerprint), and when it
  /// last happened. Purely diagnostic — never used for routing.
  static const String _kRestoreMissCount = 'vibeshort_restore_miss_count';
  static const String _kRestoreMissAt = 'vibeshort_restore_miss_at';

  /// Set by main() after the Firebase.initializeApp() attempt.
  static bool firebaseReady = false;

  static const String offlineMsg =
      'Could not connect. Please check your internet connection and try again.';

  /// Secure-storage keys for the app-managed session restore
  /// (see the class doc). The credentials live ONLY in the
  /// platform secure storage — never in SharedPreferences,
  /// never logged, and they are sent nowhere except the
  /// Firebase sign-in call itself.
  static const String _kSecureEmail = 'vs_auth_email';
  static const String _kSecurePassword = 'vs_auth_password';

  static final FlutterSecureStorage _secureStorage =
      FlutterSecureStorage();

  /// One silent restore attempt per cold start, ever: the gate
  /// may reach the "would resolve signed-out" decision from
  /// more than one path (fuse expiry, splash backstop), and a
  /// second attempt could race the first one's sign-in.
  bool _storedRestoreAttempted = false;
  bool _storedRestoreInFlight = false;

  FirebaseAuth? _auth;
  User? _user;
  bool _initialized = false;

  /// True once the REAL session state is known: either a non-null
  /// [FirebaseAuth.currentUser] at startup, or the first
  /// authStateChanges event (which always fires once with the
  /// persisted user — or null when genuinely signed out).
  bool _authResolved = false;
  bool get authResolved => _authResolved;

  /// Uid from the session marker read at startup (null = no
  /// prior session on this device). Kept in sync by
  /// [_markSession] whenever the marker is written or cleared.
  String? _markerUid;

  /// The short fuse (test-apk-19) running after a first null
  /// event that arrived WITH a session marker: the gate gives
  /// the native restore up to [_fuseWindow] to surface a live
  /// user before it accepts "signed out". While the fuse runs —
  /// and only then — the splash may show its restoring cue, so
  /// the cue can now last at most ~6 s instead of ~10 s.
  /// test-apk-75 widened the fuse from 3 s: the test-apk-74
  /// retest showed the bounce surviving on the user's phone
  /// (signed in and using the app, asked to log in again on
  /// the next launch minutes later) while every other suspect
  /// audited clean — FirebaseOptions match the Nov 9 console
  /// registration exactly, no code path signs out or clears
  /// data, and sign-in/Firestore demonstrably work — leaving
  /// the native restore landing just after the 3 s fuse as
  /// the mechanism. The AuthScreen self-heal (test-apk-75)
  /// covers any restore that lands later still.
  Timer? _fuseTimer;
  Timer? _fuseRecheck;
  bool _fuseRunning = false;
  static const Duration _fuseWindow = Duration(seconds: 6);

  /// True while a marker-carrying cold start is still
  /// unresolved (the brief fuse period). The splash shows its
  /// "restoring session" cue while this is true.
  bool get restoringSession =>
      !_authResolved && _markerUid != null && !_explicitOut;

  /// In-memory mirror of the explicit-sign-out marker (test-apk-18):
  /// true only between an explicit sign-out (Log out / Switch /
  /// Delete) and the next sign-in. A stray null auth event that
  /// arrives while a session is resolved signed-in is treated as
  /// transient (token-refresh / reload edge) and ignored UNLESS
  /// this flag says the sign-out was deliberate.
  bool _explicitOut = false;

  /// Startup-only second restore signal (test-apk-75): an
  /// idTokenChanges subscription that can still deliver the
  /// restored user after authStateChanges opened with null —
  /// the restored user is only fully materialised once its
  /// first ID token is fetched, which is what this stream
  /// reports. Cancelled as soon as the gate resolves.
  StreamSubscription<User?>? _startupTokenSub;

  /// Bounded-wait deadline (test-apk-75): started when the
  /// startup subscriptions are made; if NO signal has resolved
  /// the gate by then, the persisted native user is probed
  /// directly (see the class doc). Cancelled on resolution.
  Timer? _resolutionTimer;

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
    // Read the session marker and the explicit-sign-out flag
    // BEFORE subscribing, so the very first auth event can be
    // judged against them.
    try {
      final p = await SharedPreferences.getInstance();
      _markerUid = p.getString(_kSessionUid);
      _explicitOut = p.getBool(_kExplicitOut) == true;
      if (_explicitOut) _markerUid = null;
    } catch (_) {
      _markerUid = null;
    }
    try {
      // Fast path only: a non-null currentUser is a definite
      // signed-in session. A null here proves NOTHING at cold
      // start (native restore may still be in flight), so in that
      // case the first stream event — or the short fuse —
      // resolves the state.
      _user = _authSafe.currentUser;
      if (_user != null) {
        _authResolved = true;
        _markSession(_user!.uid);
      }
      // Standard pattern (test-apk-19): authStateChanges() ONLY.
      // Its first event reflects the persisted session state.
      // The old code ALSO listened to userChanges(), whose extra
      // initial/null events fed the fragile restore-window logic
      // this build removes; profile changes are applied through
      // the explicit update methods below, not the stream.
      _authSafe
          .authStateChanges()
          .listen((u) => _onAuthEvent(u, source: 'authStateChanges'));
      // test-apk-75: second restore signal. On slow devices
      // the native session restore can finish AFTER
      // authStateChanges has already delivered its first
      // (null) event — the user is only fully materialised
      // once the first ID token is fetched, which is what
      // idTokenChanges reports. Feed any non-null token event
      // into the same handler until the gate resolves; null
      // token events are ignored here (the authStateChanges
      // path owns null handling and the fuse).
      _startupTokenSub = _authSafe.idTokenChanges().listen((u) {
        if (_authResolved) {
          _startupTokenSub?.cancel();
          _startupTokenSub = null;
          return;
        }
        if (u != null) _onAuthEvent(u, source: 'idTokenChanges');
      });
      // Bounded wait (test-apk-75): independent of both
      // streams. If neither has resolved the gate in 5 s —
      // the build-74 hang, where the native auth listener
      // never delivered even its first event — probe the
      // persisted user directly. A live user is definitive
      // and resolves signed-in through the normal handler.
      // No cached user + a session marker: decide NOTHING
      // here (the splash backstop forces a decision at 8 s
      // and the login self-heal catches any later landing);
      // no cached user + no marker is already handled by the
      // null-event path, which fires instantly in practice.
      _resolutionTimer = Timer(const Duration(seconds: 5), () {
        if (_authResolved) return;
        try {
          final cu = _authSafe.currentUser;
          if (cu != null) {
            _onAuthEvent(cu, source: 'deadline-probe');
          }
          // Still null: decide NOTHING here (the fuse and the
          // splash backstop own the signed-out decision).
        } catch (_) {}
      });
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.init failed: $e');
      _authResolved = true;
    }
  }

  /// Single handler for auth-state events (test-apk-19).
  ///
  /// A non-null user is definitive at ANY time: signed in,
  /// marker written, gate resolved, fuse cancelled.
  ///
  /// A null user is judged by context:
  ///  * already resolved signed-in and NOT an explicit sign-out
  ///    → transient (token-refresh / reload edge): ignored, the
  ///    session is never torn down by a stray null;
  ///  * explicit sign-out → the sign-out path has already
  ///    cleared the user; this echo changes nothing;
  ///  * unresolved with NO marker (or an explicit sign-out
  ///    before this launch) → definitive signed-out, resolve
  ///    immediately (fresh installs reach login with no wait);
  ///  * unresolved WITH a marker → start the short fuse: the
  ///    native restore gets [_fuseWindow] to surface a live
  ///    user (re-checked mid-fuse and at expiry). If none
  ///    surfaces, the gate makes its ONE app-managed restore
  ///    attempt ([_tryStoredRestore]) before it may resolve
  ///    signed-out and record a restore miss — and the marker
  ///    is KEPT either way, so the next launch gets the same
  ///    fair chance instead of an instant bounce (the old 12 s
  ///    window cleared the marker at expiry, which is what
  ///    made the failure permanent).
  void _onAuthEvent(User? u, {String source = '?'}) {
    if (u != null) {
      final wasUnresolved = !_authResolved;
      _user = u;
      _explicitOut = false;
      _cancelFuse();
      _startupTokenSub?.cancel();
      _startupTokenSub = null;
      _authResolved = true;
      _markSession(u.uid);
      if (wasUnresolved) {
        debugPrint('AuthService: session resolved signed-in');
      }
      notifyListeners();
      return;
    }
    // Null event.
    if (_authResolved) {
      if (_user != null && !_explicitOut) {
        debugPrint('AuthService: ignoring transient null event '
            '(session already resolved signed-in)');
      }
      // Otherwise: the echo of an explicit sign-out (signOut /
      // deleteCurrentUser already cleared _user) or a repeat
      // null on a resolved signed-out gate — nothing changes.
      return;
    }
    if (_explicitOut || _markerUid == null) {
      _user = null;
      _authResolved = true;
      _startupTokenSub?.cancel();
      _startupTokenSub = null;
      _resolutionTimer?.cancel();
      notifyListeners();
      return;
    }
    // Unresolved WITH a marker: give the restore the short fuse.
    if (_fuseRunning) return; // further nulls change nothing
    _fuseRunning = true;
    debugPrint('AuthService: null event with session marker — '
        'short fuse started');
    notifyListeners();
    _fuseRecheck = Timer(const Duration(milliseconds: 1200), () {
      final cu = _authSafe.currentUser;
      if (cu != null) _onAuthEvent(cu, source: 'fuse-recheck');
    });
    _fuseTimer = Timer(_fuseWindow, () async {
      _fuseRunning = false;
      if (_authResolved) return;
      final cu = _authSafe.currentUser;
      if (cu != null) {
        _onAuthEvent(cu, source: 'fuse-expiry');
        return;
      }
      // The native restore genuinely did not land — on the
      // user's phone it never does (test-apk-88 evidence: the
      // native store is empty at cold start). Before accepting
      // signed-out, make the ONE app-managed restore attempt
      // from the secure-storage credentials. The splash keeps
      // showing "Restoring your session…" while this runs —
      // the gate is still unresolved, which is exactly right.
      if (await _tryStoredRestore()) return;
      if (_authResolved) return; // a stream event landed meanwhile
      // Resolve signed-out (the splash may now route to login —
      // the ONLY automatic path there), record the miss for
      // diagnosis, and KEEP the marker: a timeout must never
      // destroy the record that a session existed.
      _user = null;
      _authResolved = true;
      _startupTokenSub?.cancel();
      _startupTokenSub = null;
      _resolutionTimer?.cancel();
      _recordRestoreMiss();
      notifyListeners();
    });
  }

  void _cancelFuse() {
    _fuseRunning = false;
    _fuseTimer?.cancel();
    _fuseRecheck?.cancel();
    _resolutionTimer?.cancel();
  }

  /// Persists a restore-miss diagnostic (see [_kRestoreMissCount]).
  Future<void> _recordRestoreMiss() async {
    debugPrint('AuthService: RESTORE MISS — marker existed but '
        'no live session surfaced within the fuse');
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(
          _kRestoreMissCount, (p.getInt(_kRestoreMissCount) ?? 0) + 1);
      await p.setInt(
          _kRestoreMissAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Clears the restore-miss diagnostics after a real sign-in —
  /// fresh evidence starts from zero.
  Future<void> _clearRestoreMiss() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kRestoreMissCount);
      await p.remove(_kRestoreMissAt);
    } catch (_) {}
  }

  /// Writes the session marker for [uid] (a live session exists).
  /// Fire-and-forget: a prefs failure must never break an auth
  /// flow. Clearing the marker happens ONLY in
  /// [_markExplicitSignOut] — never on a timeout (test-apk-19).
  Future<void> _markSession(String uid) async {
    _markerUid = uid;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kSessionUid, uid);
      await p.setBool(_kExplicitOut, false);
    } catch (_) {}
  }

  /// Marks an EXPLICIT sign-out (the only paths that may clear
  /// the session marker): Log out, Switch account, Delete account.
  Future<void> _markExplicitSignOut() async {
    _explicitOut = true;
    _markerUid = null;
    _cancelFuse();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kSessionUid);
      await p.setBool(_kExplicitOut, true);
    } catch (_) {}
  }

  /// True when FirebaseAuth's LIVE native store holds a session
  /// right now (test-apk-18). The splash consults this before it
  /// may route anywhere on an unresolved state: a live session
  /// means "signed in", regardless of how slowly the auth
  /// stream's first event is travelling.
  bool get hasLiveSession {
    if (!firebaseReady) return false;
    try {
      return _authSafe.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Settles an unresolved gate from the LIVE native session.
  /// A live user is fed through the normal event handler, so
  /// marker/resolved/listener state stays consistent. With no
  /// live user, nothing is decided unless [force] is set — the
  /// splash's last-resort backstop uses that (long after the
  /// short fuse has had its full chance) to let the gate route
  /// to login rather than trapping the user on the splash
  /// forever. Even then, a marker-carrying cold start first
  /// gets its one app-managed restore attempt
  /// ([_tryStoredRestore]) before signed-out is accepted. In
  /// normal operation the fuse resolves the gate within ~6 s
  /// and this never fires.
  void settleFromLiveSession({bool force = false}) {
    if (_authResolved || !firebaseReady) return;
    try {
      final cu = _authSafe.currentUser;
      if (cu != null) {
        _onAuthEvent(cu, source: 'live-probe');
        return;
      }
    } catch (_) {}
    if (!force) return;
    // A stored-credentials restore is already running (started
    // by the fuse): it owns the resolution — it either resolves
    // signed-in or falls through to the signed-out decision in
    // the fuse path. Forcing a verdict here would race it.
    if (_storedRestoreInFlight) return;
    // No live session and no restore running: if this cold
    // start carried a session marker (and no explicit
    // sign-out), the gate may not accept signed-out until the
    // ONE app-managed restore attempt has had its chance —
    // this backstop can be the first path to reach the
    // decision when no auth event ever arrived (the build-74
    // hang), where no fuse is running to make the attempt.
    if (_markerUid != null && !_explicitOut && !_storedRestoreAttempted) {
      _tryStoredRestore().then((restored) {
        if (!restored && !_authResolved) _forceResolveSignedOut();
      });
      return;
    }
    _forceResolveSignedOut();
  }

  /// Accepts "signed out" for an unresolved gate: cancels every
  /// pending restore mechanism and resolves. Used only by the
  /// last-resort paths (splash backstop, after the app-managed
  /// restore attempt has failed or does not apply).
  void _forceResolveSignedOut() {
    _cancelFuse();
    _startupTokenSub?.cancel();
    _startupTokenSub = null;
    _user = null;
    _authResolved = true;
    notifyListeners();
  }

  // ===== App-managed session restore (secure-storage vault) =====

  /// Saves the credentials of a successful sign-in / sign-up
  /// into the platform secure storage so a later cold start can
  /// silently restore the session when the native Firebase
  /// Auth store comes up empty. Never throws: a vault failure
  /// must not break an otherwise successful auth flow.
  Future<void> _saveStoredCredentials(
      String email, String password) async {
    try {
      await _secureStorage.write(key: _kSecureEmail, value: email);
      await _secureStorage.write(
          key: _kSecurePassword, value: password);
    } catch (_) {}
  }

  /// Deletes the stored credentials (explicit sign-out, account
  /// deletion, or credentials proven invalid). Never throws.
  Future<void> _clearStoredCredentials() async {
    try {
      await _secureStorage.delete(key: _kSecureEmail);
      await _secureStorage.delete(key: _kSecurePassword);
    } catch (_) {}
  }

  /// The ONE silent re-login attempt of a cold start: signs in
  /// with the secure-storage credentials and, on success,
  /// resolves the gate signed-in through the normal event
  /// handler (marker written, listeners notified — and if the
  /// splash already routed to the login screen, its self-heal
  /// follows the signed-in state home).
  ///
  /// Returns true when a live session was restored. Returns
  /// false when there is nothing to restore with, the attempt
  /// was already made this cold start, or the sign-in failed:
  ///  * network-type failures KEEP the stored credentials — a
  ///    later launch on a working connection can still restore;
  ///  * invalid-credential failures (wrong password, user not
  ///    found, user disabled, invalid email — e.g. the password
  ///    was changed elsewhere) DELETE the stored credentials:
  ///    they can never work again, and the user's next manual
  ///    login re-saves the current ones.
  Future<bool> _tryStoredRestore() async {
    if (_storedRestoreAttempted || _storedRestoreInFlight) {
      return false;
    }
    _storedRestoreAttempted = true;
    _storedRestoreInFlight = true;
    try {
      String? email;
      String? password;
      try {
        email = await _secureStorage.read(key: _kSecureEmail);
        password = await _secureStorage.read(key: _kSecurePassword);
      } catch (_) {
        return false;
      }
      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        return false;
      }
      try {
        final cred = await _authSafe.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final u = cred.user;
        if (u == null) return false;
        debugPrint('AuthService: session restored via stored '
            'credentials (native store was empty)');
        _onAuthEvent(u, source: 'stored-restore');
        return true;
      } on FirebaseAuthException catch (e) {
        switch (e.code) {
          case 'wrong-password':
          case 'invalid-credential':
          case 'user-not-found':
          case 'user-disabled':
          case 'invalid-email':
            await _clearStoredCredentials();
            break;
          default:
            // 'network-request-failed' and anything else:
            // keep the vault for the next launch.
            break;
        }
        return false;
      } catch (_) {
        return false;
      }
    } finally {
      _storedRestoreInFlight = false;
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
      _explicitOut = false;
      _authResolved = true;
      _cancelFuse();
      await _cacheEmail(email.trim());
      await _saveStoredCredentials(email.trim(), pw);
      await _markSession(cred.user!.uid);
      await _clearRestoreMiss();
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
      _explicitOut = false;
      _authResolved = true;
      _cancelFuse();
      await _cacheEmail(email.trim());
      await _saveStoredCredentials(email.trim(), pw);
      await _markSession(cred.user!.uid);
      await _clearRestoreMiss();
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
    // Keep the secure vault in step, or the next cold start
    // would try the OLD password, fail as invalid-credential
    // and wipe the vault (forcing a manual login).
    final email = _user?.email;
    if (email != null) {
      await _saveStoredCredentials(email, newPassword);
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
    await _clearStoredCredentials();
    notifyListeners();
  }

  /// The ONLY sign-out path in the app (explicit Log out button).
  Future<void> signOut() async {
    await _markExplicitSignOut();
    // A deliberate logout must never be silently undone by the
    // app-managed restore: the stored credentials go with it.
    await _clearStoredCredentials();
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
