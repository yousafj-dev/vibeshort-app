import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:vibeshort/models/vibe_moderation.dart';
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
      // Phase 4 safety defaults (blueprint Sections 5 + 9). The
      // role is only ever CHANGED directly in Firestore — no app
      // UI can grant admin.
      'role': 'user',
      'status': 'active',
      'suspensionReason': '',
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

  /// Newest-first video feed. Phase 4: removed videos and videos
  /// from creators the signed-in user blocked are filtered out.
  /// Settings pack: private accounts' videos are filtered out
  /// too (see [_isVisible]).
  Stream<List<VibeVideo>> videoFeed({int limit = 50}) {
    _ensureBlockedCache();
    _ensurePrivacyCaches();
    try {
      return _videos
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs
              .map(VibeVideo.fromDoc)
              .where(_isVisible)
              .toList());
    } catch (e) {
      debugPrint('videoFeed failed: $e');
      return Stream.value(const []);
    }
  }

  /// Whether [v] may appear in a feed for the signed-in user:
  /// not removed by moderation, not posted by someone they
  /// blocked, and — for a private account's video — only when
  /// the viewer is the owner or follows the owner.
  bool _isVisible(VibeVideo v) {
    if (v.isRemoved) return false;
    if (_blockedIdsCache.contains(v.uid)) return false;
    final myUid = AuthService.instance.uid;
    if (v.uid != myUid &&
        _privateIdsCache.contains(v.uid) &&
        !_myFollowingCache.contains(v.uid)) {
      return false;
    }
    return true;
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
        final list = s.docs
            .map(VibeVideo.fromDoc)
            .where((v) => !v.isRemoved)
            .toList()
          ..sort((a, b) {
            // Fix round: pinned videos first (most recently
            // pinned first), then newest first.
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            if (a.pinned && b.pinned) {
              final pa = a.pinnedAt ?? a.createdAt;
              final pb = b.pinnedAt ?? b.createdAt;
              return pb.compareTo(pa);
            }
            return b.createdAt.compareTo(a.createdAt);
          });
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
    String? soundName,
    String? soundId,
    String? soundSourceVideoId,
    String? soundOwnerId,
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
      // Phase 4 (blueprint Section 9): a suspended account cannot
      // post. The app shell already shows the suspended screen;
      // this is the service-level backstop.
      if (profile.isSuspended) {
        throw Exception(
            'Your account is suspended. You cannot post videos.');
      }
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
      // Editing phase: a video posted with picked music is named
      // after that track; everything else keeps the default.
      soundName: (soundName != null && soundName.trim().isNotEmpty)
          ? soundName.trim()
          : 'Original sound',
      // Fix round: built-in sound attribution, stored alongside
      // the display name so the sound can be re-opened later.
      soundId: soundId ?? '',
      // Sound page round: "Use this sound" attribution when the
      // audio came from another video's original sound.
      soundSourceVideoId: soundSourceVideoId ?? '',
      soundOwnerId: soundOwnerId ?? '',
      createdAt: DateTime.now(),
    ).toMap());
    return doc.id;
  }

  // ---------------------------------------------------------------
  // Own-video management (fix round)
  // ---------------------------------------------------------------

  /// Edits the caption (and its derived hashtags) of one of MY
  /// videos. Ownership is verified against the signed-in uid.
  Future<void> updateVideoCaption(String videoId, String caption) async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    final ref = _videos.doc(videoId);
    final doc = await ref.get();
    if (!doc.exists) throw Exception('Video not found.');
    final data = doc.data() as Map<String, dynamic>? ?? {};
    if ((data['uid'] ?? '') != uid) {
      throw Exception('You can only edit your own videos.');
    }
    final trimmed = caption.trim();
    await ref.update({
      'caption': trimmed,
      'hashtags': VibeVideo.parseHashtags(trimmed),
    });
  }

  /// Pins / unpins one of MY videos on my profile grid.
  Future<void> setVideoPinned(String videoId, bool pinned) async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    final ref = _videos.doc(videoId);
    final doc = await ref.get();
    if (!doc.exists) throw Exception('Video not found.');
    final data = doc.data() as Map<String, dynamic>? ?? {};
    if ((data['uid'] ?? '') != uid) {
      throw Exception('You can only pin your own videos.');
    }
    await ref.update({
      'pinned': pinned,
      'pinnedAt': pinned ? FieldValue.serverTimestamp() : null,
    });
  }

  /// Deletes one of MY videos: its comments go first (bounded
  /// batch), then the video doc itself, which removes it from
  /// every feed and profile. The Cloudinary media file is NOT
  /// deleted — uploads use an unsigned preset, which cannot
  /// delete assets; the orphaned file is unreachable once the
  /// doc is gone.
  Future<void> deleteOwnVideo(String videoId) async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    final ref = _videos.doc(videoId);
    final doc = await ref.get();
    if (!doc.exists) throw Exception('Video not found.');
    final data = doc.data() as Map<String, dynamic>? ?? {};
    if ((data['uid'] ?? '') != uid) {
      throw Exception('You can only delete your own videos.');
    }
    try {
      final comments = await ref.collection('comments').limit(200).get();
      if (comments.docs.isNotEmpty) {
        final batch = _dbSafe.batch();
        for (final c in comments.docs) {
          batch.delete(c.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      // Comment cleanup is best-effort; deleting the video doc
      // itself is what removes it from every feed.
      debugPrint('deleteOwnVideo comments cleanup failed: $e');
    }
    await ref.delete();
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
    _ensureBlockedCache();
    _ensurePrivacyCaches();
    try {
      return _followingCol(myUid).snapshots().asyncExpand((snap) {
        final uids = snap.docs.map((d) => d.id).toList();
        if (uids.isEmpty) return Stream.value(const <VibeVideo>[]);
        return _videos
            .where('uid', whereIn: uids.take(30).toList())
            .snapshots()
            .map((s) {
          final list = s.docs
              .map(VibeVideo.fromDoc)
              .where(_isVisible)
              .toList()
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

  // ---------------------------------------------------------------
  // Sound pages (sound page round)
  // ---------------------------------------------------------------

  /// All videos using one built-in library sound, newest first.
  /// Like [userVideos], the query avoids orderBy (no composite
  /// index exists for it) and sorting happens client-side.
  Stream<List<VibeVideo>> videosWithSoundId(String soundId) {
    _ensureBlockedCache();
    _ensurePrivacyCaches();
    try {
      return _videos
          .where('soundId', isEqualTo: soundId)
          .snapshots()
          .map((s) => s.docs
              .map(VibeVideo.fromDoc)
              .where(_isVisible)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    } catch (e) {
      debugPrint('videosWithSoundId failed: $e');
      return Stream.value(const []);
    }
  }

  /// All videos made with "Use this sound" on one ORIGINAL
  /// sound — i.e. whose audio source is the video
  /// [sourceVideoId]. The source video itself is NOT part of
  /// this result; the sound page adds it as the first tile.
  Stream<List<VibeVideo>> videosUsingOriginalSound(String sourceVideoId) {
    _ensureBlockedCache();
    _ensurePrivacyCaches();
    try {
      return _videos
          .where('soundSourceVideoId', isEqualTo: sourceVideoId)
          .snapshots()
          .map((s) => s.docs
              .map(VibeVideo.fromDoc)
              .where(_isVisible)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    } catch (e) {
      debugPrint('videosUsingOriginalSound failed: $e');
      return Stream.value(const []);
    }
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

  // ---------------------------------------------------------------
  // Safety: reports & blocks (Phase 4)
  // Data: vibeshort_reports/{id}, vibeshort_blocks/{id}
  //
  // Blueprint Section 9 (report + block mechanisms) and Section 8
  // (reports schema). Blocks are stored as flat docs
  // `{blocker_id}_{blocked_id}`; a blocked creator's videos are
  // filtered out of every feed the blocker sees.
  // ---------------------------------------------------------------

  CollectionReference get _reports => _dbSafe.collection('vibeshort_reports');

  CollectionReference get _blocks => _dbSafe.collection('vibeshort_blocks');

  CollectionReference get _auditLogs =>
      _dbSafe.collection('vibeshort_audit_logs');

  CollectionReference get _settingsCol =>
      _dbSafe.collection('vibeshort_settings');

  /// In-memory cache of the creators the signed-in user blocked,
  /// kept fresh by a snapshot listener so feed filters stay cheap.
  Set<String> _blockedIdsCache = {};
  String? _blockedCacheUid;
  StreamSubscription<QuerySnapshot>? _blockedSub;

  void _ensureBlockedCache() {
    final uid = AuthService.instance.uid;
    if (uid == null) {
      _blockedIdsCache = {};
      return;
    }
    if (_blockedCacheUid == uid) return;
    _blockedCacheUid = uid;
    _blockedIdsCache = {};
    _blockedSub?.cancel();
    try {
      _blockedSub = _blocks
          .where('blocker_id', isEqualTo: uid)
          .snapshots()
          .listen((s) {
        _blockedIdsCache = s.docs
            .map((d) =>
                ((d.data() as Map<String, dynamic>? ?? {})['blocked_id'] ??
                        '')
                    .toString())
            .where((id) => id.isNotEmpty)
            .toSet();
      }, onError: (Object e) => debugPrint('blocked cache failed: $e'));
    } catch (e) {
      debugPrint('blocked cache setup failed: $e');
    }
  }

  /// Whether the signed-in user has blocked [targetUid] (live).
  Stream<bool> isBlocked(String targetUid) {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value(false);
    try {
      return _blocks
          .doc('${uid}_$targetUid')
          .snapshots()
          .map((d) => d.exists);
    } catch (e) {
      debugPrint('isBlocked failed: $e');
      return Stream.value(false);
    }
  }

  /// Blocks [targetUid]: their videos disappear from my feeds and
  /// I stop following them.
  Future<void> blockUser(String targetUid) async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    if (targetUid == uid) {
      throw Exception('You cannot block your own account.');
    }
    await _blocks.doc('${uid}_$targetUid').set({
      'blocker_id': uid,
      'blocked_id': targetUid,
      'created_at': FieldValue.serverTimestamp(),
    });
    _blockedIdsCache = {..._blockedIdsCache, targetUid};
    try {
      await setFollowing(targetUid, false);
    } catch (_) {
      // Unfollow is best-effort; the block itself already stands.
    }
  }

  Future<void> unblockUser(String targetUid) async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    await _blocks.doc('${uid}_$targetUid').delete();
    _blockedIdsCache = {..._blockedIdsCache}..remove(targetUid);
  }

  /// Submits a report (blueprint Section 9). One open report per
  /// reporter per target: a repeat submit quietly succeeds without
  /// creating a duplicate queue entry.
  Future<void> submitReport({
    required String targetType,
    required String targetId,
    required String targetOwnerId,
    required String reason,
  }) async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    final existing = await _reports
        .where('reporter_id', isEqualTo: uid)
        .where('target_id', isEqualTo: targetId)
        .where('status', isEqualTo: VibeReport.statusOpen)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;
    await _reports.add({
      'reporter_id': uid,
      'target_type': targetType,
      'target_id': targetId,
      'target_owner_id': targetOwnerId,
      'reason': reason,
      'status': VibeReport.statusOpen,
      'resolution': '',
      'resolved_by': '',
      'resolved_at': null,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------
  // Admin panel (Phase 4)
  // Blueprint Section 5 modules + Section 9 moderation. EVERY
  // action first verifies the signed-in user's role in Firestore
  // ([_assertAdmin]) and writes an audit entry
  // (`vibeshort_audit_logs`). Balance changes go ONLY through
  // ledger entries — the same rule as Phase 3: approving a
  // withdrawal flips its hold entry to 'paid', rejecting flips it
  // to 'rejected'; the wallet cache is refreshed in the same
  // batch from the recomputed ledger.
  // ---------------------------------------------------------------

  /// Live admin check for UI gating: true only while the signed-in
  /// user's own doc carries role == 'admin'.
  Stream<bool> myIsAdmin() {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value(false);
    return userProfile(uid).map((p) => p?.isAdmin ?? false);
  }

  /// Hard gate used by every admin action: re-reads the caller's
  /// own profile doc and refuses when the role is not admin.
  Future<String> _assertAdmin() async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    final profile = await getUserProfile(uid);
    if (profile == null || !profile.isAdmin) {
      throw Exception('Admin access required.');
    }
    return uid;
  }

  /// Appends one audit entry. Called inside the same flow as the
  /// action it records (blueprint Section 5: audit trail).
  Future<void> _writeAudit(
    String adminId, {
    required String action,
    required String targetType,
    required String targetId,
    String reason = '',
  }) async {
    await _auditLogs.add({
      'admin_id': adminId,
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ---- Dashboard ----

  Future<int> _countAll(CollectionReference col) async {
    final agg = await col.count().get();
    return agg.count ?? 0;
  }

  Future<int> _countWhere(
      CollectionReference col, String field, Object value) async {
    final agg = await col.where(field, isEqualTo: value).count().get();
    return agg.count ?? 0;
  }

  /// Dashboard totals (blueprint Section 5: user totals, uploads,
  /// views, reports). Views are summed over a bounded recent slice
  /// of videos (no per-view counter collection exists).
  Future<Map<String, int>> adminDashboardTotals() async {
    await _assertAdmin();
    final results = await Future.wait([
      _countAll(_users),
      _countAll(_videos),
      _countWhere(_reports, 'status', VibeReport.statusOpen),
      _countWhere(_withdrawalRequests, 'status',
          VibeWithdrawal.statusPendingReview),
    ]);
    var views = 0;
    try {
      final snap = await _videos.limit(500).get();
      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        views += (data['views'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint('adminDashboardTotals views failed: $e');
    }
    return {
      'users': results[0],
      'videos': results[1],
      'openReports': results[2],
      'pendingWithdrawals': results[3],
      'views': views,
    };
  }

  // ---- Reports queue & video moderation ----

  /// All reports, open first then newest (client-side ordering —
  /// where + orderBy would need a composite index).
  Stream<List<VibeReport>> adminReports() {
    try {
      return _reports.limit(300).snapshots().map((s) {
        final list = s.docs.map(VibeReport.fromDoc).toList()
          ..sort((a, b) {
            if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
        return list;
      });
    } catch (e) {
      debugPrint('adminReports failed: $e');
      return Stream.value(const []);
    }
  }

  /// Open reports for one target (video moderation actions act on
  /// the video's whole open queue).
  Future<List<QueryDocumentSnapshot>> _openReportsFor(
      String targetType, String targetId) async {
    final q = await _reports
        .where('target_type', isEqualTo: targetType)
        .where('target_id', isEqualTo: targetId)
        .where('status', isEqualTo: VibeReport.statusOpen)
        .get();
    return q.docs;
  }

  /// Resolves or dismisses one report, recording the decision
  /// reason (blueprint Section 5: "decision reason ... audit
  /// trail").
  Future<void> resolveReport(
    VibeReport report, {
    required bool dismiss,
    required String reason,
  }) async {
    final adminId = await _assertAdmin();
    final status =
        dismiss ? VibeReport.statusDismissed : VibeReport.statusResolved;
    await _reports.doc(report.id).update({
      'status': status,
      'resolution': reason,
      'resolved_by': adminId,
      'resolved_at': FieldValue.serverTimestamp(),
    });
    await _writeAudit(
      adminId,
      action: dismiss ? 'report_dismiss' : 'report_resolve',
      targetType: 'report',
      targetId: report.id,
      reason: reason,
    );
  }

  /// Video moderation — Keep: the video stays; its open reports
  /// are dismissed with the review decision recorded.
  Future<void> keepVideo(String videoId, {required String reason}) async {
    final adminId = await _assertAdmin();
    final open = await _openReportsFor('video', videoId);
    final batch = _dbSafe.batch();
    for (final d in open) {
      batch.update(d.reference, {
        'status': VibeReport.statusDismissed,
        'resolution': reason,
        'resolved_by': adminId,
        'resolved_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await _writeAudit(
      adminId,
      action: 'video_keep',
      targetType: 'video',
      targetId: videoId,
      reason: reason,
    );
  }

  /// Video moderation — Remove: moderation_status becomes
  /// 'removed', which filters the video out of every feed; its
  /// open reports are resolved as actioned.
  Future<void> removeVideo(String videoId, {required String reason}) async {
    final adminId = await _assertAdmin();
    await _videos.doc(videoId).update({'moderationStatus': 'removed'});
    final open = await _openReportsFor('video', videoId);
    if (open.isNotEmpty) {
      final batch = _dbSafe.batch();
      for (final d in open) {
        batch.update(d.reference, {
          'status': VibeReport.statusResolved,
          'resolution': 'Video removed. $reason'.trim(),
          'resolved_by': adminId,
          'resolved_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    await _writeAudit(
      adminId,
      action: 'video_remove',
      targetType: 'video',
      targetId: videoId,
      reason: reason,
    );
  }

  // ---- User management ----

  /// Suspends an account with a recorded reason (blueprint
  /// Section 5). The suspended user sees the suspended screen and
  /// cannot post.
  Future<void> suspendUser(String targetUid,
      {required String reason}) async {
    final adminId = await _assertAdmin();
    if (targetUid == adminId) {
      throw Exception('You cannot suspend your own admin account.');
    }
    await _users.doc(targetUid).set(
      {
        'status': 'suspended',
        'suspensionReason': reason,
        'suspendedBy': adminId,
        'suspendedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await _writeAudit(
      adminId,
      action: 'user_suspend',
      targetType: 'user',
      targetId: targetUid,
      reason: reason,
    );
  }

  Future<void> restoreUser(String targetUid) async {
    final adminId = await _assertAdmin();
    await _users.doc(targetUid).set(
      {
        'status': 'active',
        'suspensionReason': '',
        'restoredBy': adminId,
        'restoredAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await _writeAudit(
      adminId,
      action: 'user_restore',
      targetType: 'user',
      targetId: targetUid,
    );
  }

  // ---- Withdrawals review ----

  /// All withdrawal requests for the Admin panel, pending review
  /// first, then newest.
  Stream<List<VibeWithdrawal>> adminWithdrawals() {
    try {
      return _withdrawalRequests.limit(200).snapshots().map((s) {
        final list = s.docs.map(VibeWithdrawal.fromDoc).toList()
          ..sort((a, b) {
            final ap = a.status == VibeWithdrawal.statusPendingReview;
            final bp = b.status == VibeWithdrawal.statusPendingReview;
            if (ap != bp) return ap ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
        return list;
      });
    } catch (e) {
      debugPrint('adminWithdrawals failed: $e');
      return Stream.value(const []);
    }
  }

  /// All referrals for the Admin panel, newest first.
  Stream<List<VibeReferral>> adminReferrals() {
    try {
      return _referrals.limit(300).snapshots().map((s) {
        final list = s.docs.map(VibeReferral.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
    } catch (e) {
      debugPrint('adminReferrals failed: $e');
      return Stream.value(const []);
    }
  }

  /// The single ledger hold entry created with a withdrawal
  /// request (type 'withdrawal', reference = request id).
  Future<QueryDocumentSnapshot?> _withdrawalHold(String requestId) async {
    final q = await _transactions
        .where('type', isEqualTo: 'withdrawal')
        .where('reference', isEqualTo: requestId)
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : q.docs.first;
  }

  /// Refreshes a wallet doc's cached balances inside [batch],
  /// recomputed from the full ledger with [statusOverrides]
  /// applied (the batch's own writes are not visible to reads
  /// yet, so the pending hold flip is applied in memory).
  Future<void> _refreshWalletCacheInBatch(
    WriteBatch batch,
    String uid, {
    Map<String, String> statusOverrides = const {},
  }) async {
    final snap = await _transactions.where('user_id', isEqualTo: uid).get();
    final txs = snap.docs.map((d) {
      final t = VibeTransaction.fromDoc(d);
      final override = statusOverrides[t.id];
      if (override == null) return t;
      return VibeTransaction(
        id: t.id,
        userId: t.userId,
        type: t.type,
        amount: t.amount,
        currency: t.currency,
        status: override,
        idempotencyKey: t.idempotencyKey,
        reference: t.reference,
        createdAt: t.createdAt,
      );
    }).toList();
    final b = WalletBalances.fromTransactions(txs);
    batch.set(
      _wallets.doc(uid),
      {
        'user_id': uid,
        'currency': WalletRules.currency,
        'cached_pending': b.pending,
        'cached_available': b.available,
        'cached_paid': b.paid,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Approves a pending withdrawal (blueprint Sections 4 + 5):
  /// records the provider reference, flips the request to 'paid'
  /// and its ledger hold to 'paid' in one batch. Idempotent: an
  /// already-reviewed request is left untouched, so a double tap
  /// can never pay twice.
  Future<void> approveWithdrawal(
    VibeWithdrawal w, {
    required String providerReference,
  }) async {
    final adminId = await _assertAdmin();
    final reqRef = _withdrawalRequests.doc(w.id);
    final fresh = await reqRef.get();
    if (!fresh.exists) throw Exception('Request not found.');
    final current = VibeWithdrawal.fromDoc(fresh);
    if (current.status != VibeWithdrawal.statusPendingReview) return;
    final hold = await _withdrawalHold(w.id);
    if (hold == null) {
      throw Exception('Ledger hold entry not found for this request.');
    }
    final batch = _dbSafe.batch();
    batch.update(reqRef, {
      'status': VibeWithdrawal.statusPaid,
      'provider_reference': providerReference,
      'reviewed_by': adminId,
      'reviewed_at': FieldValue.serverTimestamp(),
    });
    batch.update(hold.reference, {'status': 'paid'});
    await _refreshWalletCacheInBatch(batch, current.userId,
        statusOverrides: {hold.id: 'paid'});
    await batch.commit();
    await _writeAudit(
      adminId,
      action: 'withdrawal_approve',
      targetType: 'withdrawal',
      targetId: w.id,
      reason: 'Provider reference: $providerReference',
    );
  }

  /// Rejects a pending withdrawal: the request is marked rejected
  /// with the reason and the ledger hold flips to 'rejected',
  /// which releases the held funds back to the user's available
  /// balance (ledger-derived, exactly as Phase 3 defined).
  Future<void> rejectWithdrawal(
    VibeWithdrawal w, {
    required String reason,
  }) async {
    final adminId = await _assertAdmin();
    final reqRef = _withdrawalRequests.doc(w.id);
    final fresh = await reqRef.get();
    if (!fresh.exists) throw Exception('Request not found.');
    final current = VibeWithdrawal.fromDoc(fresh);
    if (current.status != VibeWithdrawal.statusPendingReview) return;
    final hold = await _withdrawalHold(w.id);
    if (hold == null) {
      throw Exception('Ledger hold entry not found for this request.');
    }
    final batch = _dbSafe.batch();
    batch.update(reqRef, {
      'status': VibeWithdrawal.statusRejected,
      'review_reason': reason,
      'reviewed_by': adminId,
      'reviewed_at': FieldValue.serverTimestamp(),
    });
    batch.update(hold.reference, {'status': 'rejected'});
    await _refreshWalletCacheInBatch(batch, current.userId,
        statusOverrides: {hold.id: 'rejected'});
    await batch.commit();
    await _writeAudit(
      adminId,
      action: 'withdrawal_reject',
      targetType: 'withdrawal',
      targetId: w.id,
      reason: reason,
    );
  }

  // ---- Referral controls ----

  /// Marks a referral ineligible (blueprint Section 5: track
  /// referrals, detect abuse, reverse ineligible rewards). Phase
  /// 3 created no reward money, so this records the status change
  /// plus the audit entry; if a reward transaction ever exists
  /// for it, its id stays on the referral doc for reversal.
  Future<void> markReferralIneligible(
    VibeReferral referral, {
    required String reason,
  }) async {
    final adminId = await _assertAdmin();
    await _referrals.doc(referral.id).update({
      'qualification_status': 'rejected',
      'reviewed_by': adminId,
      'reviewed_at': FieldValue.serverTimestamp(),
    });
    await _writeAudit(
      adminId,
      action: 'referral_ineligible',
      targetType: 'referral',
      targetId: referral.id,
      reason: reason,
    );
  }

  // ---- Audit log & app settings ----

  /// The audit trail, newest first (read-only in the panel).
  Stream<List<VibeAuditLog>> auditLogs() {
    try {
      return _auditLogs.limit(200).snapshots().map((s) {
        final list = s.docs.map(VibeAuditLog.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
    } catch (e) {
      debugPrint('auditLogs failed: $e');
      return Stream.value(const []);
    }
  }

  /// Live app settings (maintenance notice). Emits defaults when
  /// the doc does not exist or Firebase is not ready.
  Stream<VibeSettings> appSettings() {
    try {
      return _settingsCol
          .doc('app')
          .snapshots()
          .map((d) => d.exists ? VibeSettings.fromDoc(d) : const VibeSettings());
    } catch (e) {
      debugPrint('appSettings failed: $e');
      return Stream.value(const VibeSettings());
    }
  }

  Future<void> updateAppSettings({
    required bool maintenanceOn,
    required String maintenanceNotice,
  }) async {
    final adminId = await _assertAdmin();
    await _settingsCol.doc('app').set({
      'maintenance_on': maintenanceOn,
      'maintenance_notice': maintenanceNotice.trim(),
      'updated_by': adminId,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await _writeAudit(
      adminId,
      action: 'settings_update',
      targetType: 'settings',
      targetId: 'app',
      reason: maintenanceOn
          ? 'Maintenance notice ON: ${maintenanceNotice.trim()}'
          : 'Maintenance notice OFF',
    );
  }

  // ---------------------------------------------------------------
  // Settings pack: privacy caches, preferences, activity,
  // views and account deletion.
  // ---------------------------------------------------------------

  /// Ids of accounts whose profile is private, kept fresh by a
  /// snapshot listener so [_isVisible] stays cheap (same pattern
  /// as the blocked cache above).
  Set<String> _privateIdsCache = {};

  /// Ids the signed-in user follows, for the same filter.
  Set<String> _myFollowingCache = {};
  String? _privacyCacheUid;
  StreamSubscription<QuerySnapshot>? _privateSub;
  StreamSubscription<QuerySnapshot>? _followingCacheSub;

  void _ensurePrivacyCaches() {
    final uid = AuthService.instance.uid;
    if (uid == null) {
      _privateIdsCache = {};
      _myFollowingCache = {};
      return;
    }
    if (_privacyCacheUid == uid) return;
    _privacyCacheUid = uid;
    _privateIdsCache = {};
    _myFollowingCache = {};
    _privateSub?.cancel();
    _followingCacheSub?.cancel();
    try {
      _privateSub = _users
          .where('isPrivate', isEqualTo: true)
          .snapshots()
          .listen((s) {
        _privateIdsCache = s.docs.map((d) => d.id).toSet();
      }, onError: (Object e) => debugPrint('private cache failed: $e'));
      _followingCacheSub = _followingCol(uid).snapshots().listen((s) {
        _myFollowingCache = s.docs.map((d) => d.id).toSet();
      },
          onError: (Object e) =>
              debugPrint('following cache failed: $e'));
    } catch (e) {
      debugPrint('privacy cache setup failed: $e');
    }
  }

  /// Merges settings/preference fields into my profile doc
  /// (`isPrivate`, `notifLikes`, visibility prefs...).
  Future<void> updateMySettings(Map<String, dynamic> fields) async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    await _users.doc(uid).set(
      {...fields, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Videos I liked (Activity center), newest first. Removed
  /// videos are filtered out.
  Stream<List<VibeVideo>> likedVideos() {
    final myUid = AuthService.instance.uid;
    if (myUid == null) return Stream.value(const []);
    try {
      return _videos
          .where('likedBy', arrayContains: myUid)
          .snapshots()
          .map((s) {
        final list = s.docs
            .map(VibeVideo.fromDoc)
            .where((v) => !v.isRemoved)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
    } catch (e) {
      debugPrint('likedVideos failed: $e');
      return Stream.value(const []);
    }
  }

  CollectionReference _historyCol(String uid) =>
      _users.doc(uid).collection('history');

  /// Records that the signed-in user watched [videoId] now
  /// (Activity center → Watch history). Best-effort: a failed
  /// write must never disturb playback.
  Future<void> recordWatch(String videoId) async {
    final uid = AuthService.instance.uid;
    if (uid == null || videoId.isEmpty) return;
    try {
      await _historyCol(uid).doc(videoId).set({
        'videoId': videoId,
        'watchedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('recordWatch failed: $e');
    }
  }

  /// My watch history, most recently watched first (bounded).
  /// Entries whose video was deleted or removed are skipped.
  Stream<List<VibeVideo>> watchHistory({int limit = 60}) {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value(const []);
    try {
      return _historyCol(uid).snapshots().asyncMap((snap) async {
        final entries = snap.docs.map((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final ts = data['watchedAt'];
          return (
            id: (data['videoId'] ?? d.id).toString(),
            at: ts is Timestamp ? ts.toDate() : DateTime(2000),
          );
        }).toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        final out = <VibeVideo>[];
        for (final e in entries.take(limit)) {
          final v = await getVideo(e.id);
          if (v != null && !v.isRemoved) out.add(v);
        }
        return out;
      });
    } catch (e) {
      debugPrint('watchHistory failed: $e');
      return Stream.value(const []);
    }
  }

  /// Videos already counted as viewed in this app session — the
  /// view counter moves at most once per video per session.
  final Set<String> _viewedThisSession = {};

  /// Counts one view of [video] for the Creator dashboard: only
  /// for a non-owner viewer, only once per session per video.
  Future<void> recordView(VibeVideo video) async {
    final myUid = AuthService.instance.uid;
    if (myUid == null || video.uid == myUid) return;
    if (!_viewedThisSession.add(video.id)) return;
    try {
      await _videos
          .doc(video.id)
          .update({'views': FieldValue.increment(1)});
    } catch (e) {
      debugPrint('recordView failed: $e');
    }
  }

  /// Users I blocked (Settings → Blocked accounts), with their
  /// profiles resolved.
  Stream<List<VibeUser>> blockedUsers() {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value(const []);
    try {
      return _blocks
          .where('blocker_id', isEqualTo: uid)
          .snapshots()
          .asyncMap((snap) async {
        final out = <VibeUser>[];
        for (final d in snap.docs) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final blockedId = (data['blocked_id'] ?? '').toString();
          if (blockedId.isEmpty) continue;
          final profile = await getUserProfile(blockedId);
          if (profile != null) out.add(profile);
        }
        return out;
      });
    } catch (e) {
      debugPrint('blockedUsers failed: $e');
      return Stream.value(const []);
    }
  }

  /// Profiles of everyone [uid] follows (user-list screens).
  Stream<List<VibeUser>> followingUsers(String uid) {
    try {
      return _followingCol(uid).snapshots().asyncMap((snap) async {
        final out = <VibeUser>[];
        for (final d in snap.docs) {
          final profile = await getUserProfile(d.id);
          if (profile != null) out.add(profile);
        }
        return out;
      });
    } catch (e) {
      debugPrint('followingUsers failed: $e');
      return Stream.value(const []);
    }
  }

  /// Profiles of everyone who follows [uid]. The follower's uid
  /// is the parent user doc of each collection-group hit.
  Stream<List<VibeUser>> followersUsers(String uid) {
    try {
      final q = _dbSafe
          .collectionGroup('following')
          .where('targetUid', isEqualTo: uid);
      return q.snapshots().asyncMap((snap) async {
        final out = <VibeUser>[];
        final seen = <String>{};
        for (final d in snap.docs) {
          final followerUid = d.reference.parent.parent?.id ?? '';
          if (followerUid.isEmpty || !seen.add(followerUid)) continue;
          final profile = await getUserProfile(followerUid);
          if (profile != null) out.add(profile);
        }
        return out;
      });
    } catch (e) {
      debugPrint('followersUsers failed: $e');
      return Stream.value(const []);
    }
  }

  /// Deletes the signed-in user's Firestore data ahead of the
  /// Auth user deletion (Settings → Delete account): their
  /// videos (with their comment threads), watch history,
  /// following list and the profile doc itself. NOTE: the video
  /// FILES stay in Cloudinary — the unsigned upload preset
  /// cannot delete files, so only the app-side records go.
  Future<void> deleteMyAccountData() async {
    final uid = AuthService.instance.uid;
    if (uid == null) throw Exception('Please log in first.');
    final db = _dbSafe;

    Future<void> deleteAll(QuerySnapshot snap) async {
      var batch = db.batch();
      var n = 0;
      for (final d in snap.docs) {
        batch.delete(d.reference);
        if (++n % 400 == 0) {
          await batch.commit();
          batch = db.batch();
        }
      }
      if (n % 400 != 0 || n == 0) await batch.commit();
    }

    // My videos + their comments.
    final myVideos = await _videos.where('uid', isEqualTo: uid).get();
    for (final v in myVideos.docs) {
      final comments =
          await _videos.doc(v.id).collection('comments').get();
      await deleteAll(comments);
    }
    await deleteAll(myVideos);
    // Subcollections of my profile doc + the doc itself.
    await deleteAll(await _historyCol(uid).get());
    await deleteAll(await _followingCol(uid).get());
    await _users.doc(uid).delete();
  }
}
