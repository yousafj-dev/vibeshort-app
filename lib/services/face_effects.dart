import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// REAL face effects (camera upgrade round; expanded in fix
/// round 2): on-device face detection (ML Kit) finds the face on
/// the live camera feed, a sticker is drawn over it LIVE in the
/// preview, its position is logged while recording, and on post
/// the exact same sticker is baked into the video with FFmpeg at
/// the logged positions — what you see while recording is what
/// gets posted.
///
/// This is deliberately NOT Snapchat-style AR: no face mesh, no
/// beauty/skin smoothing. The stickers below are drawn from the
/// face bounding box + landmarks + the face-oval contour, which
/// is what the free on-device detector reliably provides.
///
/// Fix round 2 accuracy pass: contours are enabled, the geometry
/// now carries nose / mouth / ears / oval anchors (not just the
/// eyes), and the record screen smooths every detection with an
/// exponential moving average before it reaches this file — the
/// preview and the bake consume the same smoothed geometry, so
/// they agree and the sticker does not jitter.
enum FaceStickerKind {
  sunglasses,
  crown,
  starGlasses,
  flowerCrown,
  dogEars,
  catEars,
  bunnyEars,
  mustache,
  cap,
  halo,
}

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
    FaceSticker(FaceStickerKind.flowerCrown, 'Flowers', '🌸', 0.34),
    FaceSticker(FaceStickerKind.dogEars, 'Dog', '🐶', 0.66),
    FaceSticker(FaceStickerKind.catEars, 'Cat', '🐱', 0.38),
    FaceSticker(FaceStickerKind.bunnyEars, 'Bunny', '🐰', 0.70),
    FaceSticker(FaceStickerKind.mustache, 'Stache', '🥸', 0.32),
    FaceSticker(FaceStickerKind.cap, 'Cap', '🧢', 0.42),
    FaceSticker(FaceStickerKind.halo, 'Halo', '😇', 0.30),
  ];
}

/// A detected face reduced to what the stickers need, in UPRIGHT
/// image coordinates (the space ML Kit reports once the camera
/// rotation is applied — the same orientation the recorded video
/// is displayed in). Every anchor beyond the bounding box is
/// nullable: detectors occasionally drop a landmark, and the
/// geometry functions fall back to box-relative positions instead
/// of losing the sticker.
class FaceGeometry {
  final Rect faceRect;
  final Offset? leftEye;
  final Offset? rightEye;
  final Offset? noseBase;
  final Offset? mouthLeft;
  final Offset? mouthRight;
  final Offset? mouthBottom;

  /// Centroid of the upper-lip-top contour — the mustache anchor.
  final Offset? mouthTop;
  final Offset? leftEar;
  final Offset? rightEar;

  /// Extremes of the face-oval contour: top of the forehead and
  /// the widest left/right points. Head-top stickers (crown,
  /// ears, cap, halo) anchor to [ovalTop] when present.
  final Offset? ovalTop;
  final Offset? ovalLeft;
  final Offset? ovalRight;

  const FaceGeometry({
    required this.faceRect,
    this.leftEye,
    this.rightEye,
    this.noseBase,
    this.mouthLeft,
    this.mouthRight,
    this.mouthBottom,
    this.mouthTop,
    this.leftEar,
    this.rightEar,
    this.ovalTop,
    this.ovalLeft,
    this.ovalRight,
  });

  /// Exponential smoothing between two detections of the same
  /// face: [t] of the way from [a] (previous) to [b] (new). The
  /// record screen applies this to every frame so a sticker
  /// glides instead of jumping between raw detector readings.
  static FaceGeometry smooth(FaceGeometry a, FaceGeometry b, double t) {
    Offset? lp(Offset? x, Offset? y) =>
        (x == null || y == null) ? (y ?? x) : Offset.lerp(x, y, t);
    return FaceGeometry(
      faceRect: Rect.lerp(a.faceRect, b.faceRect, t) ?? b.faceRect,
      leftEye: lp(a.leftEye, b.leftEye),
      rightEye: lp(a.rightEye, b.rightEye),
      noseBase: lp(a.noseBase, b.noseBase),
      mouthLeft: lp(a.mouthLeft, b.mouthLeft),
      mouthRight: lp(a.mouthRight, b.mouthRight),
      mouthBottom: lp(a.mouthBottom, b.mouthBottom),
      mouthTop: lp(a.mouthTop, b.mouthTop),
      leftEar: lp(a.leftEar, b.leftEar),
      rightEar: lp(a.rightEar, b.rightEar),
      ovalTop: lp(a.ovalTop, b.ovalTop),
      ovalLeft: lp(a.ovalLeft, b.ovalLeft),
      ovalRight: lp(a.ovalRight, b.ovalRight),
    );
  }
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
  final aspect = FaceSticker.of(kind).aspect;
  // Top-of-head anchor: the face-oval contour's highest point,
  // falling back to the bounding box top.
  final headTopY = face.ovalTop?.dy ?? box.top;
  final headCx = face.ovalTop?.dx ?? box.center.dx;
  switch (kind) {
    case FaceStickerKind.sunglasses:
    case FaceStickerKind.starGlasses:
      final le = face.leftEye;
      final re = face.rightEye;
      final hasEyes = le != null && re != null;
      final cx = hasEyes ? (le.dx + re.dx) / 2 : box.center.dx;
      final eyeY = hasEyes ? (le.dy + re.dy) / 2 : box.top + box.height * 0.38;
      final w = box.width * (kind == FaceStickerKind.sunglasses ? 1.06 : 1.12);
      final h = w * aspect;
      return Rect.fromLTWH(cx - w / 2, eyeY - h / 2, w, h);
    case FaceStickerKind.crown:
      final w = box.width * 0.72;
      final h = w * aspect;
      return Rect.fromLTWH(box.center.dx - w / 2, box.top - h * 0.88, w, h);
    case FaceStickerKind.flowerCrown:
      // A flower band straddling the hairline: widest of the
      // head-top stickers, centred on the oval's top point.
      final w = box.width * 1.02;
      final h = w * aspect;
      return Rect.fromLTWH(headCx - w / 2, headTopY - h * 0.62, w, h);
    case FaceStickerKind.dogEars:
      // Ears at the top corners + a dog nose on the nose anchor,
      // all in ONE rect: it runs from just above the head down to
      // the nose, which the painter draws at a fixed 0.86 of the
      // rect height — so the rect height is derived from where
      // the nose actually is.
      final nose = face.noseBase ??
          Offset(box.center.dx, box.top + box.height * 0.60);
      const noseFrac = 0.86;
      final top = headTopY - box.height * 0.02;
      var h = (nose.dy - top) / noseFrac;
      h = h.clamp(box.height * 0.55, box.height * 1.7).toDouble();
      final w = box.width * 1.24;
      return Rect.fromLTWH(headCx - w / 2, top, w, h);
    case FaceStickerKind.catEars:
      final w = box.width * 1.08;
      final h = w * aspect;
      return Rect.fromLTWH(headCx - w / 2, headTopY - h * 0.85, w, h);
    case FaceStickerKind.bunnyEars:
      final w = box.width * 0.94;
      final h = w * aspect;
      return Rect.fromLTWH(headCx - w / 2, headTopY - h * 0.95, w, h);
    case FaceStickerKind.mustache:
      // Centred between the nose base and the top of the mouth —
      // the philtrum — from the real landmarks when present.
      final nose = face.noseBase;
      final double cy;
      if (nose != null && face.mouthTop != null) {
        cy = (nose.dy + face.mouthTop!.dy) / 2;
      } else if (nose != null) {
        cy = nose.dy + box.height * 0.06;
      } else {
        cy = box.top + box.height * 0.685;
      }
      final cx = nose?.dx ?? box.center.dx;
      final w = box.width * 0.58;
      final h = w * aspect;
      return Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h);
    case FaceStickerKind.cap:
      final w = box.width * 1.10;
      final h = w * aspect;
      return Rect.fromLTWH(headCx - w / 2, headTopY - h * 0.70, w, h);
    case FaceStickerKind.halo:
      // Floating above the head with a clear gap.
      final w = box.width * 0.70;
      final h = w * aspect;
      return Rect.fromLTWH(
          headCx - w / 2, headTopY - h - box.height * 0.13, w, h);
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
    case FaceStickerKind.flowerCrown:
      _paintFlowerCrown(canvas);
      break;
    case FaceStickerKind.dogEars:
      _paintDogEars(canvas);
      break;
    case FaceStickerKind.catEars:
      _paintCatEars(canvas);
      break;
    case FaceStickerKind.bunnyEars:
      _paintBunnyEars(canvas);
      break;
    case FaceStickerKind.mustache:
      _paintMustache(canvas);
      break;
    case FaceStickerKind.cap:
      _paintCap(canvas);
      break;
    case FaceStickerKind.halo:
      _paintHalo(canvas);
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

void _paintFlowerCrown(Canvas canvas) {
  // Leafy band along the bottom of the arc.
  final leaf = Paint()..color = const Color(0xFF3E9B4F);
  for (var i = 0; i < 6; i++) {
    final t = i / 5;
    final cx = 0.10 + 0.80 * t;
    final cy = 0.66 - 0.26 * math.sin(math.pi * t);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 0.10), width: 0.11, height: 0.07),
        leaf);
  }
  // Seven flowers along a shallow arc — the middle one highest,
  // following the curve of the top of the head.
  const petalColors = [
    Color(0xFFFF7BAC),
    Color(0xFFFFFFFF),
    Color(0xFFFFC93C),
    Color(0xFFFF7BAC),
    Color(0xFFFFFFFF),
    Color(0xFFFFC93C),
    Color(0xFFFF7BAC),
  ];
  final centerPaint = Paint()..color = const Color(0xFFFF9F1C);
  for (var i = 0; i < 7; i++) {
    final t = i / 6;
    final c = Offset(0.08 + 0.84 * t, 0.62 - 0.30 * math.sin(math.pi * t));
    final petal = Paint()..color = petalColors[i];
    for (var k = 0; k < 5; k++) {
      final a = -math.pi / 2 + k * 2 * math.pi / 5;
      canvas.drawCircle(
          c + Offset(0.052 * math.cos(a), 0.052 * math.sin(a)), 0.046, petal);
    }
    canvas.drawCircle(c, 0.034, centerPaint);
  }
}

/// One floppy / upright ear drawn as a rotated ellipse pair,
/// shared by the dog and bunny stickers.
void _paintEar(Canvas canvas, Offset center, double angle, double w, double h,
    Color fill, Color inner) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(angle);
  canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()..color = fill);
  canvas.drawOval(
      Rect.fromCenter(
          center: Offset(0, h * 0.05), width: w * 0.55, height: h * 0.68),
      Paint()..color = inner);
  canvas.restore();
}

void _paintDogEars(Canvas canvas) {
  // Floppy ears hanging at the top corners of the head.
  _paintEar(canvas, const Offset(0.09, 0.34), 0.38, 0.19, 0.52,
      const Color(0xFF9C6642), const Color(0xFF6F4525));
  _paintEar(canvas, const Offset(0.91, 0.34), -0.38, 0.19, 0.52,
      const Color(0xFF9C6642), const Color(0xFF6F4525));
  // Dog nose on the nose anchor (drawn at the rect fraction the
  // geometry function reserves for it: 0.86 of the height).
  final nose = Paint()..color = const Color(0xFF43302B);
  canvas.drawOval(
      Rect.fromCenter(center: const Offset(0.50, 0.86), width: 0.15, height: 0.105),
      nose);
  canvas.drawOval(
      Rect.fromCenter(center: const Offset(0.465, 0.835), width: 0.045, height: 0.03),
      Paint()..color = const Color(0x66FFFFFF));
  // Philtrum line down from the nose.
  canvas.drawLine(
      const Offset(0.50, 0.905),
      const Offset(0.50, 0.965),
      Paint()
        ..color = const Color(0xFF43302B)
        ..strokeWidth = 0.022
        ..strokeCap = StrokeCap.round);
}

void _paintCatEars(Canvas canvas) {
  final fill = Paint()..color = const Color(0xFF464653);
  final soft = Paint()
    ..color = const Color(0xFF464653)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.045
    ..strokeJoin = StrokeJoin.round;
  final inner = Paint()..color = const Color(0xFFFF9FB2);
  Path ear(List<Offset> pts) {
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final pt in pts.skip(1)) {
      p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  Path innerOf(List<Offset> pts) {
    final c = Offset(
      (pts[0].dx + pts[1].dx + pts[2].dx) / 3,
      (pts[0].dy + pts[1].dy + pts[2].dy) / 3,
    );
    return ear([for (final pt in pts) c + (pt - c) * 0.52]);
  }

  const leftPts = [Offset(0.05, 0.88), Offset(0.13, 0.08), Offset(0.38, 0.62)];
  const rightPts = [Offset(0.95, 0.88), Offset(0.87, 0.08), Offset(0.62, 0.62)];
  for (final pts in [leftPts, rightPts]) {
    final p = ear(pts);
    canvas.drawPath(p, fill);
    canvas.drawPath(p, soft);
    canvas.drawPath(innerOf(pts), inner);
  }
}

void _paintBunnyEars(Canvas canvas) {
  // Long upright ears with pink inners, on a slim head band.
  _paintEar(canvas, const Offset(0.335, 0.42), -0.15, 0.165, 0.78,
      const Color(0xFFF5F5F7), const Color(0xFFFFB3C7));
  _paintEar(canvas, const Offset(0.665, 0.42), 0.15, 0.165, 0.78,
      const Color(0xFFF5F5F7), const Color(0xFFFFB3C7));
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTRB(0.27, 0.86, 0.73, 1.0),
          const Radius.circular(0.06)),
      Paint()..color = const Color(0xFFF5F5F7));
}

void _paintMustache(Canvas canvas) {
  final hair = Paint()..color = const Color(0xFF2B2622);
  // One handlebar half; the other is its mirror image.
  final half = Path()
    ..moveTo(0.50, 0.26)
    ..cubicTo(0.40, 0.02, 0.16, 0.02, 0.08, 0.20)
    ..cubicTo(0.02, 0.34, 0.05, 0.55, 0.14, 0.61)
    ..cubicTo(0.24, 0.67, 0.31, 0.52, 0.37, 0.50)
    ..cubicTo(0.43, 0.52, 0.46, 0.62, 0.50, 0.68)
    ..close();
  canvas.drawPath(half, hair);
  canvas.save();
  canvas.translate(1.0, 0.0);
  canvas.scale(-1.0, 1.0);
  canvas.drawPath(half, hair);
  canvas.restore();
}

void _paintCap(Canvas canvas) {
  // Dome.
  final dome = Path()
    ..moveTo(0.10, 0.80)
    ..cubicTo(0.12, 0.30, 0.30, 0.08, 0.50, 0.08)
    ..cubicTo(0.70, 0.08, 0.88, 0.30, 0.90, 0.80)
    ..close();
  canvas.drawPath(dome, Paint()..color = const Color(0xFF00C2FF));
  // Panel seams + top button.
  final seam = Paint()
    ..color = const Color(0xFF0E9BD8)
    ..strokeWidth = 0.028
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(const Offset(0.50, 0.12), const Offset(0.28, 0.78), seam);
  canvas.drawLine(const Offset(0.50, 0.12), const Offset(0.72, 0.78), seam);
  canvas.drawCircle(const Offset(0.50, 0.10), 0.045,
      Paint()..color = const Color(0xFF7C4DFF));
  // Brim across the front.
  canvas.drawOval(
      Rect.fromCenter(center: const Offset(0.50, 0.86), width: 1.04, height: 0.22),
      Paint()..color = const Color(0xFF7C4DFF));
}

void _paintHalo(Canvas canvas) {
  final oval = Rect.fromCenter(
      center: const Offset(0.50, 0.50), width: 0.86, height: 0.62);
  canvas.drawOval(
      oval,
      Paint()
        ..color = const Color(0x55FFD93B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.13);
  canvas.drawOval(
      oval,
      Paint()
        ..color = const Color(0xFFFFD93B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06);
  canvas.drawArc(
      oval,
      -2.7,
      1.5,
      false,
      Paint()
        ..color = const Color(0xFFFFF3B0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.025
        ..strokeCap = StrokeCap.round);
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
