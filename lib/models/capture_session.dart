import 'package:microscopeapp/core/utils/json_readers.dart';
import 'package:microscopeapp/models/camera_setup.dart';
import 'package:microscopeapp/models/frame_record.dart';
import 'package:microscopeapp/models/session_status.dart';

const Object _unset = Object();

class CaptureSession {
  CaptureSession({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.requestedFrameCount,
    required this.directoryPath,
    required this.framesDirectoryPath,
    required this.elapsed,
    required List<FrameRecord> frames,
    this.completedAt,
    this.camera,
    this.errorMessage,
    this.schemaVersion = 1,
  }) : frames = List<FrameRecord>.unmodifiable(frames);

  final int schemaVersion;
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final SessionStatus status;
  final int requestedFrameCount;
  final String directoryPath;
  final String framesDirectoryPath;
  final Duration elapsed;
  final CameraSetup? camera;
  final List<FrameRecord> frames;
  final String? errorMessage;

  int get savedCount => frames.where((frame) => frame.success).length;

  int get failedCount => frames.where((frame) => !frame.success).length;

  int get notAttempted {
    final remaining = requestedFrameCount - frames.length;
    return remaining < 0 ? 0 : remaining;
  }

  List<FrameRecord> get savedFrames =>
      frames.where((frame) => frame.success && frame.filePath != null).toList();

  /// Pixel size of the saved JPEGs. This is the captured file size, not an
  /// estimate of optical or reconstructed resolution.
  String? get capturedSizeLabel {
    final labels = <String>{};
    for (final frame in frames) {
      if (!frame.success || frame.width == null || frame.height == null) {
        continue;
      }
      labels.add('${frame.width}×${frame.height}');
    }
    if (labels.isEmpty) {
      return null;
    }
    if (labels.length == 1) {
      return labels.first;
    }
    return 'Varies (${labels.length} sizes)';
  }

  CaptureSession copyWith({
    DateTime? updatedAt,
    Object? completedAt = _unset,
    SessionStatus? status,
    Duration? elapsed,
    Object? camera = _unset,
    List<FrameRecord>? frames,
    Object? errorMessage = _unset,
  }) {
    return CaptureSession(
      schemaVersion: schemaVersion,
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      status: status ?? this.status,
      requestedFrameCount: requestedFrameCount,
      directoryPath: directoryPath,
      framesDirectoryPath: framesDirectoryPath,
      elapsed: elapsed ?? this.elapsed,
      camera: identical(camera, _unset) ? this.camera : camera as CameraSetup?,
      frames: frames ?? this.frames,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'completedAt': completedAt?.toUtc().toIso8601String(),
      'status': status.name,
      'requestedFrameCount': requestedFrameCount,
      'directoryPath': directoryPath,
      'framesDirectoryPath': framesDirectoryPath,
      'elapsedMilliseconds': elapsed.inMilliseconds,
      'camera': camera?.toJson(),
      'frames': frames.map((frame) => frame.toJson()).toList(),
      'errorMessage': errorMessage,
    };
  }

  factory CaptureSession.fromJson(Map<String, dynamic> json) {
    final cameraJson = json['camera'];
    CameraSetup? camera;
    if (cameraJson is Map) {
      camera = CameraSetup.fromJson(Map<String, dynamic>.from(cameraJson));
    } else if (cameraJson != null) {
      throw const FormatException('Camera metadata is not an object.');
    }

    final rawFrames = json['frames'];
    if (rawFrames is! List) {
      throw const FormatException('Session frames are missing.');
    }
    final frames = <FrameRecord>[];
    for (final item in rawFrames) {
      if (item is! Map) {
        throw const FormatException('A frame record is not an object.');
      }
      frames.add(FrameRecord.fromJson(Map<String, dynamic>.from(item)));
    }

    final statusName = json['status'];
    if (statusName is! String) {
      throw const FormatException('Session status is missing.');
    }

    return CaptureSession(
      schemaVersion: readOptionalInt(json['schemaVersion']) ?? 1,
      id: readOptionalString(json['id']) ??
          (throw const FormatException('Session id is missing.')),
      createdAt: readDateTime(json['createdAt'], 'createdAt'),
      updatedAt: json['updatedAt'] == null
          ? readDateTime(json['createdAt'], 'createdAt')
          : readDateTime(json['updatedAt'], 'updatedAt'),
      completedAt: json['completedAt'] == null
          ? null
          : readDateTime(json['completedAt'], 'completedAt'),
      status: sessionStatusFromName(statusName),
      requestedFrameCount: readInt(
        json['requestedFrameCount'],
        'requestedFrameCount',
      ),
      directoryPath: readOptionalString(json['directoryPath']) ?? '',
      framesDirectoryPath: readOptionalString(json['framesDirectoryPath']) ?? '',
      elapsed: Duration(
        milliseconds: readOptionalInt(json['elapsedMilliseconds']) ?? 0,
      ),
      camera: camera,
      frames: frames,
      errorMessage: readOptionalString(json['errorMessage']),
    );
  }
}
