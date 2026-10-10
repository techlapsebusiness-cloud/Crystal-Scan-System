import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Single-channel image in the range 0–1. NaN marks a sample that fell
/// outside the frame.
class GrayPlane {
  GrayPlane(this.width, this.height, this.samples)
    : assert(samples.length == width * height);

  final int width;
  final int height;
  final Float32List samples;

  double at(int x, int y) => samples[y * width + x];

  double sample(double x, double y) {
    if (x < 0 || y < 0 || x > width - 1 || y > height - 1) {
      return double.nan;
    }
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = math.min(x0 + 1, width - 1);
    final y1 = math.min(y0 + 1, height - 1);
    final tx = x - x0;
    final ty = y - y0;
    final a = at(x0, y0);
    final b = at(x1, y0);
    final c = at(x0, y1);
    final d = at(x1, y1);
    return a * (1 - tx) * (1 - ty) + b * tx * (1 - ty) + c * (1 - tx) * ty + d * tx * ty;
  }

  static GrayPlane fromImage(img.Image image) {
    final width = image.width;
    final height = image.height;
    final samples = Float32List(width * height);
    final scale = image.maxChannelValue == 0 ? 1.0 : image.maxChannelValue.toDouble();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final luma = 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;
        samples[y * width + x] = luma / scale;
      }
    }
    return GrayPlane(width, height, samples);
  }
}

GrayPlane downsampleGray(GrayPlane source) {
  final width = source.width >> 1;
  final height = source.height >> 1;
  if (width < 16 || height < 16) {
    return source;
  }
  final samples = Float32List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final sx = x * 2;
      final sy = y * 2;
      samples[y * width + x] =
          0.25 *
          (source.at(sx, sy) +
              source.at(sx + 1, sy) +
              source.at(sx, sy + 1) +
              source.at(sx + 1, sy + 1));
    }
  }
  return GrayPlane(width, height, samples);
}

List<GrayPlane> grayPyramid(GrayPlane base) {
  final levels = <GrayPlane>[base];
  var current = base;
  while (current.width > 40 && current.height > 40) {
    final next = downsampleGray(current);
    if (identical(next, current) || (next.width == current.width && next.height == current.height)) {
      break;
    }
    levels.add(next);
    current = next;
  }
  return levels;
}

double grayMean(GrayPlane plane) {
  var sum = 0.0;
  for (final value in plane.samples) {
    sum += value;
  }
  return plane.samples.isEmpty ? 0 : sum / plane.samples.length;
}

double grayStandardDeviation(GrayPlane plane) {
  if (plane.samples.isEmpty) {
    return 0;
  }
  var sum = 0.0;
  var sumSquares = 0.0;
  for (final value in plane.samples) {
    sum += value;
    sumSquares += value * value;
  }
  final count = plane.samples.length;
  final mean = sum / count;
  return math.sqrt(math.max(0, sumSquares / count - mean * mean));
}

/// Variance of a discrete Laplacian. Smooth images score low; that is not,
/// by itself, a defect.
double laplacianVariance(GrayPlane plane) {
  if (plane.width < 3 || plane.height < 3) {
    return 0;
  }
  final stride = math.max(1, math.min(plane.width, plane.height) ~/ 180);
  var sum = 0.0;
  var sumSquares = 0.0;
  var count = 0;
  for (var y = 1; y < plane.height - 1; y += stride) {
    for (var x = 1; x < plane.width - 1; x += stride) {
      final value =
          4 * plane.at(x, y) -
          plane.at(x - 1, y) -
          plane.at(x + 1, y) -
          plane.at(x, y - 1) -
          plane.at(x, y + 1);
      sum += value;
      sumSquares += value * value;
      count++;
    }
  }
  if (count == 0) {
    return 0;
  }
  final mean = sum / count;
  return math.max(0, sumSquares / count - mean * mean);
}

({double highlight, double shadow}) clipFractions(GrayPlane plane) {
  if (plane.samples.isEmpty) {
    return (highlight: 0, shadow: 0);
  }
  var high = 0;
  var low = 0;
  for (final value in plane.samples) {
    if (value >= 0.97) {
      high++;
    } else if (value <= 0.03) {
      low++;
    }
  }
  final count = plane.samples.length;
  return (highlight: high / count, shadow: low / count);
}
