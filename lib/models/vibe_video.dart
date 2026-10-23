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

  /// Hashtags parsed from the caption (lowercase, no leading '#').
  /// Stored on the doc at upload; older docs may not have the field,
  /// so reads fall back to parsing the caption (see
  /// [effectiveHashtags]).
  final List<String> hashtags;

  /// Name of the sound attached to this video (Phase 1: the default
  /// "Original sound" for every upload).
  final String soundName;

  /// Id of the built-in sound attached to this video (fix round),
  /// e.g. 'sound_backbeat'. Empty for original/device sounds.
  final String soundId;

  /// When this video was made with "Use this sound" on someone
  /// else's ORIGINAL sound (sound page round): the id of the
  /// video whose own audio track was reused, and that video's
  /// owner uid. Empty for library sounds, device-file music and
  /// true originals. The anchor video of an original sound is the
  /// video itself when this is empty and [soundId] is also empty.
  final String soundSourceVideoId;
  final String soundOwnerId;

  /// Pinned to the top of the creator's profile grid (fix round).
  /// Older docs have no field and read as unpinned.
  final bool pinned;
  final DateTime? pinnedAt;

  /// Moderation state (Phase 4, blueprint Sections 5 + 8):
  /// 'active' | 'removed'. Removed videos are filtered out of
  /// every feed. Pre-Phase-4 docs have no field and read as
  /// 'active'.
  final String moderationStatus;

  /// Play count, shown on the Admin dashboard (blueprint Section
  /// 5). New uploads start at 0.
  final int views;
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
    this.hashtags = const [],
    this.soundName = 'Original sound',
    this.soundId = '',
    this.soundSourceVideoId = '',
    this.soundOwnerId = '',
    this.pinned = false,
    this.pinnedAt,
    this.moderationStatus = 'active',
    this.views = 0,
    required this.createdAt,
  });

  bool get isRemoved => moderationStatus == 'removed';

  /// True when a built-in library sound is attached.
  bool get hasLibrarySound => soundId.isNotEmpty;

  /// True when this video reuses another video's original audio
  /// via "Use this sound" (its [soundName] was stored at post
  /// time as 'original sound — @<owner>').
  bool get usesOriginalSound => soundId.isEmpty && soundSourceVideoId.isNotEmpty;

  /// The video that anchors this video's ORIGINAL sound: the
  /// source video when one was reused, otherwise this video
  /// itself. Only meaningful when [soundId] is empty.
  String get originalSoundAnchorId =>
      soundSourceVideoId.isNotEmpty ? soundSourceVideoId : id;

  /// The sound line shown under the caption in the feed
  /// (sound page round, TikTok style):
  ///  - library sound → the track's name;
  ///  - reused original → the stored 'original sound — @owner';
  ///  - true original / untouched sound name → derived here as
  ///    'original sound — @<creator>';
  ///  - device-file music keeps its track name, as before.
  String get feedSoundLabel {
    if (soundId.isNotEmpty) return soundName;
    if (soundSourceVideoId.isNotEmpty) return soundName;
    if (soundName.isEmpty || soundName == 'Original sound') {
      return 'original sound — @$username';
    }
    return soundName;
  }

  /// Extracts `#tags` from a caption: lowercase, without the '#',
  /// de-duplicated, in first-appearance order.
  static List<String> parseHashtags(String caption) {
    final seen = <String>{};
    final out = <String>[];
    for (final m in RegExp(r'#([A-Za-z0-9_]+)').allMatches(caption)) {
      final tag = m.group(1)!.toLowerCase();
      if (seen.add(tag)) out.add(tag);
    }
    return out;
  }

  /// The hashtags to actually use for this video: the stored field
  /// when present, otherwise parsed live from the caption (docs
  /// uploaded before Phase 2 have no stored field).
  List<String> get effectiveHashtags =>
      hashtags.isNotEmpty ? hashtags : parseHashtags(caption);

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
      hashtags: ((d['hashtags'] ?? []) as List)
          .map((e) => e.toString().toLowerCase())
          .toList(),
      soundName: (d['soundName'] ?? 'Original sound') as String,
      soundId: (d['soundId'] ?? '') as String,
      soundSourceVideoId: (d['soundSourceVideoId'] ?? '') as String,
      soundOwnerId: (d['soundOwnerId'] ?? '') as String,
      pinned: (d['pinned'] ?? false) as bool,
      pinnedAt:
          d['pinnedAt'] is Timestamp ? (d['pinnedAt'] as Timestamp).toDate() : null,
      moderationStatus: (d['moderationStatus'] ?? 'active') as String,
      views: (d['views'] ?? 0) as int,
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
        'hashtags': parseHashtags(caption),
        'soundName': soundName,
        'soundId': soundId,
        'soundSourceVideoId': soundSourceVideoId,
        'soundOwnerId': soundOwnerId,
        'moderationStatus': 'active',
        'views': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
