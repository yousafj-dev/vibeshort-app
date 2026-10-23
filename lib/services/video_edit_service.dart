import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

/// A named video filter. [ffmpegFilter] is the `-vf` fragment baked into
/// the posted video; [previewMatrix] is the ColorFilter approximation
/// shown live on the record and edit screens. `null` ffmpegFilter =
/// no processing.
class VideoFilter {
  final String name;
  final String? ffmpegFilter;
  final List<double>? previewMatrix;

  const VideoFilter(this.name, this.ffmpegFilter, this.previewMatrix);
}

/// A named whole-frame effect (TikTok-panel style). [ffmpegGraph] is
/// the full `-vf` filtergraph baked into the posted video — effects
/// include their own colour grade, so a selected effect is used
/// INSTEAD of the colour filter chain. These are frame-level effects
/// only: there is no face tracking / AR, and the preview can only
/// approximate the grade effects ([previewMatrix]); structural
/// effects (mirror, glitch…) honestly show no preview change.
class VideoEffect {
  final String name;
  final String emoji;
  final String? ffmpegGraph;
  final List<double>? previewMatrix;

  const VideoEffect(this.name, this.emoji, this.ffmpegGraph,
      this.previewMatrix);
}

class VideoEffects {
  VideoEffects._();

  static const VideoEffect none = VideoEffect('None', '🚫', null, null);

  // Preview approximations exist ONLY for grade-style effects.
  static const List<double> _softGlowPreview = [
    1.10, 0, 0, 0, 14,
    0, 1.02, 0, 0, 8,
    0, 0, 0.92, 0, 2,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _posterPopPreview = [
    1.72, -0.47, -0.05, 0, -25,
    -0.14, 1.39, -0.05, 0, -25,
    -0.14, -0.47, 1.81, 0, -25,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _oldFilmPreview = [
    0.72, 0.25, 0.05, 0, 14,
    0.16, 0.66, 0.08, 0, 10,
    0.14, 0.22, 0.52, 0, 2,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _cinematicPreview = [
    1.06, 0, 0.02, 0, -2,
    0, 1.04, 0, 0, 0,
    0.02, 0, 1.10, 0, 4,
    0, 0, 0, 1, 0,
  ];

  // Pack 2 preview approximations (grade-style effects only; the blur
  // in Fog / Underwater cannot be expressed as a matrix and is baked
  // for real by FFmpeg — the matrix only matches the grade).
  static const List<double> _fogPreview = [
    0.74, 0.08, 0.02, 0, 40,
    0.06, 0.76, 0.03, 0, 38,
    0.05, 0.09, 0.80, 0, 36,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _xrayPreview = [
    -0.55, 0, 0, 0, 200,
    0, -0.95, 0, 0, 245,
    0, 0, -0.55, 0, 195,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _underwaterPreview = [
    0.80, 0.03, 0.02, 0, -8,
    0.02, 0.98, 0.05, 0, 2,
    0.03, 0.07, 1.13, 0, 10,
    0, 0, 0, 1, 0,
  ];

  // Every ffmpegGraph below was syntax-tested (in the sister app this
  // system was ported from) against system ffmpeg on even (540x960)
  // and odd (541x961) clips, alone, with drawtext appended, and in
  // the music-replace command shape.
  static List<VideoEffect> get all => [
        none,
        const VideoEffect(
            'Soft Glow',
            '🌸',
            'split[a][b];[b]gblur=sigma=8[bb];'
                '[a][bb]blend=all_mode=softlight:all_opacity=0.45,'
                'eq=brightness=0.05:saturation=1.15,'
                'colorbalance=rs=0.1:gs=-0.02:bs=-0.06:rm=0.06:bm=-0.04',
            _softGlowPreview),
        const VideoEffect(
            'Glitch',
            '👾',
            'rgbashift=rh=-10:bh=10:gh=5,noise=alls=28:allf=t,'
                'eq=saturation=1.55:contrast=1.1',
            null),
        const VideoEffect(
            'Cartoon',
            '🎨',
            'split[a][b];'
                '[a]bilateral=sigmaS=4:sigmaR=0.12,'
                'eq=saturation=1.35:contrast=1.05[base];'
                '[b]format=gray,edgedetect=low=0.08:high=0.25,negate,'
                'format=yuv420p[edges];'
                '[base][edges]blend=all_mode=multiply',
            null),
        const VideoEffect(
            'VHS',
            '📼',
            'noise=alls=18:allf=t,rgbashift=rh=-3:bh=3,'
                'eq=saturation=0.72:contrast=0.96:brightness=0.02,'
                'vignette=PI/5',
            null),
        const VideoEffect(
            'Mirror',
            '🪞',
            'scale=trunc(iw/2)*2:trunc(ih/2)*2,crop=iw/2:ih,'
                'split[l][r];[r]hflip[rf];[l][rf]hstack,setsar=1',
            null),
        const VideoEffect(
            'Quad',
            '🪟',
            'scale=trunc(iw/2)*2:trunc(ih/2)*2,crop=iw/2:ih/2,'
                'split=4[a][b][c][d];[b]hflip[bf];[c]vflip[cf];'
                '[d]hflip,vflip[df];[a][bf]hstack[top];'
                '[cf][df]hstack[bot];[top][bot]vstack,setsar=1',
            null),
        const VideoEffect(
            'Dream Blur',
            '☁️',
            'split[a][b];[b]gblur=sigma=16[bb];'
                '[a][bb]blend=all_mode=screen:all_opacity=0.5,'
                'eq=brightness=0.05:saturation=1.1',
            null),
        const VideoEffect(
            'Poster Pop',
            '💥',
            'eq=saturation=1.65:contrast=1.25:brightness=0.01,'
                'vibrance=intensity=0.55',
            _posterPopPreview),
        const VideoEffect(
            'Old Film',
            '🎞️',
            'eq=saturation=0.42:contrast=0.95:brightness=0.03,'
                'colorbalance=rs=0.09:gs=0.03:bs=-0.11,'
                'noise=alls=14:allf=t,vignette=PI/4.5',
            _oldFilmPreview),
        const VideoEffect(
            'Cinematic',
            '🎬',
            'colorbalance=rs=-0.1:gs=0.05:bs=0.13:rh=0.13:gh=0.04:'
                'bh=-0.1,eq=saturation=1.12:contrast=1.08,'
                'drawbox=x=0:y=0:w=iw:h=ih/13:color=black:t=fill,'
                'drawbox=x=0:y=ih-ih/13:w=iw:h=ih/13:color=black:t=fill',
            _cinematicPreview),
        const VideoEffect(
            'Neon Edges',
            '⚡',
            'format=gray,edgedetect=low=0.08:high=0.3,format=rgb24,'
                'lutrgb=r=val*0.3:g=val:b=val,'
                'eq=contrast=1.25:brightness=0.06',
            null),
        // ---- Effects Pack 2 -------------------------------------------
        // Camcorder carries two placeholders in its graph —
        // __VIBE_FONT__ and __VIBE_DATE__ — which VideoEditService
        // resolves at processing time (bundled font path + today's
        // date), so its text is real drawtext baked into the video.
        const VideoEffect(
            'Fisheye',
            '🐟',
            'lenscorrection=cx=0.5:cy=0.5:k1=0.35:k2=0.08:i=bilinear',
            null),
        const VideoEffect(
            'Spin',
            '🔄',
            'scale=iw*1.8:ih*1.8,'
                "rotate=a='t*1.2':ow=iw:oh=ih:c=black,"
                'crop=iw/1.8:ih/1.8,'
                'scale=trunc(iw/2)*2:trunc(ih/2)*2',
            null),
        const VideoEffect(
            'Shake',
            '📳',
            'scale=iw*1.12:ih*1.12,'
                "rotate=a='0.03*sin(t*28)':ow=iw:oh=ih:c=black,"
                'crop=iw/1.12:ih/1.12,'
                'scale=trunc(iw/2)*2:trunc(ih/2)*2',
            null),
        const VideoEffect(
            'Psychedelic',
            '🌀',
            "negate,hue=h='t*40':s=1.35",
            null),
        const VideoEffect(
            'Rainbow',
            '🌈',
            "hue=h='t*60':s=1.3",
            null),
        const VideoEffect(
            'Thermal',
            '🔥',
            'format=gray,format=rgb24,pseudocolor=preset=inferno',
            null),
        const VideoEffect(
            'Mosaic',
            '🧩',
            'scale=trunc(iw/24):trunc(ih/24):flags=neighbor,'
                'scale=iw*24:ih*24:flags=neighbor,'
                'scale=trunc(iw/2)*2:trunc(ih/2)*2',
            null),
        const VideoEffect(
            'Fog',
            '🌫️',
            'gblur=sigma=14,'
                'eq=brightness=0.09:contrast=0.9:saturation=0.72',
            _fogPreview),
        const VideoEffect(
            'Triple',
            '3️⃣',
            'split=3[t1][t2][t3];'
                '[t1]crop=iw:trunc(ih/3/2)*2:0:ih/3[b1];'
                '[t2]crop=iw:trunc(ih/3/2)*2:0:ih/3[b2];'
                '[t3]crop=iw:trunc(ih/3/2)*2:0:ih/3[b3];'
                '[b1][b2][b3]vstack=inputs=3,'
                'scale=trunc(iw/2)*2:trunc(ih/2)*2',
            null),
        const VideoEffect(
            'Frame',
            '🖼️',
            'drawbox=x=0:y=0:w=iw:h=ih:color=black@0.35:t=3,'
                "pad=w=iw*1.12:h=ih*1.12:x='(ow-iw)/2':y='(oh-ih)/2'"
                ':color=white,'
                'scale=trunc(iw/2)*2:trunc(ih/2)*2',
            null),
        const VideoEffect(
            'Camcorder',
            '📹',
            'eq=saturation=0.92:contrast=1.03,noise=alls=10:allf=t,'
                "drawtext=fontfile=__VIBE_FONT__:text='● REC'"
                ':fontcolor=red:fontsize=h/20:x=w*0.05:y=h*0.04,'
                "drawtext=fontfile=__VIBE_FONT__:text='__VIBE_DATE__'"
                ':fontcolor=white:fontsize=h/26'
                ':x=w-text_w-w*0.05:y=h-text_h-h*0.04',
            null),
        const VideoEffect(
            'Echo Trail',
            '👻',
            "tmix=frames=5:weights='1 1 1 1 1'",
            null),
        const VideoEffect(
            'X-Ray',
            '☠️',
            'negate,colorbalance=gs=0.3:gm=0.18:bm=-0.1,'
                'eq=contrast=1.3:saturation=0.55',
            _xrayPreview),
        const VideoEffect(
            'Underwater',
            '🌊',
            'colortemperature=temperature=4600:mix=0.75,'
                'colorbalance=gs=0.14:bs=0.16:gm=0.08:bm=0.1,'
                'eq=saturation=0.92,gblur=sigma=1.1',
            _underwaterPreview),
      ];
}

/// Where the overlay text sits on the frame.
enum OverlayPosition { top, center, bottom }

/// What happens to the audio on post.
enum MusicMode { original, mute, replace }

/// The edits chosen on the edit screen.
class VideoEditOptions {
  final VideoFilter filter;

  /// Whole-frame effect. When one is selected its graph replaces the
  /// colour [filter] chain (effects carry their own grade).
  final VideoEffect effect;
  final MusicMode musicMode;

  /// Audio file path when [musicMode] is [MusicMode.replace].
  final String? musicPath;
  final String overlayText;
  final OverlayPosition overlayPosition;

  /// Trim window: the kept segment starts at [trimStart]; [trimEnd]
  /// is null when the segment runs to the end of the clip.
  final Duration trimStart;
  final Duration? trimEnd;

  const VideoEditOptions({
    required this.filter,
    this.effect = VideoEffects.none,
    this.musicMode = MusicMode.original,
    this.musicPath,
    this.overlayText = '',
    this.overlayPosition = OverlayPosition.bottom,
    this.trimStart = Duration.zero,
    this.trimEnd,
  });

  bool get hasEdits =>
      effect.ffmpegGraph != null ||
      filter.ffmpegFilter != null ||
      musicMode != MusicMode.original ||
      overlayText.trim().isNotEmpty ||
      trimStart > Duration.zero ||
      trimEnd != null;
}

class VideoFilters {
  VideoFilters._();

  // Saturation matrix for a given saturation level (0 = greyscale).
  static List<double> _sat(double s) => [
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
        0, 0, 0, 1, 0,
      ];

  // Contrast c around mid-grey combined with a brightness offset.
  static const List<double> _noirPreview = [
    0.276, 0.928, 0.094, 0, -34,
    0.276, 0.928, 0.094, 0, -34,
    0.276, 0.928, 0.094, 0, -34,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _fadePreview = [
    0.62, 0.28, 0.03, 0, 34,
    0.16, 0.68, 0.05, 0, 34,
    0.16, 0.27, 0.76, 0, 34,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _warmPreview = [
    1.16, 0.02, 0, 0, 4,
    0, 1.03, 0, 0, 0,
    0, 0, 0.84, 0, -4,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _coolPreview = [
    0.86, 0, 0, 0, -4,
    0, 1.0, 0.02, 0, 2,
    0, 0.03, 1.16, 0, 8,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _vintagePreview = [
    0.86, 0.28, 0.06, 0, 10,
    0.12, 0.72, 0.10, 0, 4,
    0.22, 0.24, 0.52, 0, -8,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _sunsetPreview = [
    1.2, 0.05, 0, 0, 10,
    0, 1.02, 0, 0, 2,
    0, 0, 0.78, 0, -8,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _goldenPreview = [
    1.12, 0.04, 0, 0, 6,
    0.02, 1.06, 0, 0, 4,
    0, 0, 0.82, 0, -6,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _candyPreview = [
    1.18, 0, 0.04, 0, 12,
    0, 0.98, 0.02, 0, 2,
    0.04, 0, 1.1, 0, 8,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _tealPreview = [
    1.04, 0, 0.02, 0, 0,
    0, 1.05, 0.02, 0, 2,
    0, 0.04, 1.12, 0, 4,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _dramaPreview = [
    1.12, 0.04, 0.01, 0, -22,
    0.03, 1.11, 0.03, 0, -22,
    0.03, 0.04, 1.12, 0, -22,
    0, 0, 0, 1, 0,
  ];

  // Blur-based filters (Beauty, Dreamy) approximate with brightness /
  // contrast / saturation only — the baked FFmpeg result is the real one.
  static const List<double> _beautyPreview = [
    0.97, 0, 0, 0, 20,
    0, 0.96, 0, 0, 18,
    0, 0, 0.97, 0, 16,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _retroPreview = [
    0.78, 0.2, 0.04, 0, 22,
    0.12, 0.82, 0.08, 0, 24,
    0.14, 0.24, 0.62, 0, 14,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _cyberPreview = [
    1.1, 0, 0.12, 0, 4,
    0, 0.92, 0.06, 0, 0,
    0.08, 0, 1.24, 0, 10,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _midnightPreview = [
    0.82, 0, 0.04, 0, -16,
    0, 0.9, 0.04, 0, -10,
    0.02, 0.05, 1.18, 0, 2,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _sepiaPreview = [
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _dreamyPreview = [
    0.96, 0, 0, 0, 30,
    0, 0.95, 0, 0, 27,
    0, 0, 0.97, 0, 24,
    0, 0, 0, 1, 0,
  ];

  // Sharpen can't be expressed as a colour matrix; contrast stands in.
  static const List<double> _crispPreview = [
    1.1, 0, 0, 0, -12,
    0, 1.1, 0, 0, -12,
    0, 0, 1.1, 0, -12,
    0, 0, 0, 1, 0,
  ];

  static List<VideoFilter> get all => [
        const VideoFilter('Normal', null, null),
        VideoFilter('Warm',
            'eq=saturation=1.12:brightness=0.02,'
            'colorbalance=rs=0.13:gs=0.03:bs=-0.13:rm=0.08:bm=-0.08',
            _warmPreview),
        VideoFilter('Cool',
            'eq=saturation=1.05,'
            'colorbalance=rs=-0.13:gs=-0.02:bs=0.15:rm=-0.06:bm=0.08',
            _coolPreview),
        VideoFilter('Vivid', 'eq=saturation=1.45:contrast=1.12', _sat(1.45)),
        VideoFilter('Vintage',
            'eq=saturation=0.7:contrast=0.94:brightness=0.05,'
            'colorbalance=rs=0.08:gs=0.02:bs=-0.12,vignette=PI/5',
            _vintagePreview),
        VideoFilter('B&W', 'eq=saturation=0', _sat(0)),
        VideoFilter(
            'Fade', 'eq=contrast=0.84:brightness=0.13:saturation=0.78',
            _fadePreview),
        VideoFilter('Noir',
            'eq=saturation=0.04:contrast=1.32:brightness=-0.02,'
            'vignette=PI/3.2',
            _noirPreview),
        VideoFilter('Sunset',
            'eq=saturation=1.3:brightness=0.03,'
            'colorbalance=rs=0.22:gs=0.05:bs=-0.22:rm=0.12:gm=0.02:bm=-0.12',
            _sunsetPreview),
        VideoFilter('Golden',
            'eq=saturation=1.15:contrast=0.96:brightness=0.03,'
            'colorbalance=rs=0.15:gs=0.08:bs=-0.18:rm=0.1:gm=0.04:bm=-0.1',
            _goldenPreview),
        VideoFilter('Candy',
            'eq=saturation=1.35:brightness=0.06,'
            'colorbalance=rs=0.12:bs=0.1:rm=0.08:bm=0.06',
            _candyPreview),
        VideoFilter('Teal',
            'colorbalance=rs=-0.12:gs=0.1:bs=0.18:rh=0.12:gh=0.02:bh=-0.12,'
            'eq=saturation=1.12:contrast=1.06',
            _tealPreview),
        VideoFilter('Drama',
            'eq=contrast=1.28:brightness=-0.04:saturation=0.85',
            _dramaPreview),
        VideoFilter('Beauty',
            'split[a][b];[b]gblur=sigma=2[bb];'
            '[a][bb]blend=all_mode=overlay:all_opacity=0.35,'
            'eq=brightness=0.05:contrast=0.94:saturation=1.08',
            _beautyPreview),
        VideoFilter('Retro',
            'eq=saturation=0.75:contrast=0.9:brightness=0.06,'
            'colorbalance=gs=0.08:gm=0.05:bs=-0.05,vignette=PI/4.5',
            _retroPreview),
        VideoFilter('Cyber',
            'eq=saturation=1.35:contrast=1.1,'
            'colorbalance=rs=0.12:gs=-0.05:bs=0.22:bm=0.12',
            _cyberPreview),
        VideoFilter('Midnight',
            'eq=brightness=-0.09:contrast=1.12:saturation=0.8,'
            'colorbalance=rs=-0.15:gs=-0.05:bs=0.25:bm=0.15',
            _midnightPreview),
        VideoFilter('Sepia',
            'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:'
            '.272:.534:.131:0',
            _sepiaPreview),
        VideoFilter('Dreamy',
            'split[a][b];[b]gblur=sigma=6[bb];'
            '[a][bb]blend=all_mode=screen:all_opacity=0.4,'
            'eq=brightness=0.06:saturation=1.1',
            _dreamyPreview),
        VideoFilter('Crisp',
            'unsharp=5:5:1.2:5:5:0.0,eq=contrast=1.08:saturation=1.05',
            _crispPreview),
        // Fix round: richer looks for the camera carousel — soft
        // pink beauty tint, bright airy bloom, dark teal moody.
        VideoFilter('Pink Glow',
            'eq=saturation=1.18:brightness=0.05,'
            'colorbalance=rs=0.16:bs=0.12:rm=0.1:bm=0.08',
            _pinkGlowPreview),
        VideoFilter('Bloom',
            'eq=brightness=0.09:contrast=0.92:saturation=1.12,'
            'colorbalance=rs=0.06:gs=0.02:bs=-0.06',
            _bloomPreview),
        VideoFilter('Moody',
            'eq=saturation=0.62:contrast=1.14:brightness=-0.03,'
            'colorbalance=rs=-0.06:gs=0.06:bs=0.1',
            _moodyPreview),
      ];

  static const List<double> _pinkGlowPreview = [
    1.08, 0.02, 0.03, 0, 18,
    0.01, 0.96, 0.02, 0, 8,
    0.03, 0.02, 1.06, 0, 16,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _bloomPreview = [
    0.95, 0.01, 0, 0, 26,
    0, 0.95, 0.01, 0, 24,
    0, 0, 0.93, 0, 20,
    0, 0, 0, 1, 0,
  ];

  static const List<double> _moodyPreview = [
    0.55, 0.30, 0.05, 0, -6,
    0.18, 0.68, 0.14, 0, -4,
    0.10, 0.30, 0.72, 0, 2,
    0, 0, 0, 1, 0,
  ];
}

/// One entry of the camera screen's TikTok-style LIVE carousel
/// (fix round): a look that can be previewed on the camera feed
/// itself. A look is either a colour [filter] or one of the
/// grade-style [VideoEffect]s that carries a preview matrix — both
/// bake through the exact same FFmpeg chains the edit screen uses,
/// so what you see while recording is what gets posted.
/// Structural effects (mirror, glitch…) are NOT looks: they stay
/// in the camera's Effects tab and bake at post time, as before.
class LiveLook {
  final String name;
  final VideoFilter? filter;
  final VideoEffect? effect;

  /// Draws the Cinematic letterbox bars over the live preview.
  final bool letterbox;

  const LiveLook(this.name, {this.filter, this.effect, this.letterbox = false});

  List<double>? get previewMatrix =>
      effect?.previewMatrix ?? filter?.previewMatrix;

  /// Icon shown on the carousel thumbnail.
  String get emoji => effect?.emoji ?? '🎨';
}

class LiveLooks {
  LiveLooks._();

  static VideoFilter _f(String name) =>
      VideoFilters.all.firstWhere((f) => f.name == name);

  static VideoEffect _e(String name) =>
      VideoEffects.all.firstWhere((e) => e.name == name);

  /// 30 live looks, TikTok order: beauty/popular first, moody and
  /// mono looks last.
  static final List<LiveLook> all = [
    const LiveLook('Normal'),
    LiveLook('Beauty', filter: _f('Beauty')),
    LiveLook('Soft Glow', effect: _e('Soft Glow')),
    LiveLook('Golden', filter: _f('Golden')),
    LiveLook('Sunset', filter: _f('Sunset')),
    LiveLook('Pink Glow', filter: _f('Pink Glow')),
    LiveLook('Vivid', filter: _f('Vivid')),
    LiveLook('Poster Pop', effect: _e('Poster Pop')),
    LiveLook('Warm', filter: _f('Warm')),
    LiveLook('Vintage', filter: _f('Vintage')),
    LiveLook('Retro', filter: _f('Retro')),
    LiveLook('Dreamy', filter: _f('Dreamy')),
    LiveLook('Bloom', filter: _f('Bloom')),
    LiveLook('Candy', filter: _f('Candy')),
    LiveLook('Cool', filter: _f('Cool')),
    LiveLook('Teal', filter: _f('Teal')),
    LiveLook('Cyber', filter: _f('Cyber')),
    LiveLook('Cinematic', effect: _e('Cinematic'), letterbox: true),
    LiveLook('Noir', filter: _f('Noir')),
    LiveLook('Drama', filter: _f('Drama')),
    LiveLook('Old Film', effect: _e('Old Film')),
    LiveLook('Fade', filter: _f('Fade')),
    LiveLook('Sepia', filter: _f('Sepia')),
    LiveLook('Moody', filter: _f('Moody')),
    LiveLook('Midnight', filter: _f('Midnight')),
    LiveLook('Fog', effect: _e('Fog')),
    LiveLook('X-Ray', effect: _e('X-Ray')),
    LiveLook('Underwater', effect: _e('Underwater')),
    LiveLook('B&W', filter: _f('B&W')),
    LiveLook('Crisp', filter: _f('Crisp')),
  ];
}

/// Runs FFmpeg (via ffmpeg_kit_flutter_new) to bake the chosen filter
/// or effect, trim, music change and text overlay into a NEW mp4. The
/// original file is never modified. Throws an [Exception] with a
/// friendly English message when processing fails — callers must NOT
/// fall back to uploading the unedited file in that case.
class VideoEditService {
  VideoEditService._();
  static final VideoEditService instance = VideoEditService._();

  static const _failMsg =
      'Video processing failed. Please try again with different edits.';

  static String _secs(Duration d) =>
      (d.inMilliseconds / 1000.0).toStringAsFixed(3);

  Future<File> processVideo({
    required File input,
    required VideoEditOptions options,
    required Duration videoDuration,
    required int videoHeight,
  }) async {
    final tmp = await getTemporaryDirectory();
    final out = File(
        '${tmp.path}/vibeshort_edit_${DateTime.now().millisecondsSinceEpoch}.mp4');

    // Trim window → effective output duration.
    final start = options.trimStart;
    final end = options.trimEnd;
    var effDur = (end ?? videoDuration) - start;
    final trimmed = effDur > Duration.zero &&
        effDur < videoDuration &&
        (start > Duration.zero || end != null);
    if (!trimmed) effDur = videoDuration;

    // Build the video filter chain: a selected effect replaces the
    // colour filter (its graph includes its own grade); text is last.
    final vfParts = <String>[];
    var baseChain =
        options.effect.ffmpegGraph ?? options.filter.ffmpegFilter;
    if (baseChain != null &&
        (baseChain.contains('__VIBE_FONT__') ||
            baseChain.contains('__VIBE_DATE__'))) {
      // Some effects (Camcorder) draw their own text inside the graph
      // and carry placeholders for the bundled font path and today's
      // date — resolve them here, at processing time.
      final font = await _fontFile();
      baseChain = baseChain
          .replaceAll('__VIBE_FONT__', font.path)
          .replaceAll('__VIBE_DATE__', _dateStamp());
    }
    if (baseChain != null) {
      vfParts.add(baseChain);
    }
    final text = options.overlayText.trim();
    if (text.isNotEmpty) {
      final font = await _fontFile();
      final y = switch (options.overlayPosition) {
        OverlayPosition.top => 'h*0.06',
        OverlayPosition.center => '(h-text_h)/2',
        OverlayPosition.bottom => 'h-text_h-h*0.09',
      };
      final fontSize = (videoHeight / 17).round().clamp(24, 96);
      vfParts.add("drawtext=fontfile=${font.path}"
          ":text='${_sanitize(text)}'"
          ':fontcolor=white:fontsize=$fontSize'
          ':borderw=3:bordercolor=black'
          ':x=(w-text_w)/2:y=$y');
    }
    final vf = vfParts.isEmpty ? null : vfParts.join(',');

    final args = <String>['-y'];
    if (trimmed && start > Duration.zero) {
      // Input seek (fast, frame-accurate with re-encode).
      args.addAll(['-ss', _secs(start)]);
    }
    args.addAll(['-i', input.path]);
    switch (options.musicMode) {
      case MusicMode.original:
        if (vf != null) args.addAll(['-vf', vf]);
        args.addAll([
          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
          '-c:a', 'aac', '-b:a', '128k',
        ]);
        break;
      case MusicMode.mute:
        if (vf != null || trimmed) {
          if (vf != null) args.addAll(['-vf', vf]);
          args.addAll(['-c:v', 'libx264', '-preset', 'veryfast',
              '-crf', '23']);
        } else {
          args.addAll(['-c:v', 'copy']);
        }
        args.add('-an');
        break;
      case MusicMode.replace:
        final dur = effDur.inMilliseconds / 1000.0;
        final fadeStart = (dur - 2).clamp(0.0, dur);
        args.addAll(['-stream_loop', '-1', '-i', options.musicPath!]);
        if (vf != null) args.addAll(['-vf', vf]);
        args.addAll([
          '-map', '0:v:0', '-map', '1:a:0',
          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
          '-af', 'afade=t=out:st=$fadeStart:d=2',
          '-c:a', 'aac', '-b:a', '160k',
          '-shortest',
        ]);
        break;
    }
    if (trimmed) args.addAll(['-t', _secs(effDur)]);
    args.addAll(['-movflags', '+faststart', out.path]);

    debugPrint('FFmpeg args: ${args.join(' ')}');
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc) || !await out.exists()) {
      final log = await session.getOutput();
      debugPrint('FFmpeg failed (rc=$rc): $log');
      throw Exception(_failMsg);
    }
    return out;
  }

  /// Camcorder-style date stamp, e.g. "23 OCT 2026". Contains no
  /// drawtext syntax characters, so it is safe inside a filter graph.
  static String _dateStamp() {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    final now = DateTime.now();
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  /// drawtext treats : ' \ % [ ] , ; as syntax. Strip them so the
  /// filter graph can never break on user text.
  String _sanitize(String text) => text
      .replaceAll(RegExp(r'''[:'\\%\[\],;"]'''), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<File> _fontFile() async {
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}/DejaVuSans-Bold.ttf');
    if (!await f.exists()) {
      final data = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
      await f.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return f;
  }
}
