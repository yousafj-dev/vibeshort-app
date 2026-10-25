import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// REAL face effects (camera upgrade round): on-device face
/// detection (ML Kit) finds the face on the live camera feed, a
/// sticker is drawn over it LIVE in the preview, its position is
/// logged while recording, and on post the exact same sticker is
/// baked into the video with FFmpeg at the logged positions —
/// what you see while recording is what gets posted.
///
/// This is deliberately NOT Snapchat-style AR: no face mesh, no
/// beauty/skin smoothing. The three stickers below are drawn from
/// the face bounding box + eye landmarks, which is what the free
/// on-device detector reliably provides.
enum FaceStickerKind { sunglasses, crown, starGlasses }

class FaceSticker {
  final FaceStickerKind kind;
  final String name;
  final String emoji;

  /// Sticker height / width ratio — the geometry function and the
  /// rendered PNG both honour it, so preview and bake agree.
  final double aspect;

  const FaceSticker(this.kind, this.name, this.emoji, this.aspect);

  static FaceSticker of(FaceStickerKind kind) =>
      FaceStickers.all.firstWhere((s) => s.kind == kind);
}

class FaceStickers {
  FaceStickers._();

  static const List<FaceSticker> all = [
    FaceSticker(FaceStickerKind.sunglasses, 'Shades', '🕶️', 0.34),
    FaceSticker(FaceStickerKind.crown, 'Crown', '👑', 0.62),
    FaceSticker(FaceStickerKind.starGlasses, 'Stars', '⭐', 0.44),
  ];
}

/// A detected face reduced to what the stickers need, in UPRIGHT
/// image coordinates (the space ML Kit reports once the camera
/// rotation is applied — the same orientation the recorded video
/// is displayed in).
class FaceGeometry {
  final Rect faceRect;
  final Offset? leftEye;
  final Offset? rightEye;

  const FaceGeometry({required this.faceRect, this.leftEye, this.rightEye});
}

/// One logged detection while recording: the primary (largest)
/// face at [tSeconds] after the recording started.
class FaceTrackSample {
  final double tSeconds;
  final FaceGeometry face;

  const FaceTrackSample(this.tSeconds, this.face);
}

/// The full face track handed from the record screen to the edit
/// screen: raw samples plus the upright image size they live in.
class FaceTrackData {
  final FaceStickerKind recordedKind;
  final Size imageSize;
  final List<FaceTrackSample> samples;

  const FaceTrackData({
    required this.recordedKind,
    required this.imageSize,
    required this.samples,
  });

  /// Compiles samples into ~0.5s bake segments for [kind]: each
  /// bucket takes its LAST sample's sticker rect; a bucket with no
  /// sample holds the previous rect for up to 1s (two buckets),
  /// then the sticker honestly disappears until the face returns.
  List<FaceBakeSegment> buildSegments(FaceStickerKind kind) {
    if (samples.isEmpty) return const [];
    final sorted = [...samples]
      ..sort((a, b) => a.tSeconds.compareTo(b.tSeconds));
    const bucket = 0.5;
    final firstBucket = (sorted.first.tSeconds / bucket).floor();
    final lastBucket = (sorted.last.tSeconds / bucket).floor();
    final segments = <FaceBakeSegment>[];
    Rect? carry;
    var hold = 0;
    for (var b = firstBucket; b <= lastBucket; b++) {
      final start = b * bucket;
      final end = start + bucket;
      FaceTrackSample? last;
      for (final s in sorted) {
        if (s.tSeconds >= start && s.tSeconds < end) last = s;
      }
      Rect? rect;
      if (last != null) {
        rect = stickerRectFor(kind, last.face);
        carry = rect;
        hold = 0;
      } else if (carry != null && hold < 2) {
        rect = carry;
        hold++;
      } else {
        carry = null;
      }
      if (rect != null) {
        segments.add(FaceBakeSegment(start, end, rect));
      }
    }
    return segments;
  }
}

/// One bake segment: draw the sticker at [rect] (upright image
/// coordinates) between [start] and [end] seconds of the
/// RECORDED timeline (the edit service shifts it for trims).
class FaceBakeSegment {
  final double start;
  final double end;
  final Rect rect;

  const FaceBakeSegment(this.start, this.end, this.rect);
}

/// What the edit screen passes to the bake: which sticker, and the
/// track recorded on the camera screen.
class FaceBakeData {
  final FaceStickerKind kind;
  final FaceTrackData track;

  const FaceBakeData({required this.kind, required this.track});
}

/// Where the sticker goes for a face — shared by the live preview
/// painter and the bake so both place it identically.
Rect stickerRectFor(FaceStickerKind kind, FaceGeometry face) {
  final box = face.faceRect;
  switch (kind) {
    case FaceStickerKind.sunglasses:
    case FaceStickerKind.starGlasses:
      final le = face.leftEye;
      final re = face.rightEye;
      final hasEyes = le != null && re != null;
      final cx = hasEyes ? (le.dx + re.dx) / 2 : box.center.dx;
      final eyeY = hasEyes ? (le.dy + re.dy) / 2 : box.top + box.height * 0.38;
      final w = box.width * (kind == FaceStickerKind.sunglasses ? 1.06 : 1.12);
      final h = w * FaceSticker.of(kind).aspect;
      return Rect.fromLTWH(cx - w / 2, eyeY - h / 2, w, h);
    case FaceStickerKind.crown:
      final w = box.width * 0.72;
      final h = w * FaceSticker.of(kind).aspect;
      return Rect.fromLTWH(box.center.dx - w / 2, box.top - h * 0.88, w, h);
  }
}

/// Draws a sticker into [rect]. Used for the LIVE preview (a
/// CustomPainter calls this per face) and to render the PNG the
/// FFmpeg bake overlays — one drawing, both surfaces.
void paintFaceSticker(Canvas canvas, Rect rect, FaceStickerKind kind) {
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.scale(rect.width, rect.height);
  switch (kind) {
    case FaceStickerKind.sunglasses:
      _paintSunglasses(canvas);
      break;
    case FaceStickerKind.crown:
      _paintCrown(canvas);
      break;
    case FaceStickerKind.starGlasses:
      _paintStarGlasses(canvas);
      break;
  }
  canvas.restore();
}

void _paintSunglasses(Canvas canvas) {
  final black = Paint()..color = const Color(0xFF101016);
  final shine = Paint()..color = const Color(0x33FFFFFF);
  final frame = Paint()
    ..color = const Color(0xFF101016)
    ..strokeWidth = 0.055
    ..strokeCap = StrokeCap.round;
  // Temple arms to the edges of the sticker box.
  canvas.drawLine(const Offset(0.0, 0.28), const Offset(0.10, 0.30), frame);
  canvas.drawLine(const Offset(1.0, 0.28), const Offset(0.90, 0.30), frame);
  // Lenses.
  final left = RRect.fromRectAndRadius(
      const Rect.fromLTRB(0.03, 0.16, 0.45, 0.92),
      const Radius.circular(0.10));
  final right = RRect.fromRectAndRadius(
      const Rect.fromLTRB(0.55, 0.16, 0.97, 0.92),
      const Radius.circular(0.10));
  canvas.drawRRect(left, black);
  canvas.drawRRect(right, black);
  // Bridge.
  canvas.drawLine(const Offset(0.45, 0.32), const Offset(0.55, 0.32), frame);
  // Lens shine.
  canvas.drawLine(const Offset(0.13, 0.78), const Offset(0.30, 0.34), shine);
  canvas.drawLine(const Offset(0.63, 0.78), const Offset(0.80, 0.34), shine);
}

void _paintCrown(Canvas canvas) {
  final gold = Paint()..color = const Color(0xFFFFC93C);
  final goldEdge = Paint()
    ..color = const Color(0xFFB8860B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.03;
  final path = Path()
    ..moveTo(0.06, 0.96)
    ..lineTo(0.06, 0.38)
    ..lineTo(0.28, 0.64)
    ..lineTo(0.50, 0.20)
    ..lineTo(0.72, 0.64)
    ..lineTo(0.94, 0.38)
    ..lineTo(0.94, 0.96)
    ..close();
  canvas.drawPath(path, gold);
  canvas.drawPath(path, goldEdge);
  // Peak jewels.
  final jewel = Paint()..color = const Color(0xFFFFC93C);
  final jewelEdge = Paint()
    ..color = const Color(0xFFB8860B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.025;
  for (final c in [const Offset(0.06, 0.30), const Offset(0.50, 0.12), const Offset(0.94, 0.30)]) {
    canvas.drawCircle(c, 0.055, jewel);
    canvas.drawCircle(c, 0.055, jewelEdge);
  }
  // Centre gem + base band.
  canvas.drawCircle(const Offset(0.50, 0.78),
      0.075, Paint()..color = const Color(0xFFE63950));
  canvas.drawRect(const Rect.fromLTRB(0.06, 0.86, 0.94, 0.96),
      Paint()..color = const Color(0xFFF5A623));
}

void _paintStarGlasses(Canvas canvas) {
  final gold = Paint()..color = const Color(0xFFFFD93B);
  final edge = Paint()
    ..color = const Color(0xFF8A6D00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.03
    ..strokeJoin = StrokeJoin.round;
  Path star(Offset center, double rOuter, double rInner) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? rOuter : rInner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    return p..close();
  }

  final left = star(const Offset(0.25, 0.50), 0.245, 0.115);
  final right = star(const Offset(0.75, 0.50), 0.245, 0.115);
  canvas.drawPath(left, gold);
  canvas.drawPath(left, edge);
  canvas.drawPath(right, gold);
  canvas.drawPath(right, edge);
  // Bridge + arms.
  final frame = Paint()
    ..color = const Color(0xFF8A6D00)
    ..strokeWidth = 0.045
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(const Offset(0.47, 0.44), const Offset(0.53, 0.44), frame);
  canvas.drawLine(const Offset(0.02, 0.40), const Offset(0.06, 0.44), frame);
  canvas.drawLine(const Offset(0.98, 0.40), const Offset(0.94, 0.44), frame);
}

/// Renders a sticker to a PNG file (512px wide) for the FFmpeg
/// bake. The bake scales it per segment to the logged face size.
Future<File> renderStickerPng(FaceStickerKind kind) async {
  const double w = 512;
  final h = w * FaceSticker.of(kind).aspect;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintFaceSticker(canvas, Rect.fromLTWH(0, 0, w, h), kind);
  final picture = recorder.endRecording();
  final img = await picture.toImage(w.round(), h.round());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final tmp = await getTemporaryDirectory();
  final f = File('${tmp.path}/vibe_sticker_${kind.name}.png');
  await f.writeAsBytes(bytes!.buffer.asUint8List());
  return f;
}
