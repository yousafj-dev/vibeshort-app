import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local device preferences (settings pack). Kept in
/// SharedPreferences — they describe THIS device's playback, not
/// the account, so they apply instantly and work offline.
class PrefsService {
  PrefsService._();

  static const String _dataSaverKey = 'vibeshort_data_saver';

  /// Data Saver: when true the feed plays the lighter 540p
  /// Cloudinary variant instead of the 720p one. Read
  /// synchronously by the video card, so it is loaded once at
  /// startup (see main.dart) and mirrored here on every change.
  static bool dataSaver = false;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      dataSaver = p.getBool(_dataSaverKey) ?? false;
    } catch (e) {
      debugPrint('PrefsService.load failed: $e');
    }
  }

  static Future<void> setDataSaver(bool value) async {
    dataSaver = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_dataSaverKey, value);
    } catch (e) {
      debugPrint('PrefsService.setDataSaver failed: $e');
    }
  }
}
