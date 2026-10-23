import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One built-in sound for the Create flow (fix round, item 6).
///
/// ONLY royalty-free tracks are listed: every entry is a CC0 /
/// public-domain track (Kevin MacLeod, FreePD.com and friends —
/// the same library the project's other apps draw from). The audio
/// files are hosted on the project's Cloudinary next to the
/// uploaded videos — nothing is bundled into the APK, so the app
/// stays slim; a track is downloaded once, on first selection, and
/// cached on the device from then on.
class VibeSound {
  final String id;
  final String name;
  final String artist;
  final String url;
  final int durationSec;

  const VibeSound({
    required this.id,
    required this.name,
    required this.artist,
    required this.url,
    required this.durationSec,
  });

  String get durationLabel {
    final m = durationSec ~/ 60;
    final s = (durationSec % 60).toString().padLeft(2, '0');
    return m > 0 ? '$m:$s' : '0:$s';
  }
}

class BuiltInSounds {
  BuiltInSounds._();

  static const List<VibeSound> all = [
    VibeSound(
      id: 'sound_silly_intro',
      name: 'Silly Intro',
      artist: 'Alexander Nakarada',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772196/vibeshort_sounds/paxlipioawepffjtprab.m4a',
      durationSec: 25,
    ),
    VibeSound(
      id: 'sound_tuba_plum_fairy',
      name: 'Dance of the Tuba Plum Fairy',
      artist: 'Kevin MacLeod',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772197/vibeshort_sounds/wrimfam9ofbauaw0ygqy.m4a',
      durationSec: 29,
    ),
    VibeSound(
      id: 'sound_comic_mischief',
      name: 'Comic Game Loop – Mischief',
      artist: 'Kevin MacLeod',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772199/vibeshort_sounds/rcjcoeqt5mi4uzhwtyhq.m4a',
      durationSec: 43,
    ),
    VibeSound(
      id: 'sound_baltic_levity',
      name: 'Baltic Levity',
      artist: 'Kevin MacLeod',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772201/vibeshort_sounds/tgyc62wrw5vhjyiyfrpl.m4a',
      durationSec: 48,
    ),
    VibeSound(
      id: 'sound_barroom_ballet',
      name: 'Barroom Ballet',
      artist: 'Kevin MacLeod',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772203/vibeshort_sounds/cgrz3erjpfv2k4g3hibm.m4a',
      durationSec: 56,
    ),
    VibeSound(
      id: 'sound_backbeat',
      name: 'Backbeat',
      artist: 'Kevin MacLeod',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772207/vibeshort_sounds/wkh6o7zsngcvbaxplwrq.m4a',
      durationSec: 46,
    ),
    VibeSound(
      id: 'sound_bit_bit_loop',
      name: 'Bit Bit Loop',
      artist: 'Kevin MacLeod',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772208/vibeshort_sounds/psgvny08eovvt9tlrd1o.m4a',
      durationSec: 77,
    ),
    VibeSound(
      id: 'sound_happy_ukulele',
      name: 'Happy Whistling Ukulele',
      artist: 'FreePD.com',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772205/vibeshort_sounds/rudtkf17g60qbb13mrxi.m4a',
      durationSec: 123,
    ),
    VibeSound(
      id: 'sound_barnville',
      name: 'Barnville',
      artist: 'Rafael Krux',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772216/vibeshort_sounds/l5axbmeyrohnqtx06eq2.m4a',
      durationSec: 102,
    ),
    VibeSound(
      id: 'sound_and_just_like_that',
      name: 'And Just Like That',
      artist: 'Bryan Teoh',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772212/vibeshort_sounds/p5kvwozdudk2ttiiutvn.m4a',
      durationSec: 114,
    ),
    VibeSound(
      id: 'sound_advertime',
      name: 'Advertime',
      artist: 'FreePD.com',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772210/vibeshort_sounds/meryskanbgsaj7l24yfn.m4a',
      durationSec: 134,
    ),
    VibeSound(
      id: 'sound_bebop_for_joey',
      name: 'BeBop for Joey',
      artist: 'FreePD.com',
      url:
          'https://res.cloudinary.com/q76vpymr/video/upload/v1792772214/vibeshort_sounds/ixar3hni2hecvzykvfnr.m4a',
      durationSec: 139,
    ),
  ];

  static VibeSound? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Downloads a built-in sound to the app's documents folder on
/// first use and returns the cached file afterwards. The cache is
/// what gets played during camera recording and what FFmpeg mixes
/// into the posted video.
class SoundCache {
  SoundCache._();

  static Future<File> fileFor(VibeSound sound) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/sounds');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/${sound.id}.m4a');
    if (await file.exists() && await file.length() > 10000) return file;
    debugPrint('Downloading sound ${sound.id} …');
    await Dio().download(
      sound.url,
      file.path,
      options: Options(
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    if (!await file.exists() || await file.length() <= 10000) {
      throw Exception('Could not download the sound. Check your connection.');
    }
    return file;
  }
}
