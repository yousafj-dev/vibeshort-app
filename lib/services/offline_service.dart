import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeshort/models/vibe_video.dart';

/// One video saved for offline viewing (settings pack). The MP4
/// lives in the app documents directory under `offline_videos/`;
/// this index entry (kept in SharedPreferences) is what the
/// Offline screen lists.
class OfflineVideo {
  final String videoId;
  final String caption;
  final String username;
  final String url;
  final String path;
  final int savedAtMs;

  const OfflineVideo({
    required this.videoId,
    required this.caption,
    required this.username,
    required this.url,
    required this.path,
    required this.savedAtMs,
  });

  /// Cloudinary frame-grab thumbnail derived from the stored URL
  /// (same derivation as the feed model).
  String get thumbUrl {
    if (!url.contains('/upload/')) return '';
    var t = url.replaceFirst('/upload/', '/upload/so_0,w_300/');
    final dot = t.lastIndexOf('.');
    if (dot > 0) t = '${t.substring(0, dot)}.jpg';
    return t;
  }

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'caption': caption,
        'username': username,
        'url': url,
        'path': path,
        'savedAtMs': savedAtMs,
      };

  factory OfflineVideo.fromJson(Map<String, dynamic> j) => OfflineVideo(
        videoId: (j['videoId'] ?? '') as String,
        caption: (j['caption'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        path: (j['path'] ?? '') as String,
        savedAtMs: (j['savedAtMs'] ?? 0) as int,
      );
}

/// Offline downloads (settings pack): save a feed video's MP4
/// into the app documents folder so it plays with no connection,
/// list the saved set, and delete individual items. Separate
/// from [DownloadService], which saves to the device gallery.
class OfflineService {
  OfflineService._();

  static const String _indexKey = 'vibeshort_offline_index_v1';

  static Future<Directory> offlineDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/offline_videos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<OfflineVideo>> list() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_indexKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List;
      final items = decoded
          .map((e) => OfflineVideo.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
      // Drop index entries whose file is gone (e.g. OS cleanup).
      final alive = <OfflineVideo>[];
      for (final item in items) {
        if (await File(item.path).exists()) alive.add(item);
      }
      return alive;
    } catch (e) {
      debugPrint('OfflineService.list failed: $e');
      return const [];
    }
  }

  static Future<bool> isDownloaded(String videoId) async {
    final items = await list();
    return items.any((i) => i.videoId == videoId);
  }

  static Future<void> _saveIndex(List<OfflineVideo> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _indexKey, jsonEncode(items.map((i) => i.toJson()).toList()));
  }

  /// Downloads [video]'s original MP4 to the offline folder and
  /// indexes it. Returns a user-facing result message; throws
  /// nothing.
  static Future<String> download(
    VibeVideo video, {
    void Function(double progress)? onProgress,
  }) async {
    if (video.videoUrl.isEmpty) return 'This video cannot be downloaded.';
    try {
      if (await isDownloaded(video.id)) {
        return 'Already saved in Offline videos.';
      }
      final dir = await offlineDir();
      final file = File('${dir.path}/${video.id}.mp4');
      await Dio().download(
        video.videoUrl,
        file.path,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 30),
        ),
        onReceiveProgress: (received, total) {
          if (onProgress != null && total > 0) {
            onProgress(received / total);
          }
        },
      );
      if (!await file.exists() || await file.length() == 0) {
        return 'Download failed. Please try again.';
      }
      final items = await list();
      items.add(OfflineVideo(
        videoId: video.id,
        caption: video.caption,
        username: video.username,
        url: video.videoUrl,
        path: file.path,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      await _saveIndex(items);
      return 'Saved to Offline videos';
    } catch (e) {
      debugPrint('OfflineService.download failed: $e');
      return 'Download failed. Check your connection and try again.';
    }
  }

  /// Deletes one offline video: its file and its index entry.
  static Future<void> remove(String videoId) async {
    try {
      final items = await list();
      for (final item in items.where((i) => i.videoId == videoId)) {
        final f = File(item.path);
        if (await f.exists()) await f.delete();
      }
      await _saveIndex(
          items.where((i) => i.videoId != videoId).toList());
    } catch (e) {
      debugPrint('OfflineService.remove failed: $e');
    }
  }

  /// Total bytes held by offline downloads (shown in Settings →
  /// Free up space; NOT deleted by Clear cache).
  static Future<int> totalSizeBytes() async {
    try {
      final dir = await offlineDir();
      var total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
