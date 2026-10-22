import 'package:cloud_firestore/cloud_firestore.dart';

/// A short video in the VibeShort feed. Stored in `vibeshort_videos`.
class VibeVideo {
  final String id;
  final String videoUrl;
  final String caption;
  final String uid;
  final String username;
  final String userPhoto;
  final int likes;
  final List<String> likedBy;
  final int commentCount;

  /// Name of the sound attached to this video (Phase 1: the default
  /// "Original sound" for every upload).
  final String soundName;
  final DateTime createdAt;

  const VibeVideo({
    required this.id,
    required this.videoUrl,
    required this.caption,
    required this.uid,
    required this.username,
    this.userPhoto = '',
    this.likes = 0,
    this.likedBy = const [],
    this.commentCount = 0,
    this.soundName = 'Original sound',
    required this.createdAt,
  });

  bool likedByMe(String? myUid) => myUid != null && likedBy.contains(myUid);

  /// Cloudinary frame-grab thumbnail: first frame (so_0) at 300px
  /// wide, as a .jpg. Empty when the URL is not a Cloudinary upload.
  String get thumbUrl {
    if (!videoUrl.contains('/upload/')) return '';
    var t = videoUrl.replaceFirst('/upload/', '/upload/so_0,w_300/');
    final dot = t.lastIndexOf('.');
    if (dot > 0) t = '${t.substring(0, dot)}.jpg';
    return t;
  }

  factory VibeVideo.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    DateTime ts;
    final raw = d['createdAt'];
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else {
      ts = DateTime.now();
    }
    return VibeVideo(
      id: doc.id,
      videoUrl: (d['videoUrl'] ?? '') as String,
      caption: (d['caption'] ?? '') as String,
      uid: (d['uid'] ?? '') as String,
      username: (d['username'] ?? 'user') as String,
      userPhoto: (d['userPhoto'] ?? '') as String,
      likes: (d['likes'] ?? 0) as int,
      likedBy:
          ((d['likedBy'] ?? []) as List).map((e) => e.toString()).toList(),
      commentCount: (d['commentCount'] ?? 0) as int,
      soundName: (d['soundName'] ?? 'Original sound') as String,
      createdAt: ts,
    );
  }

  Map<String, dynamic> toMap() => {
        'videoUrl': videoUrl,
        'caption': caption,
        'uid': uid,
        'username': username,
        'userPhoto': userPhoto,
        'likes': likes,
        'likedBy': likedBy,
        'commentCount': commentCount,
        'soundName': soundName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
