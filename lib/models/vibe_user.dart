import 'package:cloud_firestore/cloud_firestore.dart';

/// A VibeShort user profile. Stored in `vibeshort_users/{uid}` and
/// kept in sync with the FirebaseAuth profile (display name + photo).
class VibeUser {
  final String uid;
  final String displayName;
  final String username;
  final String photoUrl;
  final String bio;

  const VibeUser({
    required this.uid,
    this.displayName = '',
    this.username = '',
    this.photoUrl = '',
    this.bio = '',
  });

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
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'username': username,
        'photoUrl': photoUrl,
        'bio': bio,
      };
}
