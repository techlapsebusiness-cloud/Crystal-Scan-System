import 'package:microscopeapp/core/utils/frame_naming.dart';
import 'package:microscopeapp/core/utils/json_readers.dart';

/// One attempted frame. A failed attempt is kept in the session record even
/// when no image file was saved.
class FrameRecord {
  const FrameRecord({
    required this.frameNumber,
    required this.fileName,
    required this.success,
    required this.capturedAt,
    this.filePath,
    this.fileSizeBytes,
    this.width,
    this.height,
    this.error,
    this.focusMode,
    this.exposureMode,
    this.flashMode,
    this.exposureOffset,
  });

  factory FrameRecord.failure({
    required int frameNumber,
    required DateTime capturedAt,
    required String error,
    String? fileName,
    String? filePath,
    int? fileSizeBytes,
    String? focusMode,
    String? exposureMode,
    String? flashMode,
    double? exposureOffset,
  }) {
    return FrameRecord(
      frameNumber: frameNumber,
      fileName: fileName ?? frameFileName(frameNumber),
      success: false,
      capturedAt: capturedAt,
      error: error,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      focusMode: focusMode,
      exposureMode: exposureMode,
      flashMode: flashMode,
      exposureOffset: exposureOffset,
    );
  }

  final int frameNumber;
  final String fileName;
  final String? filePath;
  final int? fileSizeBytes;
  final int? width;
  final int? height;
  final bool success;
  final String? error;
  final DateTime capturedAt;

  /// Values read back from the camera after the shutter, when the plugin
  /// exposes them. Null means the device or plugin did not provide the value.
  final String? focusMode;
  final String? exposureMode;
  final String? flashMode;
  final double? exposureOffset;

  Map<String, Object?> toJson() {
    return {
      'frameNumber': frameNumber,
      'fileName': fileName,
      'filePath': filePath,
      'fileSizeBytes': fileSizeBytes,
      'width': width,
      'height': height,
      'success': success,
      'error': error,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'focusMode': focusMode,
      'exposureMode': exposureMode,
      'flashMode': flashMode,
      'exposureOffset': exposureOffset,
    };
  }

  factory FrameRecord.fromJson(Map<String, dynamic> json) {
    final frameNumber = readInt(json['frameNumber'], 'frameNumber');
    return FrameRecord(
      frameNumber: frameNumber,
      fileName: readOptionalString(json['fileName']) ?? frameFileName(frameNumber),
      filePath: readOptionalString(json['filePath']),
      fileSizeBytes: readOptionalInt(json['fileSizeBytes']),
      width: readOptionalInt(json['width']),
      height: readOptionalInt(json['height']),
      success: readBool(json['success'], 'success'),
      error: readOptionalString(json['error']),
      capturedAt: readDateTime(json['capturedAt'], 'capturedAt'),
      focusMode: readOptionalString(json['focusMode']),
      exposureMode: readOptionalString(json['exposureMode']),
      flashMode: readOptionalString(json['flashMode']),
      exposureOffset: readOptionalDouble(json['exposureOffset']),
    );
  }
}
