import 'package:cloud_firestore/cloud_firestore.dart';

/// A VibeShort user profile. Stored in `vibeshort_users/{uid}` and
/// kept in sync with the FirebaseAuth profile (display name + photo).
///
/// Phase 4 adds the safety layer (blueprint Sections 5 + 9):
/// [role] separates normal users from admins (the Admin panel is
/// only reachable when role == 'admin'; the role is set directly
/// in Firestore, never from the app UI), and [status] carries the
/// moderation state — a 'suspended' account sees a clear
/// suspended screen and cannot post.
class VibeUser {
  final String uid;
  final String displayName;
  final String username;
  final String photoUrl;
  final String bio;
  final String email;

  /// 'user' | 'admin' — protected role (blueprint Section 5:
  /// "separate protected roles"). Defaults to 'user' for every
  /// pre-Phase-4 doc that has no field yet.
  final String role;

  /// 'active' | 'suspended'. Suspension always carries a recorded
  /// reason (blueprint Section 5: suspend/restore "with recorded
  /// reasons") in [suspensionReason].
  final String status;
  final String suspensionReason;

  /// Settings pack — privacy & preferences stored on the doc.
  /// All default to the pre-settings-pack behaviour for docs that
  /// have no fields yet (public account, notifications on,
  /// lists visible to everyone).
  final bool isPrivate;
  final bool notifLikes;
  final bool notifComments;
  final bool notifFollows;

  /// 'Everyone' | 'Only me' — who may see my liked videos / my
  /// following list on my profile.
  final String likedVisibility;
  final String followingVisibility;

  const VibeUser({
    required this.uid,
    this.displayName = '',
    this.username = '',
    this.photoUrl = '',
    this.bio = '',
    this.email = '',
    this.role = 'user',
    this.status = 'active',
    this.suspensionReason = '',
    this.isPrivate = false,
    this.notifLikes = true,
    this.notifComments = true,
    this.notifFollows = true,
    this.likedVisibility = 'Everyone',
    this.followingVisibility = 'Everyone',
  });

  bool get isAdmin => role == 'admin';
  bool get isSuspended => status == 'suspended';

  /// Name shown in the UI: display name, else @username, else 'user'.
  String get displayOrFallback {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (username.trim().isNotEmpty) return username.trim();
    return 'user';
  }

  factory VibeUser.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return VibeUser(
      uid: doc.id,
      displayName: (d['displayName'] ?? '') as String,
      username: (d['username'] ?? '') as String,
      photoUrl: (d['photoUrl'] ?? '') as String,
      bio: (d['bio'] ?? '') as String,
      email: (d['email'] ?? '') as String,
      role: (d['role'] ?? 'user') as String,
      status: (d['status'] ?? 'active') as String,
      suspensionReason: (d['suspensionReason'] ?? '') as String,
      isPrivate: (d['isPrivate'] ?? false) as bool,
      notifLikes: (d['notifLikes'] ?? true) as bool,
      notifComments: (d['notifComments'] ?? true) as bool,
      notifFollows: (d['notifFollows'] ?? true) as bool,
      likedVisibility: (d['likedVisibility'] ?? 'Everyone') as String,
      followingVisibility: (d['followingVisibility'] ?? 'Everyone') as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'username': username,
        'photoUrl': photoUrl,
        'bio': bio,
      };
}
