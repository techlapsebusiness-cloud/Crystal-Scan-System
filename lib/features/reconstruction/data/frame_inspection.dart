import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:microscopeapp/features/reconstruction/data/gray_plane.dart';

class FrameInspection {
  const FrameInspection({
    required this.path,
    required this.fileSizeBytes,
    this.imageWidth,
    this.imageHeight,
    this.sharpness,
    this.meanLuminance,
    this.highlightClip,
    this.shadowClip,
    this.texture,
    this.channels,
    this.rejectionReason,
  });

  final String path;
  final int fileSizeBytes;
  final int? imageWidth;
  final int? imageHeight;
  final double? sharpness;
  final double? meanLuminance;
  final double? highlightClip;
  final double? shadowClip;
  final double? texture;
  final int? channels;
  final String? rejectionReason;

  bool get decoded => rejectionReason == null && imageWidth != null && imageHeight != null;
}

/// Decodes one frame, bakes its orientation, and releases the bitmap.
///
/// The original file is only opened for reading.
Future<FrameInspection> inspectFrame(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return FrameInspection(
      path: path,
      fileSizeBytes: 0,
      rejectionReason: 'The file is missing.',
    );
  }
  final length = await file.length();
  if (length <= 0) {
    return FrameInspection(
      path: path,
      fileSizeBytes: 0,
      rejectionReason: 'The file is empty and could not be decoded.',
    );
  }
  final bytes = await file.readAsBytes();
  final decoded = _tryDecode(bytes);
  if (decoded == null) {
    return FrameInspection(
      path: path,
      fileSizeBytes: length,
      rejectionReason: 'The file could not be decoded.',
    );
  }
  final img.Image image;
  try {
    image = img.bakeOrientation(decoded);
  } catch (_) {
    return FrameInspection(
      path: path,
      fileSizeBytes: length,
      rejectionReason: 'The file could not be decoded.',
    );
  }
  if (image.width < 8 || image.height < 8) {
    return FrameInspection(
      path: path,
      fileSizeBytes: length,
      imageWidth: image.width,
      imageHeight: image.height,
      channels: image.numChannels,
      rejectionReason: 'The frame is too small to reconstruct.',
    );
  }
  final plane = GrayPlane.fromImage(image);
  final clips = clipFractions(plane);
  return FrameInspection(
    path: path,
    fileSizeBytes: length,
    imageWidth: image.width,
    imageHeight: image.height,
    sharpness: laplacianVariance(plane),
    meanLuminance: grayMean(plane),
    highlightClip: clips.highlight,
    shadowClip: clips.shadow,
    texture: grayStandardDeviation(plane),
    channels: image.numChannels,
  );
}

Future<img.Image?> decodeOriented(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  final bytes = await file.readAsBytes();
  final decoded = _tryDecode(bytes);
  if (decoded == null) {
    return null;
  }
  return img.bakeOrientation(decoded);
}

img.Image? _tryDecode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}
