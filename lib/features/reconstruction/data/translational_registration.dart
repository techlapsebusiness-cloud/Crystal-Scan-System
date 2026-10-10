import 'dart:math' as math;

import 'package:microscopeapp/features/reconstruction/data/gray_plane.dart';
import 'package:microscopeapp/features/reconstruction/data/plane_transform.dart';

class RegistrationEstimate {
  const RegistrationEstimate({
    required this.transform,
    required this.mae,
    required this.overlap,
    required this.accepted,
    required this.periodicAmbiguity,
    required this.lowTexture,
    required this.confidence,
    this.rejectionReason,
  });

  final PlaneTransform transform;
  final double mae;
  final double overlap;
  final bool accepted;
  final bool periodicAmbiguity;
  final bool lowTexture;
  final double confidence;
  final String? rejectionReason;

  factory RegistrationEstimate.rejected(String reason) {
    return RegistrationEstimate(
      transform: const PlaneTransform(),
      mae: 1,
      overlap: 0,
      accepted: false,
      periodicAmbiguity: false,
      lowTexture: false,
      confidence: 0,
      rejectionReason: reason,
    );
  }
}

/// Intensity registration for a stationary camera and a nearly planar scene.
///
/// The search is translation, plus a small rotation around the center. A
/// homography is not estimated: one global model cannot explain parallax.
RegistrationEstimate estimateTranslation(GrayPlane reference, GrayPlane moving) {
  if (reference.width != moving.width || reference.height != moving.height) {
    return RegistrationEstimate.rejected(
      'The frame size does not match the reference, so it was not stretched to fit.',
    );
  }
  if (reference.width < 8 || reference.height < 8) {
    return RegistrationEstimate.rejected('The frame is too small to align.');
  }

  final referenceTexture = grayStandardDeviation(reference);
  final movingTexture = grayStandardDeviation(moving);
  if (referenceTexture < 0.02 && movingTexture < 0.02) {
    final identity = _difference(reference, moving, 0, 0, 1);
    return RegistrationEstimate(
      transform: const PlaneTransform(),
      mae: identity.mae,
      overlap: identity.overlap,
      accepted: true,
      periodicAmbiguity: false,
      lowTexture: true,
      confidence: 0.25,
    );
  }

  final stride = _strideFor(reference.width, reference.height);
  final zero = _difference(reference, moving, 0, 0, stride);
  if (zero.mae < 0.000001 && zero.overlap > 0.98) {
    final ambiguous = _hasPeriodicAlias(reference, moving, 0, 0, zero.mae, stride);
    return RegistrationEstimate(
      transform: const PlaneTransform(),
      mae: zero.mae,
      overlap: zero.overlap,
      accepted: true,
      periodicAmbiguity: ambiguous,
      lowTexture: false,
      confidence: (1 - zero.mae).clamp(0, 1),
    );
  }

  final referenceLevels = grayPyramid(reference);
  final movingLevels = grayPyramid(moving);
  // Small images are searched at full resolution. Larger images search rotation
  // near 64 pixels so a one- or two-degree rotation is still visible.
  var angleLevel = 0;
  if (reference.width > 96) {
    for (var level = 0; level < referenceLevels.length; level++) {
      final side = math.min(referenceLevels[level].width, referenceLevels[level].height);
      if (side >= 64) {
        angleLevel = level;
      }
    }
  }
  final angles = <double>[0, -1, 1, -2, 2];
  var bestAngle = 0.0;
  var bestCoarseDx = 0;
  var bestCoarseDy = 0;
  var bestCoarseCost = double.infinity;
  var zeroAngleCost = double.infinity;
  final searchRadius = math.min(4, referenceLevels[angleLevel].width ~/ 2);

  for (final angle in angles) {
    final rotated = angle == 0 ? movingLevels[angleLevel] : rotateGray(movingLevels[angleLevel], angle);
    final found = _integerSearch(
      referenceLevels[angleLevel],
      rotated,
      centerX: 0,
      centerY: 0,
      radius: searchRadius,
      stride: 1,
    );
    if (angle == 0) {
      zeroAngleCost = found.cost;
    }
    if (found.cost < bestCoarseCost) {
      bestCoarseCost = found.cost;
      bestCoarseDx = found.dx;
      bestCoarseDy = found.dy;
      bestAngle = angle;
    }
  }

  // Keep a pure translation unless rotation clearly explains the frames better.
  if (bestAngle != 0 && zeroAngleCost - bestCoarseCost < 0.002) {
    final found = _integerSearch(
      referenceLevels[angleLevel],
      movingLevels[angleLevel],
      centerX: 0,
      centerY: 0,
      radius: searchRadius,
      stride: 1,
    );
    bestAngle = 0;
    bestCoarseDx = found.dx;
    bestCoarseDy = found.dy;
  }

  var dx = bestCoarseDx.toDouble();
  var dy = bestCoarseDy.toDouble();
  for (var level = angleLevel - 1; level >= 0; level--) {
    dx *= 2;
    dy *= 2;
    final movingLevel = bestAngle == 0
        ? movingLevels[level]
        : rotateGray(movingLevels[level], bestAngle);
    final found = _integerSearch(
      referenceLevels[level],
      movingLevel,
      centerX: dx.round(),
      centerY: dy.round(),
      radius: 2,
      stride: _strideFor(referenceLevels[level].width, referenceLevels[level].height),
    );
    dx = found.dx.toDouble();
    dy = found.dy.toDouble();
  }

  final refined = _subpixelSearch(
    reference,
    bestAngle == 0 ? moving : rotateGray(moving, bestAngle),
    dx.round(),
    dy.round(),
    stride,
  );
  dx = refined.dx;
  dy = refined.dy;

  final transform = PlaneTransform(dx: dx, dy: dy, angleDegrees: bestAngle);
  final measured = _differenceTransformed(reference, moving, transform, stride);
  final ambiguous = _hasPeriodicAlias(reference, moving, dx, dy, measured.mae, stride);

  if (dx.abs() > reference.width * 0.40 || dy.abs() > reference.height * 0.40) {
    return RegistrationEstimate(
      transform: transform,
      mae: measured.mae,
      overlap: measured.overlap,
      accepted: false,
      periodicAmbiguity: ambiguous,
      lowTexture: false,
      confidence: 0,
      rejectionReason: 'The estimated shift is too large to treat as a small camera motion.',
    );
  }
  if (measured.overlap < 0.70) {
    return RegistrationEstimate(
      transform: transform,
      mae: measured.mae,
      overlap: measured.overlap,
      accepted: false,
      periodicAmbiguity: ambiguous,
      lowTexture: false,
      confidence: 0,
      rejectionReason: 'The aligned overlap covers too little of the reference.',
    );
  }
  if (ambiguous && math.sqrt(dx * dx + dy * dy) > 1.5) {
    return RegistrationEstimate(
      transform: transform,
      mae: measured.mae,
      overlap: measured.overlap,
      accepted: false,
      periodicAmbiguity: true,
      lowTexture: false,
      confidence: 0,
      rejectionReason:
          'Repetitive texture produced more than one plausible shift, so this frame was excluded.',
    );
  }
  if (measured.mae > 0.10) {
    return RegistrationEstimate(
      transform: transform,
      mae: measured.mae,
      overlap: measured.overlap,
      accepted: false,
      periodicAmbiguity: ambiguous,
      lowTexture: false,
      confidence: 0,
      rejectionReason:
          'After alignment the frames still disagree, so the transformation was rejected.',
    );
  }

  return RegistrationEstimate(
    transform: transform,
    mae: measured.mae,
    overlap: measured.overlap,
    accepted: true,
    periodicAmbiguity: ambiguous,
    lowTexture: false,
    confidence: ((1 - measured.mae) * measured.overlap).clamp(0, 1),
  );
}

int _strideFor(int width, int height) {
  final minSide = math.min(width, height);
  if (minSide <= 96) {
    return 1;
  }
  return math.max(1, minSide ~/ 220);
}

class _Score {
  const _Score(this.mae, this.overlap);
  final double mae;
  final double overlap;
}

_Score _difference(GrayPlane reference, GrayPlane moving, double dx, double dy, int stride) {
  var error = 0.0;
  var used = 0;
  var visited = 0;
  final integer = _isInteger(dx) && _isInteger(dy);
  final ix = dx.round();
  final iy = dy.round();
  for (var y = 0; y < reference.height; y += stride) {
    for (var x = 0; x < reference.width; x += stride) {
      visited++;
      final double sample;
      if (integer) {
        final sx = x - ix;
        final sy = y - iy;
        if (sx < 0 || sy < 0 || sx >= moving.width || sy >= moving.height) {
          continue;
        }
        sample = moving.at(sx, sy);
        if (sample.isNaN) {
          continue;
        }
      } else {
        sample = moving.sample(x - dx, y - dy);
        if (sample.isNaN) {
          continue;
        }
      }
      error += (reference.at(x, y) - sample).abs();
      used++;
    }
  }
  if (used == 0 || visited == 0) {
    return const _Score(1, 0);
  }
  return _Score(error / used, used / visited);
}

_Score _differenceTransformed(
  GrayPlane reference,
  GrayPlane moving,
  PlaneTransform transform,
  int stride,
) {
  if (transform.angleDegrees.abs() < 1e-8) {
    return _difference(reference, moving, transform.dx, transform.dy, stride);
  }
  var error = 0.0;
  var used = 0;
  var visited = 0;
  for (var y = 0; y < reference.height; y += stride) {
    for (var x = 0; x < reference.width; x += stride) {
      visited++;
      final (sx, sy) = transform.sourceAt(x.toDouble(), y.toDouble(), moving.width, moving.height);
      final sample = moving.sample(sx, sy);
      if (sample.isNaN) {
        continue;
      }
      error += (reference.at(x, y) - sample).abs();
      used++;
    }
  }
  if (used == 0 || visited == 0) {
    return const _Score(1, 0);
  }
  return _Score(error / used, used / visited);
}

bool _isInteger(double value) => (value - value.round()).abs() < 1e-6;

({int dx, int dy, double cost}) _integerSearch(
  GrayPlane reference,
  GrayPlane moving, {
  required int centerX,
  required int centerY,
  required int radius,
  required int stride,
}) {
  var bestCost = double.infinity;
  var bestDx = centerX;
  var bestDy = centerY;
  var bestDistance = 1 << 30;
  for (var dy = centerY - radius; dy <= centerY + radius; dy++) {
    for (var dx = centerX - radius; dx <= centerX + radius; dx++) {
      final score = _difference(reference, moving, dx.toDouble(), dy.toDouble(), stride);
      final distance = (dx - centerX) * (dx - centerX) + (dy - centerY) * (dy - centerY);
      final clearlyBetter = score.mae < bestCost - 0.004;
      final tiedAndCloser = (score.mae - bestCost).abs() <= 0.004 && distance < bestDistance;
      if (clearlyBetter || tiedAndCloser || bestCost.isInfinite) {
        bestCost = score.mae;
        bestDx = dx;
        bestDy = dy;
        bestDistance = distance;
      }
    }
  }
  return (dx: bestDx, dy: bestDy, cost: bestCost);
}

({double dx, double dy}) _subpixelSearch(
  GrayPlane reference,
  GrayPlane moving,
  int originX,
  int originY,
  int stride,
) {
  var bestDx = originX.toDouble();
  var bestDy = originY.toDouble();
  var best = double.infinity;
  for (var stepY = -4; stepY <= 4; stepY++) {
    for (var stepX = -4; stepX <= 4; stepX++) {
      final dx = originX + stepX * 0.25;
      final dy = originY + stepY * 0.25;
      final score = _difference(reference, moving, dx, dy, stride);
      if (score.mae < best) {
        best = score.mae;
        bestDx = dx;
        bestDy = dy;
      }
    }
  }
  final baseX = bestDx;
  final baseY = bestDy;
  for (var stepY = -4; stepY <= 4; stepY++) {
    for (var stepX = -4; stepX <= 4; stepX++) {
      final dx = baseX + stepX * 0.05;
      final dy = baseY + stepY * 0.05;
      final score = _difference(reference, moving, dx, dy, stride);
      if (score.mae < best) {
        best = score.mae;
        bestDx = dx;
        bestDy = dy;
      }
    }
  }
  return (dx: bestDx, dy: bestDy);
}

bool _hasPeriodicAlias(
  GrayPlane reference,
  GrayPlane moving,
  double dx,
  double dy,
  double bestMae,
  int stride,
) {
  final radius = 12;
  final scanStride = math.max(stride, _strideFor(reference.width, reference.height));
  final originX = dx.round();
  final originY = dy.round();
  for (var offsetY = -radius; offsetY <= radius; offsetY++) {
    for (var offsetX = -radius; offsetX <= radius; offsetX++) {
      if (offsetX * offsetX + offsetY * offsetY < 9) {
        continue;
      }
      final score = _difference(
        reference,
        moving,
        (originX + offsetX).toDouble(),
        (originY + offsetY).toDouble(),
        scanStride,
      );
      if (score.overlap < 0.5) {
        continue;
      }
      if (score.mae <= bestMae + 0.012) {
        return true;
      }
    }
  }
  return false;
}
