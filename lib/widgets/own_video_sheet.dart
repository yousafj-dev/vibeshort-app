import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_video.dart';
import 'package:vibeshort/services/download_service.dart';
import 'package:vibeshort/services/firestore_service.dart';

/// Actions for MY OWN videos (fix round, item 2): download, pin,
/// edit captions, share, delete. Shared by the profile grid
/// (long-press), the video page's More menu and the feed
/// long-press menu, so the behaviour is identical everywhere.

void _snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));
}

String _err(Object e) => e.toString().replaceFirst('Exception: ', '');

Future<void> downloadVideoAction(BuildContext context, VibeVideo video) async {
  _snack(context, 'Downloading video…');
  final msg = await DownloadService.downloadVideo(video.videoUrl);
  _snack(context, msg);
}

Future<void> pinVideoAction(BuildContext context, VibeVideo video) async {
  try {
    await FirestoreService.instance.setVideoPinned(video.id, !video.pinned);
    _snack(context,
        video.pinned ? 'Video unpinned' : 'Video pinned to your profile');
  } catch (e) {
    _snack(context, _err(e));
  }
}

Future<void> editCaptionAction(BuildContext context, VibeVideo video) async {
  final controller = TextEditingController(text: video.caption);
  final saved = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: const Text('Edit captions'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        maxLength: 300,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Write a caption… use #hashtags',
          hintStyle: TextStyle(color: AppTheme.muted),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (saved == null) return;
  try {
    await FirestoreService.instance.updateVideoCaption(video.id, saved);
    _snack(context, 'Caption updated');
  } catch (e) {
    _snack(context, _err(e));
  }
}

Future<void> deleteVideoAction(BuildContext context, VibeVideo video) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: const Text('Delete this video?'),
      content: const Text(
          'It will be removed from feeds and your profile. This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete',
              style: TextStyle(color: Color(0xFFFF5C7A))),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await FirestoreService.instance.deleteOwnVideo(video.id);
    _snack(context, 'Video deleted');
  } catch (e) {
    _snack(context, _err(e));
  }
}

Widget _row(
  IconData icon,
  String label, {
  Color color = Colors.white,
  String? subtitle,
}) {
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(label, style: TextStyle(color: color)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle, style: const TextStyle(color: AppTheme.muted)),
  );
}

/// The own-video action sheet: Download / Pin / Edit captions /
/// Share / Delete.
Future<void> showOwnVideoActions(BuildContext context, VibeVideo video) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                Navigator.of(sheetCtx).pop();
                downloadVideoAction(context, video);
              },
              child: _row(Icons.download, 'Download video',
                  subtitle: 'Save to your gallery'),
            ),
            InkWell(
              onTap: () {
                Navigator.of(sheetCtx).pop();
                pinVideoAction(context, video);
              },
              child: _row(
                video.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                video.pinned ? 'Unpin video' : 'Pin video',
                subtitle: video.pinned
                    ? 'Pinned videos show first on your profile'
                    : 'Show first on your profile',
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.of(sheetCtx).pop();
                editCaptionAction(context, video);
              },
              child: _row(Icons.edit_outlined, 'Edit captions'),
            ),
            InkWell(
              onTap: () {
                Navigator.of(sheetCtx).pop();
                Share.share(video.videoUrl);
              },
              child: _row(Icons.share_outlined, 'Share'),
            ),
            const Divider(color: Colors.white10, height: 1),
            InkWell(
              onTap: () {
                Navigator.of(sheetCtx).pop();
                deleteVideoAction(context, video);
              },
              child: _row(Icons.delete_outline, 'Delete video',
                  color: const Color(0xFFFF5C7A)),
            ),
          ],
        ),
      );
    },
  );
}
