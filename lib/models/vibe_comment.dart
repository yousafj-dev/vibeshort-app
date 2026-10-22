import 'package:cloud_firestore/cloud_firestore.dart';

/// A comment on a video. Stored in `vibeshort_videos/{id}/comments`.
class VibeComment {
  final String id;
  final String uid;
  final String username;
  final String text;
  final DateTime createdAt;

  const VibeComment({
    required this.id,
    required this.uid,
    required this.username,
    required this.text,
    required this.createdAt,
  });

  factory VibeComment.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    DateTime ts;
    final raw = d['createdAt'];
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else {
      ts = DateTime.now();
    }
    return VibeComment(
      id: doc.id,
      uid: (d['uid'] ?? '') as String,
      username: (d['username'] ?? 'user') as String,
      text: (d['text'] ?? '') as String,
      createdAt: ts,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'username': username,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
