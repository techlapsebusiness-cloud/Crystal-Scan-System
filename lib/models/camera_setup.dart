import 'package:microscopeapp/core/utils/json_readers.dart';

/// Controls actually applied at the start of a capture, plus what the device
/// did not expose. Null measurements were not available and are not invented.
class CameraSetup {
  const CameraSetup({
    required this.cameraName,
    required this.lensDirection,
    required this.lensType,
    required this.sensorOrientation,
    required this.requestedResolution,
    required this.flashDisabled,
    required this.focusLocked,
    required this.exposureLocked,
    required this.refocusBetweenFrames,
    this.previewWidth,
    this.previewHeight,
    this.zoomLevel,
    this.focusMode,
    this.exposureMode,
    this.flashMode,
    this.minExposureOffset,
    this.maxExposureOffset,
    this.exposureOffsetStep,
    this.limitations = const [],
  });

  final String cameraName;
  final String lensDirection;
  final String lensType;
  final int sensorOrientation;

  /// Plugin preset that was requested, such as `max`. The device chooses the
  /// exact pixel size; frame records store the JPEG dimensions.
  final String requestedResolution;
  final int? previewWidth;
  final int? previewHeight;
  final double? zoomLevel;
  final String? focusMode;
  final String? exposureMode;
  final String? flashMode;
  final bool flashDisabled;
  final bool focusLocked;
  final bool exposureLocked;

  /// Crystal Scan does not autofocus between frames in this version.
  final bool refocusBetweenFrames;
  final double? minExposureOffset;
  final double? maxExposureOffset;
  final double? exposureOffsetStep;
  final List<String> limitations;

  String get lockSummary {
    final flash = flashDisabled ? 'Flash off' : 'Flash not disabled';
    final focus = focusLocked ? 'Focus locked' : 'Focus not locked';
    final exposure = exposureLocked ? 'Exposure locked' : 'Exposure not locked';
    return '$flash · $focus · $exposure';
  }

  Map<String, Object?> toJson() {
    return {
      'cameraName': cameraName,
      'lensDirection': lensDirection,
      'lensType': lensType,
      'sensorOrientation': sensorOrientation,
      'requestedResolution': requestedResolution,
      'previewWidth': previewWidth,
      'previewHeight': previewHeight,
      'zoomLevel': zoomLevel,
      'focusMode': focusMode,
      'exposureMode': exposureMode,
      'flashMode': flashMode,
      'flashDisabled': flashDisabled,
      'focusLocked': focusLocked,
      'exposureLocked': exposureLocked,
      'refocusBetweenFrames': refocusBetweenFrames,
      'minExposureOffset': minExposureOffset,
      'maxExposureOffset': maxExposureOffset,
      'exposureOffsetStep': exposureOffsetStep,
      'limitations': limitations,
    };
  }

  factory CameraSetup.fromJson(Map<String, dynamic> json) {
    return CameraSetup(
      cameraName: readOptionalString(json['cameraName']) ?? 'Unknown camera',
      lensDirection: readOptionalString(json['lensDirection']) ?? 'unknown',
      lensType: readOptionalString(json['lensType']) ?? 'unknown',
      sensorOrientation: readOptionalInt(json['sensorOrientation']) ?? 0,
      requestedResolution:
          readOptionalString(json['requestedResolution']) ?? 'unrecorded',
      previewWidth: readOptionalInt(json['previewWidth']),
      previewHeight: readOptionalInt(json['previewHeight']),
      zoomLevel: readOptionalDouble(json['zoomLevel']),
      focusMode: readOptionalString(json['focusMode']),
      exposureMode: readOptionalString(json['exposureMode']),
      flashMode: readOptionalString(json['flashMode']),
      flashDisabled: json['flashDisabled'] == true,
      focusLocked: json['focusLocked'] == true,
      exposureLocked: json['exposureLocked'] == true,
      refocusBetweenFrames: json['refocusBetweenFrames'] == true,
      minExposureOffset: readOptionalDouble(json['minExposureOffset']),
      maxExposureOffset: readOptionalDouble(json['maxExposureOffset']),
      exposureOffsetStep: readOptionalDouble(json['exposureOffsetStep']),
      limitations: readStringList(json['limitations']),
    );
  }
}
