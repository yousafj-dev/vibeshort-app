import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeshort/core/theme/app_theme.dart';

/// Local device preferences (settings pack). Kept in
/// SharedPreferences — they describe THIS device's playback, not
/// the account, so they apply instantly and work offline.
class PrefsService {
  PrefsService._();

  static const String _dataSaverKey = 'vibeshort_data_saver';
  static const String _lightThemeKey = 'vibeshort_light_theme';
  static const String _lastFeedFirstKey = 'vibeshort_last_feed_first_id';

  /// Data Saver: when true the feed plays the lighter 540p
  /// Cloudinary variant instead of the 720p one. Read
  /// synchronously by the video card, so it is loaded once at
  /// startup (see main.dart) and mirrored here on every change.
  static bool dataSaver = false;

  /// Light theme (Settings → Appearance, build 16): false =
  /// dark (the default look). Loaded before the first frame so
  /// the app never flashes the wrong theme; [themeNotifier]
  /// fires on every change so the root widget can swap the
  /// MaterialApp theme and rebuild the tree.
  static bool lightTheme = false;
  static final ValueNotifier<bool> themeNotifier =
      ValueNotifier<bool>(false);

  /// Id of the video the For You feed opened on in the most
  /// recent session (test-apk-17 feed freshness). The home feed
  /// reads it synchronously when a session's shuffled order is
  /// established and never starts a new session on this video
  /// when the pool offers an alternative. Null on first run.
  static String? lastFeedFirstId;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      dataSaver = p.getBool(_dataSaverKey) ?? false;
      lightTheme = p.getBool(_lightThemeKey) ?? false;
      AppTheme.lightMode = lightTheme;
      themeNotifier.value = lightTheme;
      lastFeedFirstId = p.getString(_lastFeedFirstKey);
    } catch (e) {
      debugPrint('PrefsService.load failed: $e');
    }
  }

  static Future<void> setLastFeedFirstId(String id) async {
    lastFeedFirstId = id;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_lastFeedFirstKey, id);
    } catch (e) {
      debugPrint('PrefsService.setLastFeedFirstId failed: $e');
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

  static Future<void> setLightTheme(bool value) async {
    lightTheme = value;
    AppTheme.lightMode = value;
    themeNotifier.value = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_lightThemeKey, value);
    } catch (e) {
      debugPrint('PrefsService.setLightTheme failed: $e');
    }
  }
}
