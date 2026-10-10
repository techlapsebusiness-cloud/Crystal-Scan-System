import 'dart:math' as math;
import 'dart:typed_data';

import 'package:microscopeapp/features/reconstruction/data/gray_plane.dart';

/// Maps a reference pixel to the source frame.
///
/// source(x, y) matches reference(x + dx, y + dy) after the source has been
/// rotated by [angleDegrees] around its center. Fusion therefore samples the
/// source at (x - dx, y - dy), then undoes that rotation.
class PlaneTransform {
  const PlaneTransform({this.dx = 0, this.dy = 0, this.angleDegrees = 0});

  final double dx;
  final double dy;
  final double angleDegrees;

  (double x, double y) sourceAt(double x, double y, int width, int height) {
    final untranslatedX = x - dx;
    final untranslatedY = y - dy;
    if (angleDegrees.abs() < 1e-8) {
      return (untranslatedX, untranslatedY);
    }
    final radians = -angleDegrees * math.pi / 180.0;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    final centerX = (width - 1) / 2.0;
    final centerY = (height - 1) / 2.0;
    final deltaX = untranslatedX - centerX;
    final deltaY = untranslatedY - centerY;
    return (
      centerX + deltaX * cosine - deltaY * sine,
      centerY + deltaX * sine + deltaY * cosine,
    );
  }
}

GrayPlane rotateGray(GrayPlane source, double degrees) {
  if (degrees.abs() < 1e-8) {
    return source;
  }
  final transform = PlaneTransform(angleDegrees: degrees);
  final samples = Float32List(source.width * source.height);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final (sx, sy) = transform.sourceAt(x.toDouble(), y.toDouble(), source.width, source.height);
      samples[y * source.width + x] = source.sample(sx, sy);
    }
  }
  return GrayPlane(source.width, source.height, samples);
}
