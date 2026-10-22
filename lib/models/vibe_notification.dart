import 'package:cloud_firestore/cloud_firestore.dart';

/// One Inbox entry. Stored in `vibeshort_notifications`, written by
/// the actor's client whenever someone likes/comments on my video or
/// follows me — never for my own actions.
class VibeNotification {
  final String id;
  final String recipientId;
  final String actorId;
  final String actorName;
  final String actorPhoto;

  /// 'like' | 'comment' | 'follow'
  final String type;

  /// Set for like/comment notifications; null for follows.
  final String? videoId;

  /// Cloudinary frame-grab of the video, for like/comment rows.
  final String? videoThumb;

  /// Comment snippet, for comment notifications.
  final String? text;
  final bool read;
  final DateTime createdAt;

  const VibeNotification({
    required this.id,
    required this.recipientId,
    required this.actorId,
    required this.actorName,
    this.actorPhoto = '',
    required this.type,
    this.videoId,
    this.videoThumb,
    this.text,
    this.read = false,
    required this.createdAt,
  });

  /// The action phrase shown after the actor's name.
  String get actionText {
    switch (type) {
      case 'like':
        return 'liked your video';
      case 'comment':
        final t = (text ?? '').trim();
        return t.isEmpty ? 'commented on your video' : 'commented: $t';
      case 'follow':
        return 'started following you';
      default:
        return 'interacted with you';
    }
  }

  factory VibeNotification.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final raw = d['createdAt'];
    return VibeNotification(
      id: doc.id,
      recipientId: (d['recipientId'] ?? '') as String,
      actorId: (d['actorId'] ?? '') as String,
      actorName: (d['actorName'] ?? 'user') as String,
      actorPhoto: (d['actorPhoto'] ?? '') as String,
      type: (d['type'] ?? '') as String,
      videoId: d['videoId'] as String?,
      videoThumb: d['videoThumb'] as String?,
      text: d['text'] as String?,
      read: (d['read'] ?? false) as bool,
      createdAt: raw is Timestamp ? raw.toDate() : DateTime.now(),
    );
  }
}

/// Short relative label for a timestamp: "just now", "5m", "2h",
/// "3d", or a plain date for anything older than a week.
String timeAgoLabel(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${t.day}/${t.month}/${t.year}';
}
