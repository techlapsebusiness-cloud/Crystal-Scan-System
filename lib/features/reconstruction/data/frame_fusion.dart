import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:microscopeapp/features/reconstruction/data/frame_inspection.dart';
import 'package:microscopeapp/features/reconstruction/data/plane_transform.dart';

class FusionFrame {
  const FusionFrame({
    required this.path,
    required this.transform,
    required this.registrationMae,
  });

  final String path;
  final PlaneTransform transform;
  final double registrationMae;
}

class DenoiseOutput {
  const DenoiseOutput({this.image, this.failure});

  final img.Image? image;
  final String? failure;
}

class SuperResolutionOutput {
  const SuperResolutionOutput({
    required this.image,
    required this.reprojectionError,
    required this.coverage,
  });

  final img.Image image;
  final double reprojectionError;
  final double coverage;
}

const int _outlierDelta = 42;
const int _scale = 2;

/// Robust average of registered frames. Pixels that disagree with the
/// reference are left out so a moving object does not leave a ghost.
Future<DenoiseOutput> denoiseFrames({
  required img.Image reference,
  required String referencePath,
  required List<FusionFrame> frames,
  required bool rejectOutliers,
  required bool Function() isCancelled,
  void Function(int completed, int total)? onFrame,
}) async {
  final width = reference.width;
  final height = reference.height;
  final count = width * height;
  final Uint32List sumR;
  final Uint32List sumG;
  final Uint32List sumB;
  final Uint32List weights;
  try {
    sumR = Uint32List(count);
    sumG = Uint32List(count);
    sumB = Uint32List(count);
    weights = Uint32List(count);
  } on OutOfMemoryError {
    return const DenoiseOutput(
      failure: 'There is not enough memory to combine these frames at their native size.',
    );
  }

  var fused = 0;
  for (final frame in frames) {
    if (isCancelled()) {
      return const DenoiseOutput();
    }
    onFrame?.call(fused, frames.length);
    final image = await imageForFrame(frame: frame, reference: reference, referencePath: referencePath);
    if (image == null) {
      continue;
    }
    if (image.width != width || image.height != height) {
      continue;
    }
    final gain = identical(image, reference) ? 1.0 : _estimateGain(reference, image, frame.transform);
    final weight = _frameWeight(frame.registrationMae);
    final scale = image.maxChannelValue == 0 ? 1.0 : image.maxChannelValue.toDouble();
    final referenceScale = reference.maxChannelValue == 0
        ? 1.0
        : reference.maxChannelValue.toDouble();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final color = _read(image, frame.transform, x, y, scale);
        if (color == null) {
          continue;
        }
        final red = (color.r * gain).round().clamp(0, 255);
        final green = (color.g * gain).round().clamp(0, 255);
        final blue = (color.b * gain).round().clamp(0, 255);
        if (rejectOutliers && !identical(image, reference)) {
          final basis = _read(reference, const PlaneTransform(), x, y, referenceScale);
          if (basis != null && _far(red, green, blue, basis)) {
            continue;
          }
        }
        final index = y * width + x;
        sumR[index] += red * weight;
        sumG[index] += green * weight;
        sumB[index] += blue * weight;
        weights[index] += weight;
      }
    }
    fused++;
    onFrame?.call(fused, frames.length);
  }

  final output = img.Image(width: width, height: height, numChannels: 3);
  final referenceScale = reference.maxChannelValue == 0 ? 1.0 : reference.maxChannelValue.toDouble();
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      final weight = weights[index];
      if (weight == 0) {
        final basis = _read(reference, const PlaneTransform(), x, y, referenceScale);
        output.setPixelRgb(x, y, basis?.r.round() ?? 0, basis?.g.round() ?? 0, basis?.b.round() ?? 0);
      } else {
        output.setPixelRgb(
          x,
          y,
          sumR[index] ~/ weight,
          sumG[index] ~/ weight,
          sumB[index] ~/ weight,
        );
      }
    }
  }
  return DenoiseOutput(image: output);
}

/// Shift-and-add onto a 2× grid, then a few iterative back-projection steps.
///
/// Returns null when the samples do not cover the high-resolution grid. The
/// caller must keep the native-resolution denoise in that case.
Future<SuperResolutionOutput?> superResolveFrames({
  required img.Image reference,
  required String referencePath,
  required img.Image denoised,
  required List<FusionFrame> frames,
  required bool rejectOutliers,
  required bool Function() isCancelled,
  void Function(int completed, int total)? onFrame,
}) async {
  final width = reference.width * _scale;
  final height = reference.height * _scale;
  final count = width * height;
  final Float32List sumR;
  final Float32List sumG;
  final Float32List sumB;
  final Float32List sumW;
  try {
    sumR = Float32List(count);
    sumG = Float32List(count);
    sumB = Float32List(count);
    sumW = Float32List(count);
  } on OutOfMemoryError {
    return null;
  }

  var splatted = 0;
  for (final frame in frames) {
    if (isCancelled()) {
      return null;
    }
    onFrame?.call(splatted, frames.length + 2);
    final image = await imageForFrame(frame: frame, reference: reference, referencePath: referencePath);
    if (image == null || image.width != reference.width || image.height != reference.height) {
      splatted++;
      continue;
    }
    final gain = identical(image, reference) ? 1.0 : _estimateGain(reference, image, frame.transform);
    final weight = _frameWeight(frame.registrationMae).toDouble();
    final scale = image.maxChannelValue == 0 ? 1.0 : image.maxChannelValue.toDouble();
    final referenceScale = reference.maxChannelValue == 0
        ? 1.0
        : reference.maxChannelValue.toDouble();
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final red = (pixel.r * 255.0 / scale * gain).round().clamp(0, 255);
        final green = (pixel.g * 255.0 / scale * gain).round().clamp(0, 255);
        final blue = (pixel.b * 255.0 / scale * gain).round().clamp(0, 255);
        if (rejectOutliers && !identical(image, reference)) {
          final basis = _sampleRgb(
            reference,
            x + frame.transform.dx,
            y + frame.transform.dy,
            referenceScale,
          );
          if (basis != null && _far(red, green, blue, basis)) {
            continue;
          }
        }
        _splat(
          sumR,
          sumG,
          sumB,
          sumW,
          width,
          height,
          (x + frame.transform.dx) * _scale,
          (y + frame.transform.dy) * _scale,
          red.toDouble(),
          green.toDouble(),
          blue.toDouble(),
          weight,
        );
      }
    }
    splatted++;
    onFrame?.call(splatted, frames.length + 2);
  }

  var covered = 0;
  for (final weight in sumW) {
    if (weight > 1e-3) {
      covered++;
    }
  }
  final coverage = count == 0 ? 0.0 : covered / count;
  if (coverage < 0.8) {
    return null;
  }

  final initialR = Float32List(count);
  final initialG = Float32List(count);
  final initialB = Float32List(count);
  for (var i = 0; i < count; i++) {
    if (sumW[i] > 1e-3) {
      initialR[i] = sumR[i] / sumW[i];
      initialG[i] = sumG[i] / sumW[i];
      initialB[i] = sumB[i] / sumW[i];
    } else {
      final filled = _denoisedAt(denoised, i % width, i ~/ width);
      initialR[i] = filled.r;
      initialG[i] = filled.g;
      initialB[i] = filled.b;
    }
  }
  final estimateR = Float32List.fromList(initialR);
  final estimateG = Float32List.fromList(initialG);
  final estimateB = Float32List.fromList(initialB);

  for (var iteration = 0; iteration < 2; iteration++) {
    if (isCancelled()) {
      return null;
    }
    onFrame?.call(frames.length + iteration, frames.length + 2);
    for (final frame in frames) {
      final image = await imageForFrame(frame: frame, reference: reference, referencePath: referencePath);
      if (image == null) {
        continue;
      }
      final gain = identical(image, reference) ? 1.0 : _estimateGain(reference, image, frame.transform);
      final scale = image.maxChannelValue == 0 ? 1.0 : image.maxChannelValue.toDouble();
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final observedR = pixel.r * 255.0 / scale * gain;
          final observedG = pixel.g * 255.0 / scale * gain;
          final observedB = pixel.b * 255.0 / scale * gain;
          final hx = (x + frame.transform.dx) * _scale;
          final hy = (y + frame.transform.dy) * _scale;
          final predicted = _sampleEstimate(estimateR, estimateG, estimateB, width, height, hx, hy);
          if (predicted == null) {
            continue;
          }
          _splat(
            estimateR,
            estimateG,
            estimateB,
            null,
            width,
            height,
            hx,
            hy,
            (observedR - predicted.r) * 0.55,
            (observedG - predicted.g) * 0.55,
            (observedB - predicted.b) * 0.55,
            1,
          );
        }
      }
    }
    for (var i = 0; i < count; i++) {
      estimateR[i] = (estimateR[i] * 0.88 + initialR[i] * 0.12).clamp(0, 255);
      estimateG[i] = (estimateG[i] * 0.88 + initialG[i] * 0.12).clamp(0, 255);
      estimateB[i] = (estimateB[i] * 0.88 + initialB[i] * 0.12).clamp(0, 255);
    }
  }

  final output = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      if (sumW[index] <= 1e-3) {
        final filled = _denoisedAt(denoised, x, y);
        output.setPixelRgb(x, y, filled.r.round(), filled.g.round(), filled.b.round());
      } else {
        output.setPixelRgb(
          x,
          y,
          estimateR[index].round().clamp(0, 255),
          estimateG[index].round().clamp(0, 255),
          estimateB[index].round().clamp(0, 255),
        );
      }
    }
  }

  var residual = 0.0;
  var residualCount = 0;
  for (final frame in frames) {
    final image = await imageForFrame(frame: frame, reference: reference, referencePath: referencePath);
    if (image == null) {
      continue;
    }
    final scale = image.maxChannelValue == 0 ? 1.0 : image.maxChannelValue.toDouble();
    final gain = identical(image, reference) ? 1.0 : _estimateGain(reference, image, frame.transform);
    for (var y = 0; y < image.height; y += 2) {
      for (var x = 0; x < image.width; x += 2) {
        final pixel = image.getPixel(x, y);
        final predicted = _sampleEstimate(
          estimateR,
          estimateG,
          estimateB,
          width,
          height,
          (x + frame.transform.dx) * _scale,
          (y + frame.transform.dy) * _scale,
        );
        if (predicted == null) {
          continue;
        }
        residual += (pixel.r * 255.0 / scale * gain - predicted.r).abs();
        residual += (pixel.g * 255.0 / scale * gain - predicted.g).abs();
        residual += (pixel.b * 255.0 / scale * gain - predicted.b).abs();
        residualCount += 3;
      }
    }
  }

  return SuperResolutionOutput(
    image: output,
    reprojectionError: residualCount == 0 ? 0 : residual / residualCount,
    coverage: coverage,
  );
}

/// The reference frame is passed already decoded so it is not read twice.
Future<img.Image?> imageForFrame({
  required FusionFrame frame,
  required img.Image reference,
  required String referencePath,
}) {
  if (frame.path == referencePath) {
    return Future<img.Image?>.value(reference);
  }
  return decodeOriented(frame.path);
}

int _frameWeight(double mae) => (1000 / (0.02 + mae)).round().clamp(1, 10000);

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final double r;
  final double g;
  final double b;
}

bool _far(int red, int green, int blue, _Rgb basis) {
  return (red - basis.r).abs() > _outlierDelta ||
      (green - basis.g).abs() > _outlierDelta ||
      (blue - basis.b).abs() > _outlierDelta;
}

_Rgb? _read(img.Image image, PlaneTransform transform, int x, int y, double scale) {
  if (transform.angleDegrees.abs() < 1e-8 &&
      (transform.dx - transform.dx.round()).abs() < 0.02 &&
      (transform.dy - transform.dy.round()).abs() < 0.02) {
    final sx = x - transform.dx.round();
    final sy = y - transform.dy.round();
    if (sx < 0 || sy < 0 || sx >= image.width || sy >= image.height) {
      return null;
    }
    final pixel = image.getPixel(sx, sy);
    return _Rgb(pixel.r * 255.0 / scale, pixel.g * 255.0 / scale, pixel.b * 255.0 / scale);
  }
  final (sx, sy) = transform.sourceAt(x.toDouble(), y.toDouble(), image.width, image.height);
  return _sampleRgb(image, sx, sy, scale);
}

_Rgb? _sampleRgb(img.Image image, double x, double y, double scale) {
  if (x < 0 || y < 0 || x > image.width - 1 || y > image.height - 1) {
    return null;
  }
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, image.width - 1);
  final y1 = math.min(y0 + 1, image.height - 1);
  final tx = x - x0;
  final ty = y - y0;
  _Rgb at(int px, int py) {
    final pixel = image.getPixel(px, py);
    return _Rgb(pixel.r * 255.0 / scale, pixel.g * 255.0 / scale, pixel.b * 255.0 / scale);
  }

  final a = at(x0, y0);
  final b = at(x1, y0);
  final c = at(x0, y1);
  final d = at(x1, y1);
  double mix(double p, double q, double r, double s) {
    return p * (1 - tx) * (1 - ty) + q * tx * (1 - ty) + r * (1 - tx) * ty + s * tx * ty;
  }

  return _Rgb(mix(a.r, b.r, c.r, d.r), mix(a.g, b.g, c.g, d.g), mix(a.b, b.b, c.b, d.b));
}

double _estimateGain(img.Image reference, img.Image source, PlaneTransform transform) {
  final ratios = <double>[];
  final stride = math.max(1, reference.width ~/ 24);
  final referenceScale = reference.maxChannelValue == 0 ? 1.0 : reference.maxChannelValue.toDouble();
  final sourceScale = source.maxChannelValue == 0 ? 1.0 : source.maxChannelValue.toDouble();
  for (var y = 0; y < reference.height; y += stride) {
    for (var x = 0; x < reference.width; x += stride) {
      final basis = _read(reference, const PlaneTransform(), x, y, referenceScale);
      final sample = _read(source, transform, x, y, sourceScale);
      if (basis == null || sample == null) {
        continue;
      }
      final baseLuma = 0.2126 * basis.r + 0.7152 * basis.g + 0.0722 * basis.b;
      final sampleLuma = 0.2126 * sample.r + 0.7152 * sample.g + 0.0722 * sample.b;
      if (baseLuma < 20 || baseLuma > 235 || sampleLuma < 12) {
        continue;
      }
      ratios.add(baseLuma / sampleLuma);
    }
  }
  if (ratios.length < 12) {
    return 1;
  }
  ratios.sort();
  return ratios[ratios.length ~/ 2].clamp(0.75, 1.35);
}

void _splat(
  Float32List red,
  Float32List green,
  Float32List blue,
  Float32List? weights,
  int width,
  int height,
  double x,
  double y,
  double redValue,
  double greenValue,
  double blueValue,
  double weight,
) {
  if (x < 0 || y < 0 || x > width - 1 || y > height - 1) {
    return;
  }
  final x0 = x.floor();
  final y0 = y.floor();
  final tx = x - x0;
  final ty = y - y0;
  void add(int px, int py, double share) {
    if (share <= 0 || px < 0 || py < 0 || px >= width || py >= height) {
      return;
    }
    final index = py * width + px;
    red[index] += redValue * share * weight;
    green[index] += greenValue * share * weight;
    blue[index] += blueValue * share * weight;
    final coverage = weights;
    if (coverage != null) {
      coverage[index] += share * weight;
    }
  }

  add(x0, y0, (1 - tx) * (1 - ty));
  add(x0 + 1, y0, tx * (1 - ty));
  add(x0, y0 + 1, (1 - tx) * ty);
  add(x0 + 1, y0 + 1, tx * ty);
}

_Rgb? _sampleEstimate(
  Float32List red,
  Float32List green,
  Float32List blue,
  int width,
  int height,
  double x,
  double y,
) {
  if (x < 0 || y < 0 || x > width - 1 || y > height - 1) {
    return null;
  }
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, width - 1);
  final y1 = math.min(y0 + 1, height - 1);
  final tx = x - x0;
  final ty = y - y0;
  double mix(Float32List plane) {
    final a = plane[y0 * width + x0];
    final b = plane[y0 * width + x1];
    final c = plane[y1 * width + x0];
    final d = plane[y1 * width + x1];
    return a * (1 - tx) * (1 - ty) + b * tx * (1 - ty) + c * (1 - tx) * ty + d * tx * ty;
  }

  return _Rgb(mix(red), mix(green), mix(blue));
}

_Rgb _denoisedAt(img.Image denoised, int x, int y) {
  final lx = (x / _scale).floor().clamp(0, denoised.width - 1);
  final ly = (y / _scale).floor().clamp(0, denoised.height - 1);
  final pixel = denoised.getPixel(lx, ly);
  final scale = denoised.maxChannelValue == 0 ? 1.0 : denoised.maxChannelValue.toDouble();
  return _Rgb(pixel.r * 255.0 / scale, pixel.g * 255.0 / scale, pixel.b * 255.0 / scale);
}

double highFrequencyMad(img.Image image) {
  final residuals = <double>[];
  final stride = math.max(1, math.min(image.width, image.height) ~/ 64);
  final scale = image.maxChannelValue == 0 ? 1.0 : image.maxChannelValue.toDouble();
  double luma(int x, int y) {
    final pixel = image.getPixel(x, y);
    return (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b) / scale;
  }

  for (var y = 1; y < image.height - 1; y += stride) {
    for (var x = 1; x < image.width - 1; x += stride) {
      final center = luma(x, y);
      final neighbors = 0.25 * (luma(x - 1, y) + luma(x + 1, y) + luma(x, y - 1) + luma(x, y + 1));
      residuals.add((center - neighbors).abs());
    }
  }
  if (residuals.isEmpty) {
    return 0;
  }
  residuals.sort();
  return residuals[residuals.length ~/ 2];
}

double meanAbsoluteDifference(img.Image left, img.Image right) {
  final width = math.min(left.width, right.width);
  final height = math.min(left.height, right.height);
  if (width == 0 || height == 0) {
    return 0;
  }
  final leftScale = left.maxChannelValue == 0 ? 1.0 : left.maxChannelValue.toDouble();
  final rightScale = right.maxChannelValue == 0 ? 1.0 : right.maxChannelValue.toDouble();
  var sum = 0.0;
  var count = 0;
  final stride = math.max(1, math.min(width, height) ~/ 128);
  for (var y = 0; y < height; y += stride) {
    for (var x = 0; x < width; x += stride) {
      final a = left.getPixel(x, y);
      final b = right.getPixel(x, y);
      sum += (a.r * 255.0 / leftScale - b.r * 255.0 / rightScale).abs();
      sum += (a.g * 255.0 / leftScale - b.g * 255.0 / rightScale).abs();
      sum += (a.b * 255.0 / leftScale - b.b * 255.0 / rightScale).abs();
      count += 3;
    }
  }
  return count == 0 ? 0 : sum / count;
}
