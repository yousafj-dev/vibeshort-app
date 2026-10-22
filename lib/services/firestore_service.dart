import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:vibeshort/models/vibe_notification.dart';
import 'package:vibeshort/models/vibe_user.dart';
import 'package:vibeshort/models/vibe_video.dart';
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
}
