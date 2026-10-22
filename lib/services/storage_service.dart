import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:vibeshort/services/auth_service.dart';

/// Uploads picked videos to Cloudinary (unsigned upload) and returns
/// the playable `secure_url`, which Firestore stores as the video URL.
///
/// Login and metadata still live in Firebase — only the media bytes
/// go to Cloudinary.
class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  static const String _cloudName = 'q76vpymr';
  static const String _uploadPreset = 'lhmgywrj';
  static const String _folder = 'vibeshort_videos';
  static const String _profileFolder = 'vibeshort_profiles';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 10),
      receiveTimeout: const Duration(minutes: 10),
    ),
  );

  /// Uploads [file] and returns its public Cloudinary URL.
  /// Calls [onProgress] with 0.0–1.0 as bytes transfer.
  /// Throws an [Exception] with a friendly English message on failure.
  Future<String> uploadVideo(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    _ensureCanUpload();
    return _upload(
      file,
      resourceType: 'video',
      folder: _folder,
      failMsg: 'Upload failed. Please try again.',
      onProgress: onProgress,
    );
  }

  /// Uploads a profile photo and returns its Cloudinary `secure_url`.
  Future<String> uploadProfileImage(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    _ensureCanUpload();
    return _upload(
      file,
      resourceType: 'image',
      folder: _profileFolder,
      failMsg: 'Could not upload the photo. Please try again.',
      onProgress: onProgress,
    );
  }

  void _ensureCanUpload() {
    if (!AuthService.firebaseReady) throw Exception(AuthService.offlineMsg);
    if (AuthService.instance.uid == null) {
      throw Exception('Please log in first to upload.');
    }
  }

  Future<String> _upload(
    File file, {
    required String resourceType,
    required String folder,
    required String failMsg,
    void Function(double progress)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
      'upload_preset': _uploadPreset,
      'folder': folder,
    });

    try {
      final resp = await _dio.post(
        'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
      final url = resp.data?['secure_url'] as String?;
      if (resp.statusCode == 200 && url != null && url.isNotEmpty) {
        return url;
      }
      debugPrint('upload unexpected response: ${resp.statusCode}');
      throw Exception(failMsg);
    } on DioException catch (e) {
      debugPrint('upload failed: ${e.type}');
      if (e.response != null) {
        // Server replied with an error (e.g. bad preset) — not a network issue.
        throw Exception(failMsg);
      }
      throw Exception(
          'Internet problem — the upload could not finish. Please try again.');
    }
  }
}
