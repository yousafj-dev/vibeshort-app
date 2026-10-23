import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:vibeshort/models/vibe_notification.dart';
import 'package:vibeshort/models/vibe_user.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/models/vibe_wallet.dart';
import 'package:vibeshort/models/vibe_comment.dart';
import 'package:vibeshort/services/auth_service.dart';

/// Firestore access for VibeShort. All collections are namespaced
/// (`vibeshort_users`, `vibeshort_videos`) inside the shared
/// quizistan-academy Firebase project.
///
/// Every method throws [AuthService.offlineMsg] when Firebase is not
/// ready, so callers can show one friendly message instead of raw
/// errors.
class FirestoreService {
  FirestoreService._();

  static final FirestoreService instance = FirestoreService._();

  FirebaseFirestore? _db;

  FirebaseFirestore get _dbSafe {
    if (!AuthService.firebaseReady) throw Exception(AuthService.offlineMsg);
    _db ??= FirebaseFirestore.instance;
    return _db!;
  }

  CollectionReference get _videos => _dbSafe.collection('vibeshort_videos');

  CollectionReference get _users => _dbSafe.collection('vibeshort_users');

  CollectionReference get _notifications =>
      _dbSafe.collection('vibeshort_notifications');

  CollectionReference _followingCol(String uid) =>
      _users.doc(uid).collection('following');

  // ---------------------------------------------------------------
  // Profiles
  // ---------------------------------------------------------------

  /// Live profile of one user (`vibeshort_users/{uid}`). Emits null
  /// when the doc does not exist yet or Firebase is not ready.
  Stream<VibeUser?> userProfile(String uid) {
    try {
      return _users
          .doc(uid)
          .snapshots()
          .map((doc) => doc.exists ? VibeUser.fromDoc(doc) : null);
    } catch (e) {
      debugPrint('userProfile failed: $e');
      return Stream.value(null);
    }
  }

  /// One-shot read of `vibeshort_users/{uid}`; null when missing.
  Future<VibeUser?> getUserProfile(String uid) async {
    try {
      final doc = await _users.doc(uid).get();
      return doc.exists ? VibeUser.fromDoc(doc) : null;
    } catch (e) {
      debugPrint('getUserProfile failed: $e');
      return null;
    }
  }

  /// True when some account already uses [username] (best-effort
  /// uniqueness check at signup; not transactional).
  Future<bool> usernameTaken(String username) async {
    try {
      final q = await _users
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      return q.docs.isNotEmpty;
    } catch (e) {
      debugPrint('usernameTaken failed: $e');
      return false;
    }
  }

  /// Creates the profile doc for a freshly signed-up user.
  Future<void> createUserProfile({
    required String uid,
    required String displayName,
    required String username,
    required String email,
  }) async {
    await _users.doc(uid).set({
      'displayName': displayName,
      'username': username,
      'photoUrl': '',
      'bio': '',
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Merges the editable profile fields into `vibeshort_users/{uid}`.
  Future<void> updateUserProfile({
    required String uid,
    required String displayName,
    required String photoUrl,
    required String bio,
  }) async {
    await _users.doc(uid).set(
      {
        'displayName': displayName,
        'photoUrl': photoUrl,
        'bio': bio,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ---------------------------------------------------------------
  // Videos
  // ---------------------------------------------------------------

  /// Newest-first video feed.
  Stream<List<VibeVideo>> videoFeed({int limit = 50}) {
    try {
      return _videos
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(VibeVideo.fromDoc).toList());
    } catch (e) {
      debugPrint('videoFeed failed: $e');
      return Stream.value(const []);
    }
  }

  /// Videos uploaded by one user, newest first.
  ///
  /// NOTE: this intentionally does NOT use orderBy in the query —
  /// `where('uid') + orderBy('createdAt')` requires a composite
  /// index that does not exist in this project. The equality filter
  /// uses the automatic single-field index and sorting happens
  /// client-side instead. (Lesson carried over from Chaska.)
  Stream<List<VibeVideo>> userVideos(String uid) {
    try {
      return _videos.where('uid', isEqualTo: uid).snapshots().map((s) {
        final list = s.docs.map(VibeVideo.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
    } catch (e) {
      debugPrint('userVideos failed: $e');
      return Stream.value(const []);
    }
  }

  Future<String> addVideo({
    required String videoUrl,
    required String caption,
  }) async {
    final auth = AuthService.instance;
    final uid = auth.uid;
    if (uid == null) throw Exception('Please log in first.');
    // Prefer the profile doc's username/photo (the user may have
    // edited them); fall back to the auth profile.
    var username = auth.displayName;
    var photo = auth.photoUrl ?? '';
    final profile = await getUserProfile(uid);
    if (profile != null) {
      if (profile.username.isNotEmpty) username = profile.username;
      if (profile.photoUrl.isNotEmpty) photo = profile.photoUrl;
    }
    final doc = await _videos.add(VibeVideo(
      id: '',
      videoUrl: videoUrl,
      caption: caption.trim(),
      uid: uid,
      username: username,
      userPhoto: photo,
      createdAt: DateTime.now(),
    ).toMap());
    return doc.id;
  }

  // ---------------------------------------------------------------
  // Likes & comments
  // ---------------------------------------------------------------

  /// Toggle like for the current user. Returns the new liked state.
  /// A fresh like (not an unlike) also drops a notification in the
  /// video owner's Inbox.
  Future<bool> toggleLike(VibeVideo video) async {
    final myUid = AuthService.instance.uid;
    if (myUid == null) throw Exception('Please log in first.');
    final ref = _videos.doc(video.id);
    final liked = video.likedByMe(myUid);
    try {
      if (liked) {
        await ref.update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([myUid]),
        });
      } else {
        await ref.update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([myUid]),
        });
        await createNotification(
          recipientId: video.uid,
          type: 'like',
          videoId: video.id,
          videoThumb: video.thumbUrl.isEmpty ? null : video.thumbUrl,
        );
      }
      return !liked;
    } catch (e) {
      debugPrint('toggleLike failed: $e');
      rethrow;
    }
  }

  Stream<List<VibeComment>> comments(String videoId) {
    try {
      return _videos
          .doc(videoId)
          .collection('comments')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map((s) => s.docs.map(VibeComment.fromDoc).toList());
    } catch (e) {
      debugPrint('comments failed: $e');
      return Stream.value(const []);
    }
  }

  Future<void> addComment({
    required VibeVideo video,
    required String text,
  }) async {
    final auth = AuthService.instance;
    final myUid = auth.uid;
    if (myUid == null) throw Exception('Please log in first to comment.');
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw Exception('Write something first.');
    // Prefer the profile username so comments match the profile.
    var name = auth.displayName;
    final profile = await getUserProfile(myUid);
    if (profile != null && profile.username.isNotEmpty) {
      name = profile.username;
    }
    await _videos.doc(video.id).collection('comments').add(VibeComment(
          id: '',
          uid: myUid,
          username: name,
          text: trimmed,
          createdAt: DateTime.now(),
        ).toMap());
    await _videos.doc(video.id).update({
      'commentCount': FieldValue.increment(1),
    });
    await createNotification(
      recipientId: video.uid,
      type: 'comment',
      videoId: video.id,
      videoThumb: video.thumbUrl.isEmpty ? null : video.thumbUrl,
      text: trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed,
    );
  }

  // ---------------------------------------------------------------
  // Following (basic — Phase 1)
  // Data: vibeshort_users/{myUid}/following/{targetUid}
  // ---------------------------------------------------------------

  /// Whether the signed-in user follows [targetUid].
  Stream<bool> isFollowing(String targetUid) {
    final myUid = AuthService.instance.uid;
    if (myUid == null) return Stream.value(false);
    try {
      return _followingCol(myUid)
          .doc(targetUid)
          .snapshots()
          .map((d) => d.exists);
    } catch (e) {
      debugPrint('isFollowing failed: $e');
      return Stream.value(false);
    }
  }

  /// Follow / unfollow [targetUid] for the signed-in user. The doc
  /// carries a `targetUid` field so follower counts can be computed
  /// with a collection-group query over `following`.
  Future<void> setFollowing(String targetUid, bool follow) async {
    final myUid = AuthService.instance.uid;
    if (myUid == null) throw Exception('Please log in first.');
    if (follow) {
      await _followingCol(myUid).doc(targetUid).set({
        'targetUid': targetUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await createNotification(recipientId: targetUid, type: 'follow');
    } else {
      await _followingCol(myUid).doc(targetUid).delete();
    }
  }

  /// How many creators [uid] follows — exact aggregate count.
  Stream<int> followingCount(String uid) {
    try {
      return _followingCol(uid).snapshots().asyncMap((_) async {
        final agg = await _followingCol(uid).count().get();
        return agg.count ?? 0;
      });
    } catch (e) {
      debugPrint('followingCount failed: $e');
      return Stream.value(0);
    }
  }

  /// How many users follow [uid]: aggregate count over every
  /// `following` doc whose targetUid is [uid].
  Stream<int> followersCount(String uid) {
    try {
      final q =
          _dbSafe.collectionGroup('following').where('targetUid', isEqualTo: uid);
      return q.snapshots().asyncMap((_) async {
        final agg = await q.count().get();
        return agg.count ?? 0;
      });
    } catch (e) {
      debugPrint('followersCount failed: $e');
      return Stream.value(0);
    }
  }

  // ---------------------------------------------------------------
  // Following feed, search & hashtags (Phase 2)
  // ---------------------------------------------------------------

  /// "Following" home tab: videos posted by everyone the signed-in
  /// user follows, newest first.
  ///
  /// The inner video query deliberately avoids orderBy (a
  /// whereIn + orderBy pair would need a composite index); results
  /// are sorted client-side instead.
  Stream<List<VibeVideo>> followingFeed() {
    final myUid = AuthService.instance.uid;
    if (myUid == null) return Stream.value(const []);
    try {
      return _followingCol(myUid).snapshots().asyncExpand((snap) {
        final uids = snap.docs.map((d) => d.id).toList();
        if (uids.isEmpty) return Stream.value(const <VibeVideo>[]);
        return _videos
            .where('uid', whereIn: uids.take(30).toList())
            .snapshots()
            .map((s) {
          final list = s.docs.map(VibeVideo.fromDoc).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
      });
    } catch (e) {
      debugPrint('followingFeed failed: $e');
      return Stream.value(const []);
    }
  }

  /// All user profiles (bounded) for client-side Discover search —
  /// Firestore has no substring search, so filtering happens in the
  /// UI over this list.
  Stream<List<VibeUser>> allUsers({int limit = 300}) {
    try {
      return _users
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(VibeUser.fromDoc).toList());
    } catch (e) {
      debugPrint('allUsers failed: $e');
      return Stream.value(const []);
    }
  }

  /// Videos carrying [tag] (compared against each video's effective
  /// hashtags, so pre-Phase-2 docs without a stored field still
  /// match via caption parsing). Newest first.
  Stream<List<VibeVideo>> videosByHashtag(String tag) {
    final t = tag.toLowerCase();
    return videoFeed(limit: 300).map((videos) =>
        videos.where((v) => v.effectiveHashtags.contains(t)).toList());
  }

  /// One-shot fetch of a single video (Inbox deep-links).
  Future<VibeVideo?> getVideo(String videoId) async {
    try {
      final doc = await _videos.doc(videoId).get();
      return doc.exists ? VibeVideo.fromDoc(doc) : null;
    } catch (e) {
      debugPrint('getVideo failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------
  // Notifications / Inbox (Phase 2)
  // Data: vibeshort_notifications/{id}
  // ---------------------------------------------------------------

  /// Writes one Inbox entry for [recipientId] from the signed-in
  /// user. Silently skipped for self-actions (liking/commenting on
  /// my own video, following myself) and any failure — a
  /// notification must never break the action that triggered it.
  Future<void> createNotification({
    required String recipientId,
    required String type,
    String? videoId,
    String? videoThumb,
    String? text,
  }) async {
    final auth = AuthService.instance;
    final myUid = auth.uid;
    if (myUid == null || recipientId.isEmpty || recipientId == myUid) {
      return;
    }
    try {
      var name = auth.displayName;
      var photo = auth.photoUrl ?? '';
      final profile = await getUserProfile(myUid);
      if (profile != null) {
        if (profile.username.isNotEmpty) name = profile.username;
        if (profile.photoUrl.isNotEmpty) photo = profile.photoUrl;
      }
      await _notifications.add({
        'recipientId': recipientId,
        'actorId': myUid,
        'actorName': name,
        'actorPhoto': photo,
        'type': type,
        'videoId': videoId,
        'videoThumb': videoThumb,
        'text': text,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('createNotification failed: $e');
    }
  }

  /// My Inbox, newest first. Sorted client-side: a
  /// where + orderBy query would need a composite index.
  Stream<List<VibeNotification>> notifications() {
    final myUid = AuthService.instance.uid;
    if (myUid == null) return Stream.value(const []);
    try {
      return _notifications
          .where('recipientId', isEqualTo: myUid)
          .snapshots()
          .map((s) {
        final list = s.docs.map(VibeNotification.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(80).toList();
      });
    } catch (e) {
      debugPrint('notifications failed: $e');
      return Stream.value(const []);
    }
  }

  /// Live unread count for the Inbox bottom-nav badge.
  Stream<int> unreadNotificationCount() {
    return notifications()
        .map((list) => list.where((n) => !n.read).length);
  }

  /// Marks every unread notification of mine as read (one batch).
  /// Called when the Inbox is opened.
  Future<void> markAllNotificationsRead() async {
    final myUid = AuthService.instance.uid;
    if (myUid == null) return;
    try {
      final q = await _notifications
          .where('recipientId', isEqualTo: myUid)
          .get();
      final unread = q.docs.where((d) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        return (data['read'] ?? false) != true;
      }).toList();
      if (unread.isEmpty) return;
      final batch = _dbSafe.batch();
      for (final d in unread) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('markAllNotificationsRead failed: $e');
    }
  }

  // ---------------------------------------------------------------
  // Wallet, ledger & referrals (Phase 3)
  // Data: vibeshort_wallets/{uid}, vibeshort_transactions/{id},
  //       vibeshort_withdrawal_requests/{id}, vibeshort_referrals/{id}
  //
  // Blueprint Sections 4 + 8: the LEDGER is the source of truth.
  // Balances shown in the app are always derived by summing
  // `vibeshort_transactions`; the wallet doc only caches the same
  // numbers and is refreshed inside the same batched write that
  // adds a ledger entry — a balance is never edited on its own.
  //
  // All list queries filter on ONE field and sort client-side: a
  // where + orderBy pair would need a composite index that does
  // not exist in this project (same lesson as the Following feed).
  // ---------------------------------------------------------------

  CollectionReference get _wallets => _dbSafe.collection('vibeshort_wallets');

  CollectionReference get _transactions =>
      _dbSafe.collection('vibeshort_transactions');

  CollectionReference get _withdrawalRequests =>
      _dbSafe.collection('vibeshort_withdrawal_requests');

  CollectionReference get _referrals =>
      _dbSafe.collection('vibeshort_referrals');

  /// The referral code for [uid]: stored on the profile doc so it
  /// can be looked up at signup. Deterministic from the username +
  /// a uid fragment — stable across calls, unique per account.
  String referralCodeFor(String uid, String username) {
    final base = username.trim().isEmpty
        ? 'USER'
        : username.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final suffix =
        (uid.length >= 6 ? uid.substring(0, 6) : uid).toUpperCase();
    return 'VIBE-$base-$suffix';
  }

  /// Creates `vibeshort_wallets/{uid}` with zero balances when it
  /// does not exist yet, and makes sure the profile doc carries a
  /// referral code. Safe to call every time the Wallet opens —
  /// existing data is never overwritten.
  Future<void> ensureWalletAndReferralCode() async {
    final uid = AuthService.instance.uid;
    if (uid == null) return;
    try {
      final wref = _wallets.doc(uid);
      final w = await wref.get();
      if (!w.exists) {
        await wref.set({
          'user_id': uid,
          'currency': WalletRules.currency,
          'cached_pending': 0,
          'cached_available': 0,
          'cached_paid': 0,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      final uref = _users.doc(uid);
      final u = await uref.get();
      final data = u.data() as Map<String, dynamic>? ?? {};
      final existing = (data['referralCode'] ?? '') as String;
      if (existing.isEmpty) {
        final username = (data['username'] ?? '') as String;
        await uref.set(
          {'referralCode': referralCodeFor(uid, username)},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint('ensureWalletAndReferralCode failed: $e');
    }
  }

  /// My referral code, live (empty until the profile doc has one).
  Stream<String> myReferralCode() {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value('');
    try {
      return _users.doc(uid).snapshots().map((doc) {
        final d = doc.data() as Map<String, dynamic>? ?? {};
        return (d['referralCode'] ?? '') as String;
      });
    } catch (e) {
      debugPrint('myReferralCode failed: $e');
      return Stream.value('');
    }
  }

  /// My full ledger, newest first (bounded). Balances are derived
  /// from this list via [WalletBalances.fromTransactions].
  Stream<List<VibeTransaction>> myTransactions() {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value(const []);
    try {
      return _transactions
          .where('user_id', isEqualTo: uid)
          .snapshots()
          .map((s) {
        final list = s.docs.map(VibeTransaction.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(100).toList();
      });
    } catch (e) {
      debugPrint('myTransactions failed: $e');
      return Stream.value(const []);
    }
  }

  /// My withdrawal requests, newest first.
  Stream<List<VibeWithdrawal>> myWithdrawals() {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value(const []);
    try {
      return _withdrawalRequests
          .where('user_id', isEqualTo: uid)
          .snapshots()
          .map((s) {
        final list = s.docs.map(VibeWithdrawal.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(50).toList();
      });
    } catch (e) {
      debugPrint('myWithdrawals failed: $e');
      return Stream.value(const []);
    }
  }

  /// People who signed up with MY referral code.
  Stream<List<VibeReferral>> myReferrals() {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value(const []);
    try {
      return _referrals
          .where('referrer_id', isEqualTo: uid)
          .snapshots()
          .map((s) {
        final list = s.docs.map(VibeReferral.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(100).toList();
      });
    } catch (e) {
      debugPrint('myReferrals failed: $e');
      return Stream.value(const []);
    }
  }

  /// Submits a withdrawal request (blueprint Section 3 journey):
  /// the user checks their AVAILABLE balance against the minimum
  /// payout rule, then submits amount + payout method + account
  /// number. Writes, in ONE batch:
  ///   1. the request doc (status: pending review — approvals are
  ///      the later Admin phase, never faked here),
  ///   2. the matching ledger entry (type withdrawal, negative
  ///      amount, status pending = funds on hold),
  ///   3. the wallet doc's refreshed cached balances.
  /// The [idempotencyKey] makes a double-tap or a retried submit
  /// return the existing request instead of creating a duplicate
  /// (blueprint Section 4).
  Future<void> submitWithdrawal({
    required double amount,
    required String payoutMethod,
    required String payoutAccount,
    required String idempotencyKey,
  }) async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    if (amount < WalletRules.minWithdrawalPkr) {
      throw Exception(
          'Minimum withdrawal is ${formatPkr(WalletRules.minWithdrawalPkr.toDouble())}.');
    }
    final account = payoutAccount.replaceAll(RegExp(r'[^0-9]'), '');
    if (account.length < 10 || account.length > 15) {
      throw Exception('Please enter a valid account number.');
    }
    // Idempotency: same key already submitted -> nothing to do.
    final dup = await _withdrawalRequests
        .where('idempotency_key', isEqualTo: idempotencyKey)
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) return;
    // Available balance derived from the ledger, never from a
    // stored editable number.
    final txSnap =
        await _transactions.where('user_id', isEqualTo: uid).get();
    final txs = txSnap.docs.map(VibeTransaction.fromDoc).toList();
    final balances = WalletBalances.fromTransactions(txs);
    if (amount > balances.available) {
      throw Exception(
          'Insufficient available balance. Pending rewards cannot be withdrawn.');
    }
    final reqRef = _withdrawalRequests.doc();
    final txRef = _transactions.doc();
    final now = DateTime.now();
    final hold = VibeTransaction(
      id: txRef.id,
      userId: uid,
      type: 'withdrawal',
      amount: -amount,
      status: 'pending',
      idempotencyKey: idempotencyKey,
      reference: reqRef.id,
      createdAt: now,
    );
    final newBalances =
        WalletBalances.fromTransactions([...txs, hold]);
    final batch = _dbSafe.batch();
    batch.set(reqRef, {
      'user_id': uid,
      'amount': amount,
      'currency': WalletRules.currency,
      'payout_method': payoutMethod,
      'payout_account': account,
      'status': VibeWithdrawal.statusPendingReview,
      'idempotency_key': idempotencyKey,
      'reviewed_at': null,
      'created_at': FieldValue.serverTimestamp(),
    });
    batch.set(txRef, {
      'user_id': uid,
      'type': 'withdrawal',
      'amount': -amount,
      'currency': WalletRules.currency,
      'status': 'pending',
      'idempotency_key': idempotencyKey,
      'reference': reqRef.id,
      'created_at': FieldValue.serverTimestamp(),
    });
    batch.set(
      _wallets.doc(uid),
      {
        'user_id': uid,
        'currency': WalletRules.currency,
        'cached_pending': newBalances.pending,
        'cached_available': newBalances.available,
        'cached_paid': newBalances.paid,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Records a referral for a freshly signed-up user who entered
  /// someone's code (blueprint Section 8). Best-effort and silent:
  /// an unknown code, a self-referral, or a duplicate sign-up
  /// simply records nothing, and a failure here must NEVER break
  /// signup. No reward is created — qualification is decided
  /// later under the published rules, with abuse checks.
  Future<void> recordReferral({
    required String newUid,
    required String rawCode,
  }) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) return;
    try {
      final q = await _users
          .where('referralCode', isEqualTo: code)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return;
      final referrerId = q.docs.first.id;
      if (referrerId == newUid) return;
      final existing = await _referrals
          .where('referred_user_id', isEqualTo: newUid)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return;
      await _referrals.add({
        'referrer_id': referrerId,
        'referred_user_id': newUid,
        'code': code,
        'qualification_status': 'pending',
        'reward_transaction_id': null,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('recordReferral failed: $e');
    }
  }
}
