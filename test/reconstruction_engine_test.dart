import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:microscopeapp/features/reconstruction/data/frame_inspection.dart';
import 'package:microscopeapp/features/reconstruction/data/plane_transform.dart';
import 'package:microscopeapp/features/reconstruction/data/reconstruction_engine.dart';
import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/services/image_processing_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crystal_engine_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('identical frames are denoised without a super-resolution claim', () async {
    final scene = _photo(32, 32);
    final paths = [
      await _write(root, 'a.png', scene),
      await _write(root, 'b.png', img.Image.from(scene)),
      await _write(root, 'c.png', img.Image.from(scene)),
    ];
    final before = await _bytes(paths);
    final result = await _run(root, paths);

    expect(result.success, isTrue, reason: result.message);
    expect(result.superResolutionPerformed, isFalse);
    expect(result.outputWidth, 32);
    expect(result.outputHeight, 32);
    expect(result.scaleFactor, 1);
    expect(result.framesAccepted, 3);
    expect(result.framesRejected, 0);
    expect(File(result.denoisedFilePath!).existsSync(), isTrue);
    expect(File('${root.path}/results/super_resolution.png').existsSync(), isFalse);
    expect(_psnr(_decode(result.denoisedFilePath!), scene), greaterThan(40));
    expect(result.effectiveResolution, contains('not independently validated'));
    expect(result.message, contains('Super-resolution was not performed'));
    _expectSameBytes(paths, before);
    final restored = ReconstructionResult.fromJson(result.toJson());
    expect(restored.success, isTrue);
    expect(restored.superResolutionPerformed, isFalse);
  });

  test('recovers a known integer translation', () async {
    final scene = _photo(40, 36);
    final shifted = _shift(scene, -2, 1);
    final paths = [
      await _write(root, 'ref.png', scene),
      await _write(root, 'moved.png', shifted),
    ];
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    final report = result.frameReports.firstWhere((frame) => !frame.reference);
    final moved = report.path.endsWith('moved.png');
    expect(report.accepted, isTrue, reason: '${report.rejectionReason} dx=${report.dx} dy=${report.dy}');
    expect(report.dx, closeTo(moved ? -2 : 2, 0.25));
    expect(report.dy, closeTo(moved ? 1 : -1, 0.25));
    expect(result.superResolutionPerformed, isFalse);
    expect(report.registrationMae!, lessThan(0.05));
  });

  test('reconstructs a 2x grid when subpixel shifts exist', () async {
    final truth = _bandlimited(32, 32);
    final frames = <img.Image>[
      _sampleHighResolution(truth, 0, 0),
      _sampleHighResolution(truth, 0.5, 0),
      _sampleHighResolution(truth, 0, 0.5),
      _sampleHighResolution(truth, 0.5, 0.5),
    ];
    final paths = [
      for (var i = 0; i < frames.length; i++) await _write(root, 'lr_$i.png', frames[i]),
    ];
    final result = await _run(root, paths);

    expect(result.success, isTrue, reason: result.message);
    expect(result.superResolutionPerformed, isTrue, reason: result.message);
    expect(result.outputWidth, 32);
    expect(result.outputHeight, 32);
    expect(result.inputWidth, 16);
    expect(result.inputHeight, 16);
    expect(result.scaleFactor, 2);
    expect(File('${root.path}/results/super_resolution.png').existsSync(), isTrue);
    expect(File(result.denoisedFilePath!).existsSync(), isTrue);
    expect(result.algorithmName, ReconstructionEngine.superResolutionAlgorithm);
    final estimate = _decode(result.superResolutionFilePath!);
    final reference = frames.first;
    final resized = _upsample(reference, 2);
    expect(_bestPsnr(estimate, truth), greaterThan(_bestPsnr(resized, truth) + 1));
    expect(result.qualityMetrics['reprojectionMeanAbsoluteError'], isA<num>());
    expect(result.effectiveResolution, contains('not independently validated'));
    expect(result.effectiveResolution, isNot(contains('12K')));
  });

  test('accepts a one degree rotation', () async {
    final scene = _solid(64, 64, 20, 20, 20);
    _fillRect(scene, 4, 4, 14, 14, 230, 40, 40);
    _fillRect(scene, 50, 48, 60, 58, 40, 220, 40);
    final rotated = _rotate(scene, 2);
    final paths = [
      await _write(root, 'ref.png', scene),
      await _write(root, 'rot.png', rotated),
    ];
    final result = await _run(root, paths);
    final report = result.frameReports.firstWhere((frame) => !frame.reference);
    expect(report.accepted, isTrue, reason: '${report.rejectionReason} mae=${report.registrationMae}');
    expect(report.angleDegrees!.abs(), closeTo(2, 0.75));
    expect(result.superResolutionPerformed, isFalse);
  });

  test('does not reject a smooth low-texture image as blur', () async {
    final ramp = _ramp(32, 32);
    final paths = [
      await _write(root, 'a.png', ramp),
      await _write(root, 'b.png', img.Image.from(ramp)),
    ];
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    expect(result.framesRejected, 0);
    expect(result.superResolutionPerformed, isFalse);
    expect(result.frameReports.every((frame) => frame.lowTexture), isTrue);
  });

  test('does not super-resolve a repetitive texture with an alias', () async {
    final bars = _bars(32, 32);
    final paths = [
      await _write(root, 'a.png', bars),
      await _write(root, 'b.png', img.Image.from(bars)),
    ];
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    expect(result.superResolutionPerformed, isFalse);
    expect(result.frameReports.any((frame) => frame.periodicAmbiguity), isTrue);
    expect(result.message, contains('Super-resolution was not performed'));
  });

  test('rejects a different image size instead of stretching it', () async {
    final scene = _photo(32, 32);
    final paths = [
      await _write(root, 'a.png', scene),
      await _write(root, 'b.png', img.Image.from(scene)),
      await _write(root, 'odd.png', _photo(28, 32)),
    ];
    final before = await _bytes(paths);
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    final odd = result.frameReports.firstWhere((frame) => frame.path.endsWith('odd.png'));
    expect(odd.accepted, isFalse);
    expect(odd.rejectionReason, contains('not stretched'));
    expect(result.outputWidth, 32);
    _expectSameBytes(paths, before);
  });

  test('bakes JPEG orientation before comparing frames', () async {
    final upright = _blocks(16, 24);
    final stored = img.copyRotate(upright, angle: 270);
    stored.exif.imageIfd.orientation = 6;
    final jpegPath = '${root.path}/turned.jpg';
    await File(jpegPath).writeAsBytes(img.encodeJpg(stored, quality: 95));
    final pngPath = await _write(root, 'upright.png', upright);
    final inspected = await inspectFrame(jpegPath);
    expect(inspected.rejectionReason, isNull, reason: inspected.rejectionReason);
    expect(inspected.imageWidth, upright.width);
    expect(inspected.imageHeight, upright.height);

    final result = await _run(root, [pngPath, jpegPath]);
    expect(result.success, isTrue, reason: result.message);
    final jpeg = result.frameReports.firstWhere((frame) => frame.path == jpegPath);
    expect(jpeg.width, 16);
    expect(jpeg.height, 24);
    expect(jpeg.accepted, isTrue, reason: jpeg.rejectionReason);
  });

  test('rejects a blurred frame and an overexposed frame', () async {
    final sharp = _checker(32, 32);
    final paths = [
      await _write(root, 'sharp_a.png', sharp),
      await _write(root, 'sharp_b.png', img.Image.from(sharp)),
      await _write(root, 'blurred.png', _boxBlur(sharp, 3)),
      await _write(root, 'blown.png', _solid(32, 32, 250, 250, 250)),
    ];
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    expect(result.framesAccepted, 2);
    final blurred = result.frameReports.firstWhere((frame) => frame.path.endsWith('blurred.png'));
    final blown = result.frameReports.firstWhere((frame) => frame.path.endsWith('blown.png'));
    expect(blurred.accepted, isFalse);
    expect(blurred.rejectionReason, contains('blur'));
    expect(blown.accepted, isFalse);
    expect(blown.rejectionReason, contains('overexposed'));
  });

  test('reports corrupt and missing files and still uses the valid frames', () async {
    final scene = _photo(24, 24);
    final goodA = await _write(root, 'a.png', scene);
    final goodB = await _write(root, 'b.png', img.Image.from(scene));
    final corrupt = '${root.path}/broken.png';
    await File(corrupt).writeAsBytes([1, 2, 3, 4, 5]);
    final missing = '${root.path}/missing.png';
    final before = await _bytes([goodA, goodB, corrupt]);
    final result = await _run(root, [goodA, goodB, corrupt, missing]);

    expect(result.success, isTrue, reason: result.message);
    expect(result.framesAccepted, 2);
    expect(result.framesRejected, 2);
    expect(
      result.frameReports.firstWhere((frame) => frame.path == corrupt).rejectionReason,
      contains('decoded'),
    );
    expect(
      result.frameReports.firstWhere((frame) => frame.path == missing).rejectionReason,
      contains('missing'),
    );
    _expectSameBytes([goodA, goodB, corrupt], before);
    expect(File(missing).existsSync(), isFalse);
  });

  test('keeps a moving object from ghosting into the background', () async {
    final first = _solid(32, 32, 80, 80, 80);
    final second = img.Image.from(first);
    _fillRect(first, 4, 4, 8, 8, 240, 240, 240);
    _fillRect(second, 20, 20, 24, 24, 240, 240, 240);
    final paths = [
      await _write(root, 'a.png', first),
      await _write(root, 'b.png', second),
    ];
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    final output = _decode(result.denoisedFilePath!);
    final intruder = output.getPixel(22, 22);
    final object = output.getPixel(6, 6);
    expect(intruder.r, lessThan(100));
    expect(object.r, greaterThan(200));
  });

  test('rejects a frame whose overlap is too small', () async {
    final scene = _photo(10, 10);
    final paths = [
      await _write(root, 'a.png', scene),
      await _write(root, 'b.png', img.Image.from(scene)),
      await _write(root, 'partial.png', _shift(scene, 4, 0)),
    ];
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    final partial = result.frameReports.firstWhere((frame) => frame.path.endsWith('partial.png'));
    expect(partial.accepted, isFalse);
    expect(partial.rejectionReason, contains('overlap'));
  });

  test('rejects a frame that cannot be registered', () async {
    final scene = _photo(32, 32);
    final noise = _noise(32, 32, 7);
    final paths = [
      await _write(root, 'a.png', scene),
      await _write(root, 'b.png', img.Image.from(scene)),
      await _write(root, 'noise.png', noise),
    ];
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    final bad = result.frameReports.firstWhere((frame) => frame.path.endsWith('noise.png'));
    expect(bad.accepted, isFalse);
    expect(bad.rejectionReason, isNotNull);
  });

  test('fails an empty session without writing an image', () async {
    final result = await _run(root, const []);
    expect(result.success, isFalse);
    expect(result.outputFilePath, isNull);
    expect(result.message, contains('no frames'));
    expect(File('${root.path}/results/denoised.png').existsSync(), isFalse);
  });

  test('stops when cancellation is requested and writes no image', () async {
    final scene = _photo(24, 24);
    final paths = [
      for (var i = 0; i < 4; i++) await _write(root, 'f_$i.png', img.Image.from(scene)),
    ];
    final cancellation = ReconstructionCancellation();
    final result = await _run(
      root,
      paths,
      cancellation: cancellation,
      onProgress: (progress) {
        if (progress.completed >= 1) {
          cancellation.cancel();
        }
      },
    );
    expect(result.stage, ReconstructionStage.cancelled);
    expect(result.success, isFalse);
    expect(result.outputFilePath, isNull);
    expect(File('${root.path}/results/denoised.png').existsSync(), isFalse);
    expect(File('${root.path}/results/super_resolution.png').existsSync(), isFalse);
  });

  test('reports a blocked results path without touching the originals', () async {
    final scene = _photo(24, 24);
    final paths = [
      await _write(root, 'a.png', scene),
      await _write(root, 'b.png', img.Image.from(scene)),
    ];
    final before = await _bytes(paths);
    final blocked = File('${root.path}/results');
    await blocked.writeAsBytes([9, 9, 9]);
    final result = await _run(root, paths);
    expect(result.success, isFalse);
    expect(result.outputFilePath, isNull);
    expect(result.message.toLowerCase(), contains('results'));
    expect(await blocked.readAsBytes(), [9, 9, 9]);
    _expectSameBytes(paths, before);
  });

  test('fails when every frame is corrupt', () async {
    final first = '${root.path}/a.png';
    final second = '${root.path}/b.png';
    await File(first).writeAsBytes([0, 1, 2]);
    await File(second).writeAsBytes([3, 4]);
    final before = await _bytes([first, second]);
    final result = await _run(root, [first, second]);
    expect(result.success, isFalse);
    expect(result.framesAccepted, 0);
    expect(result.outputFilePath, isNull);
    expect(File('${root.path}/results/denoised.png').existsSync(), isFalse);
    expect(result.message, contains('Recapture'));
    _expectSameBytes([first, second], before);
  });

  test('reduces independent noise and keeps a step edge', () async {
    final clean = _edge(32, 32);
    final paths = <String>[];
    for (var i = 0; i < 6; i++) {
      paths.add(await _write(root, 'n_$i.png', _addNoise(clean, _Lcg(1000 + i), 14)));
    }
    final noisy = _decode(paths.first);
    final result = await _run(root, paths);
    expect(result.success, isTrue, reason: result.message);
    expect(result.superResolutionPerformed, isFalse);
    final output = _decode(result.denoisedFilePath!);
    expect(_highFrequencyEnergy(output), lessThan(_highFrequencyEnergy(noisy)));
    expect(_edgeContrast(output), greaterThan(140));
    expect(_psnr(output, clean), greaterThan(_psnr(noisy, clean)));
  });

  test('stays at native resolution when the 2x grid exceeds the pixel budget', () async {
    final scene = _photo(20, 20);
    final paths = [
      await _write(root, 'a.png', scene),
      await _write(root, 'b.png', img.Image.from(scene)),
    ];
    final result = await _run(
      root,
      paths,
      options: const ReconstructionOptions(maxSuperResolutionPixels: 10),
    );
    expect(result.success, isTrue, reason: result.message);
    expect(result.superResolutionPerformed, isFalse);
    expect(result.outputWidth, 20);
    expect(result.outputHeight, 20);
    expect(result.message, contains('working limit'));
    expect(File('${root.path}/results/super_resolution.png').existsSync(), isFalse);
  });

  test('reconstructs different subjects without a category label', () async {
    final subjects = <String, img.Image>{
      'traces': _traces(28, 28),
      'texture': _bandlimited(28, 28),
      'object': _photo(28, 28),
    };
    for (final entry in subjects.entries) {
      final paths = [
        await _write(root, '${entry.key}_a.png', entry.value),
        await _write(root, '${entry.key}_b.png', _shift(entry.value, 1, -1)),
      ];
      final result = await _run(root, paths);
      expect(result.success, isTrue, reason: '${entry.key}: ${result.message}');
      expect(result.outputWidth, entry.value.width);
      expect(result.strategy, isNot(contains('pcb')));
    }
  });

  test('the background service returns a saved denoised file', () async {
    final scene = _photo(16, 16);
    final paths = [
      await _write(root, 'a.png', scene),
      await _write(root, 'b.png', img.Image.from(scene)),
    ];
    final stages = <ReconstructionStage>[];
    final result = await ImageProcessingService.local().reconstruct(
      ReconstructionRequest(
        sessionId: 'session_20261010_200301_482_ab12',
        originalImagePaths: paths,
        outputDirectory: '${root.path}/results',
      ),
      onProgress: (progress) => stages.add(progress.stage),
    );
    expect(result.success, isTrue, reason: result.message);
    expect(result.superResolutionPerformed, isFalse);
    expect(File(result.outputFilePath!).lengthSync(), greaterThan(0));
    expect(stages, contains(ReconstructionStage.analyzing));
    expect(stages, contains(ReconstructionStage.denoising));
    expect(stages, contains(ReconstructionStage.completed));
  });
}

Future<ReconstructionResult> _run(
  Directory root,
  List<String> paths, {
  ReconstructionOptions options = const ReconstructionOptions(),
  ReconstructionCancellation? cancellation,
  void Function(ReconstructionProgress progress)? onProgress,
}) {
  return ReconstructionEngine().run(
    ReconstructionRequest(
      sessionId: 'session_20261010_200301_482_ab12',
      originalImagePaths: paths,
      outputDirectory: '${root.path}/results',
      options: options,
    ),
    cancellation: cancellation,
    onProgress: onProgress,
  );
}

Future<String> _write(Directory root, String name, img.Image image) async {
  final path = '${root.path}/$name';
  await File(path).writeAsBytes(img.encodePng(image));
  return path;
}

Future<Map<String, List<int>>> _bytes(List<String> paths) async {
  return {for (final path in paths) path: await File(path).readAsBytes()};
}

void _expectSameBytes(List<String> paths, Map<String, List<int>> before) {
  for (final path in paths) {
    expect(File(path).readAsBytesSync(), before[path], reason: path);
  }
}

img.Image _decode(String path) {
  final decoded = img.decodePng(File(path).readAsBytesSync());
  expect(decoded, isNotNull, reason: path);
  return decoded!;
}

img.Image _solid(int width, int height, int red, int green, int blue) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  _fillRect(image, 0, 0, width, height, red, green, blue);
  return image;
}

void _fillRect(img.Image image, int x0, int y0, int x1, int y1, int red, int green, int blue) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      image.setPixelRgb(x, y, red, green, blue);
    }
  }
}

img.Image _photo(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final dx = x - width * 0.35;
      final dy = y - height * 0.42;
      final blob = math.exp(-(dx * dx + dy * dy) / 50) * 130;
      final red = (50 + 90 * (0.5 + 0.5 * math.sin(x / 3.2)) + blob).round().clamp(0, 255);
      final green = (40 + 70 * (0.5 + 0.5 * math.sin(y / 2.7)) + blob * 0.3).round().clamp(0, 255);
      final blue = (30 + (x * 4 + y * 2) % 70).clamp(0, 255);
      image.setPixelRgb(x, y, red, green, blue);
    }
  }
  return image;
}

img.Image _bandlimited(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final wave = 118 +
          62 * math.sin(x * 0.45) +
          48 * math.sin(y * 0.38) +
          24 * math.sin((x + y) * 0.22);
      final value = wave.round().clamp(16, 240);
      image.setPixelRgb(x, y, value, (value * 0.7).round(), 180 - value ~/ 3);
    }
  }
  return image;
}

img.Image _traces(int width, int height) {
  final image = _solid(width, height, 18, 55, 32);
  for (var x = 0; x < width; x++) {
    image.setPixelRgb(x, height ~/ 4, 190, 140, 60);
    if (x.isEven) {
      image.setPixelRgb(x, height ~/ 2, 210, 170, 80);
    }
  }
  for (var y = 0; y < height; y++) {
    image.setPixelRgb(width ~/ 3, y, 170, 120, 50);
  }
  return image;
}

img.Image _checker(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final on = ((x ~/ 2) + (y ~/ 2)).isEven;
      image.setPixelRgb(x, y, on ? 230 : 20, on ? 210 : 30, on ? 80 : 40);
    }
  }
  return image;
}

img.Image _bars(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final on = ((x ~/ 4) % 2) == 0;
      image.setPixelRgb(x, y, on ? 210 : 25, on ? 210 : 25, on ? 210 : 25);
    }
  }
  return image;
}

img.Image _ramp(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = 120 + (x * 6 ~/ width);
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

img.Image _edge(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = x < width ~/ 2 ? 36 : 214;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

img.Image _noise(int width, int height, int seed) {
  final random = _Lcg(seed);
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, random.next() % 256, random.next() % 256, random.next() % 256);
    }
  }
  return image;
}

img.Image _blocks(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final band = (x ~/ 8) + (y ~/ 8) * 3;
      final red = 30 + (band % 5) * 40;
      final green = 20 + ((band + 2) % 4) * 50;
      image.setPixelRgb(x, y, red, green, 220 - red.clamp(0, 180));
    }
  }
  return image;
}

img.Image _boxBlur(img.Image source, int radius) {
  final image = img.Image(width: source.width, height: source.height, numChannels: 3);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var count = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          final sx = x + dx;
          final sy = y + dy;
          if (sx < 0 || sy < 0 || sx >= source.width || sy >= source.height) {
            continue;
          }
          final pixel = source.getPixel(sx, sy);
          red += pixel.r;
          green += pixel.g;
          blue += pixel.b;
          count++;
        }
      }
      image.setPixelRgb(x, y, (red / count).round(), (green / count).round(), (blue / count).round());
    }
  }
  return image;
}

img.Image _shift(img.Image source, double dx, double dy) {
  final image = img.Image(width: source.width, height: source.height, numChannels: 3);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final sx = (x + dx).clamp(0, source.width - 1).toDouble();
      final sy = (y + dy).clamp(0, source.height - 1).toDouble();
      final color = _bilinear(source, sx, sy)!;
      image.setPixelRgb(x, y, color.$1, color.$2, color.$3);
    }
  }
  return image;
}

img.Image _rotate(img.Image source, double degrees) {
  final transform = PlaneTransform(angleDegrees: degrees);
  final image = img.Image.from(source);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final (sx, sy) = transform.sourceAt(x.toDouble(), y.toDouble(), source.width, source.height);
      final color = _bilinear(source, sx, sy);
      if (color != null) {
        image.setPixelRgb(x, y, color.$1, color.$2, color.$3);
      }
    }
  }
  return image;
}

img.Image _sampleHighResolution(img.Image source, double dx, double dy) {
  const scale = 2;
  final width = source.width ~/ scale;
  final height = source.height ~/ scale;
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = _bilinear(source, (x + dx) * scale, (y + dy) * scale);
      image.setPixelRgb(x, y, color?.$1 ?? 0, color?.$2 ?? 0, color?.$3 ?? 0);
    }
  }
  return image;
}

img.Image _upsample(img.Image source, int scale) {
  final image = img.Image(width: source.width * scale, height: source.height * scale, numChannels: 3);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final color = _bilinear(source, x / scale, y / scale);
      image.setPixelRgb(x, y, color?.$1 ?? 0, color?.$2 ?? 0, color?.$3 ?? 0);
    }
  }
  return image;
}

(int, int, int)? _bilinear(img.Image image, double x, double y) {
  if (x < 0 || y < 0 || x > image.width - 1 || y > image.height - 1) {
    return null;
  }
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, image.width - 1);
  final y1 = math.min(y0 + 1, image.height - 1);
  final tx = x - x0;
  final ty = y - y0;
  (double, double, double) at(int px, int py) {
    final pixel = image.getPixel(px, py);
    return (pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble());
  }

  final a = at(x0, y0);
  final b = at(x1, y0);
  final c = at(x0, y1);
  final d = at(x1, y1);
  double mix(double p, double q, double r, double s) {
    return p * (1 - tx) * (1 - ty) + q * tx * (1 - ty) + r * (1 - tx) * ty + s * tx * ty;
  }

  return (
    mix(a.$1, b.$1, c.$1, d.$1).round(),
    mix(a.$2, b.$2, c.$2, d.$2).round(),
    mix(a.$3, b.$3, c.$3, d.$3).round(),
  );
}

img.Image _addNoise(img.Image source, _Lcg random, int amplitude) {
  final image = img.Image.from(source);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      image.setPixelRgb(
        x,
        y,
        (pixel.r + random.signed(amplitude)).round().clamp(0, 255),
        (pixel.g + random.signed(amplitude)).round().clamp(0, 255),
        (pixel.b + random.signed(amplitude)).round().clamp(0, 255),
      );
    }
  }
  return image;
}

double _psnr(img.Image estimate, img.Image truth, {int inset = 2, int shiftX = 0, int shiftY = 0}) {
  var error = 0.0;
  var count = 0;
  for (var y = inset; y < estimate.height - inset; y++) {
    for (var x = inset; x < estimate.width - inset; x++) {
      final tx = x + shiftX;
      final ty = y + shiftY;
      if (tx < 0 || ty < 0 || tx >= truth.width || ty >= truth.height) {
        continue;
      }
      final a = estimate.getPixel(x, y);
      final b = truth.getPixel(tx, ty);
      error += math.pow(a.r - b.r, 2) + math.pow(a.g - b.g, 2) + math.pow(a.b - b.b, 2);
      count += 3;
    }
  }
  if (count == 0) {
    return 0;
  }
  final mse = error / count;
  if (mse < 1e-8) {
    return 99;
  }
  return 10 * math.log(255 * 255 / mse) / math.ln10;
}

double _bestPsnr(img.Image estimate, img.Image truth) {
  var best = 0.0;
  for (var shiftY = -2; shiftY <= 2; shiftY++) {
    for (var shiftX = -2; shiftX <= 2; shiftX++) {
      best = math.max(best, _psnr(estimate, truth, shiftX: shiftX, shiftY: shiftY));
    }
  }
  return best;
}

double _highFrequencyEnergy(img.Image image) {
  var sum = 0.0;
  var count = 0;
  for (var y = 1; y < image.height - 1; y++) {
    for (var x = 1; x < image.width - 1; x++) {
      final center = image.getPixel(x, y).r;
      final neighbors =
          (image.getPixel(x - 1, y).r +
              image.getPixel(x + 1, y).r +
              image.getPixel(x, y - 1).r +
              image.getPixel(x, y + 1).r) /
          4;
      sum += (center - neighbors).abs();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

double _edgeContrast(img.Image image) {
  var left = 0.0;
  var right = 0.0;
  var count = 0;
  for (var y = 2; y < image.height - 2; y++) {
    left += image.getPixel(4, y).r;
    right += image.getPixel(image.width - 5, y).r;
    count++;
  }
  return count == 0 ? 0 : (right - left) / count;
}

class _Lcg {
  _Lcg(this.state);

  int state;

  int next() {
    state = (1664525 * state + 1013904223) & 0x7fffffff;
    return state;
  }

  int signed(int amplitude) => (next() % (2 * amplitude + 1)) - amplitude;
}
