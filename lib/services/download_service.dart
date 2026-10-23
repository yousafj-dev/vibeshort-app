import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Saves a feed video to the device gallery (fix round, items 2
/// and 3). Downloads the file to a temp path first, then hands it
/// to the system gallery via `gal`. When the gallery refuses
/// (permission denied on old Android), the file is kept in the
/// app's external folder and the returned message says where.
class DownloadService {
  DownloadService._();

  /// Downloads [videoUrl] and saves it to the gallery. Returns a
  /// user-facing result message ('Saved to your gallery' on
  /// success). Throws nothing — failures come back as messages.
  static Future<String> downloadVideo(
    String videoUrl, {
    void Function(double progress)? onProgress,
  }) async {
    if (videoUrl.isEmpty) return 'This video cannot be downloaded.';
    try {
      final tmp = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tmp.path}/vibeshort_$stamp.mp4');
      await Dio().download(
        videoUrl,
        file.path,
        options: Options(
          receiveTimeout: const Duration(minutes: 3),
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
      try {
        if (!await Gal.hasAccess(toAlbum: false)) {
          await Gal.requestAccess(toAlbum: false);
        }
        await Gal.putVideo(file.path);
        return 'Saved to your gallery';
      } on GalException catch (e) {
        debugPrint('Gal save failed: ${e.type}');
        // Fallback: keep the file where the user can still find it.
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final kept = await file.copy('${ext.path}/vibeshort_$stamp.mp4');
          return 'Saved to ${kept.path}';
        }
        return 'Could not save to the gallery.';
      }
    } catch (e) {
      debugPrint('downloadVideo failed: $e');
      return 'Download failed. Check your connection and try again.';
    }
  }
}
