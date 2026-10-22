import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_notification.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/home/video_viewer_screen.dart';
import 'package:vibeshort/screens/profile/public_profile_screen.dart';

/// Inbox tab: likes, comments and new followers on my content,
/// newest first. Becoming the visible tab marks everything as
/// read; entries that were unread when the screen opened stay
/// highlighted for the rest of this visit.
class InboxScreen extends StatefulWidget {
  /// True while Inbox is the shell's selected tab. (The shell keeps
  /// every tab mounted in an IndexedStack, so visibility — not
  /// initState — is what "opening the Inbox" means.)
  final bool active;

  const InboxScreen({super.key, this.active = false});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  /// Ids that arrived unread during this visit — kept highlighted
  /// even after the mark-as-read batch lands.
  final Set<String> _sessionUnread = {};

  @override
  void didUpdateWidget(InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      FirestoreService.instance.markAllNotificationsRead();
    }
  }

  Future<void> _openNotification(
      BuildContext context, VibeNotification n) async {
    if (n.type == 'follow') {
      if (n.actorId.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => PublicProfileScreen(uid: n.actorId)),
      );
      return;
    }
    final videoId = n.videoId;
    if (videoId == null || videoId.isEmpty) return;
    final video = await FirestoreService.instance.getVideo(videoId);
    if (!context.mounted) return;
    if (video == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This video is no longer available.')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoViewerScreen(videos: [video])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Inbox')),
      body: StreamBuilder<List<VibeNotification>>(
        stream: FirestoreService.instance.notifications(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final items = snap.data ?? const <VibeNotification>[];
          for (final n in items) {
            if (!n.read) _sessionUnread.add(n.id);
          }
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none,
                        size: 56, color: AppTheme.muted),
                    SizedBox(height: 14),
                    Text(
                      'No notifications yet',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Likes, comments and new followers will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => _row(context, items[i]),
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, VibeNotification n) {
    final unread = !n.read || _sessionUnread.contains(n.id);
    final thumb = n.videoThumb;
    return InkWell(
      onTap: () => _openNotification(context, n),
      child: Container(
        color: unread ? AppTheme.card : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.accent2,
              backgroundImage:
                  n.actorPhoto.isNotEmpty ? NetworkImage(n.actorPhoto) : null,
              child: n.actorPhoto.isEmpty
                  ? Text(
                      n.actorName.isNotEmpty
                          ? n.actorName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14.5),
                      children: [
                        TextSpan(
                          text: n.actorName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(text: ' ${n.actionText}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    timeAgoLabel(n.createdAt),
                    style:
                        const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (thumb != null && thumb.isNotEmpty) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  thumb,
                  width: 42,
                  height: 54,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 42,
                    height: 54,
                    color: AppTheme.card,
                    child: const Icon(Icons.play_circle_outline,
                        color: Colors.white38, size: 20),
                  ),
                ),
              ),
            ],
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 6),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF3B5C),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
