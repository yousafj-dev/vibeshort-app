import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/offline_service.dart';

/// Offline videos (settings pack): everything saved from the
/// feed's "Watch offline" action. Plays from the local file —
/// no connection needed — and each item can be deleted.
class OfflineVideosScreen extends StatefulWidget {
  const OfflineVideosScreen({super.key});

  @override
  State<OfflineVideosScreen> createState() => _OfflineVideosScreenState();
}

class _OfflineVideosScreenState extends State<OfflineVideosScreen> {
  late Future<List<OfflineVideo>> _items = OfflineService.list();

  void _reload() {
    setState(() => _items = OfflineService.list());
  }

  Future<void> _delete(OfflineVideo item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Remove offline video?'),
        content: const Text(
            'The saved copy on this device will be deleted. The video stays in the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: Color(0xFFFF5C7A))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await OfflineService.remove(item.videoId);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Offline videos')),
      body: FutureBuilder<List<OfflineVideo>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent));
          }
          final items = snap.data ?? const <OfflineVideo>[];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.offline_pin_outlined,
                        size: 56, color: AppTheme.muted),
                    SizedBox(height: 14),
                    Text(
                      'No offline videos yet',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Long-press a video in the feed and choose "Watch offline" to save it here.',
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
            itemBuilder: (context, i) => _row(items[i]),
          );
        },
      ),
    );
  }

  Widget _row(OfflineVideo item) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: item.thumbUrl.isNotEmpty
            ? Image.network(
                item.thumbUrl,
                width: 52,
                height: 68,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _thumbFallback(),
              )
            : _thumbFallback(),
      ),
      title: Text(
        item.caption.isNotEmpty ? item.caption : 'Video',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text('@${item.username}',
          style: const TextStyle(color: AppTheme.muted)),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Color(0xFFFF5C7A)),
        onPressed: () => _delete(item),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OfflinePlayerScreen(item: item)),
      ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      width: 52,
      height: 68,
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: const Icon(Icons.play_circle_outline,
          color: Colors.white70, size: 24),
    );
  }
}

/// Minimal full-screen player for one offline file: tap to
/// play/pause. No network is involved — the controller reads the
/// file from the app documents folder.
class OfflinePlayerScreen extends StatefulWidget {
  final OfflineVideo item;

  const OfflinePlayerScreen({super.key, required this.item});

  @override
  State<OfflinePlayerScreen> createState() => _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends State<OfflinePlayerScreen> {
  VideoPlayerController? _ctrl;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.file(File(widget.item.path));
    _ctrl = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {});
      ctrl.play();
    } catch (e) {
      debugPrint('OfflinePlayer init failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.item.caption.isNotEmpty ? widget.item.caption : 'Offline video',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _failed
          ? const Center(
              child: Text('Could not play this file.',
                  style: TextStyle(color: AppTheme.muted)),
            )
          : ctrl == null || !ctrl.value.isInitialized
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent))
              : GestureDetector(
                  onTap: () {
                    setState(() {
                      if (ctrl.value.isPlaying) {
                        ctrl.pause();
                      } else {
                        ctrl.play();
                      }
                    });
                  },
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: ctrl.value.aspectRatio,
                      child: VideoPlayer(ctrl),
                    ),
                  ),
                ),
    );
  }
}
