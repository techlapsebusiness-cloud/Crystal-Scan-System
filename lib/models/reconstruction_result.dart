import 'package:microscopeapp/core/utils/json_readers.dart';

enum ReconstructionStage {
  notStarted,
  preparing,
  aligning,
  reconstructing,
  saving,
  completed,
  failed,
  unavailable,
}

String reconstructionStageLabel(ReconstructionStage stage) {
  switch (stage) {
    case ReconstructionStage.notStarted:
      return 'Not started';
    case ReconstructionStage.preparing:
      return 'Preparing images';
    case ReconstructionStage.aligning:
      return 'Aligning frames';
    case ReconstructionStage.reconstructing:
      return 'Reconstructing';
    case ReconstructionStage.saving:
      return 'Saving output';
    case ReconstructionStage.completed:
      return 'Completed';
    case ReconstructionStage.failed:
      return 'Failed';
    case ReconstructionStage.unavailable:
      return 'Not implemented';
  }
}

class ReconstructionRequest {
  const ReconstructionRequest({
    required this.sessionId,
    required this.originalImagePaths,
    required this.outputDirectory,
  });

  final String sessionId;

  /// Absolute paths of the original captures. Implementations must not
  /// overwrite these files.
  final List<String> originalImagePaths;
  final String outputDirectory;
}

class ReconstructionResult {
  const ReconstructionResult({
    required this.implemented,
    required this.success,
    required this.stage,
    required this.inputFrameCount,
    required this.framesAccepted,
    required this.framesRejected,
    required this.processingDuration,
    required this.algorithmName,
    required this.algorithmVersion,
    required this.message,
    this.outputFilePath,
    this.outputWidth,
    this.outputHeight,
    this.qualityMetrics = const {},
    this.effectiveResolution,
  });

  factory ReconstructionResult.unavailable({
    required int inputFrameCount,
    required String algorithmName,
    required String algorithmVersion,
    required Duration processingDuration,
  }) {
    return ReconstructionResult(
      implemented: false,
      success: false,
      stage: ReconstructionStage.unavailable,
      inputFrameCount: inputFrameCount,
      framesAccepted: 0,
      framesRejected: 0,
      processingDuration: processingDuration,
      algorithmName: algorithmName,
      algorithmVersion: algorithmVersion,
      message: unavailableReconstructionMessage,
      effectiveResolution: notMeasuredResolution,
    );
  }

  static const String unavailableReconstructionMessage =
      'Reconstruction is not implemented. No enhanced image was created, and the original frames were not modified.';

  static const String notMeasuredResolution =
      'Not measured. Effective resolution is reported only after a validation procedure.';

  final bool implemented;
  final bool success;
  final ReconstructionStage stage;
  final String? outputFilePath;
  final int? outputWidth;
  final int? outputHeight;
  final int inputFrameCount;
  final int framesAccepted;
  final int framesRejected;
  final Duration processingDuration;
  final String algorithmName;
  final String algorithmVersion;
  final Map<String, Object?> qualityMetrics;
  final String message;

  /// Null until a measurement procedure exists. Pixel dimensions of an output
  /// file are not a substitute for this.
  final String? effectiveResolution;

  Map<String, Object?> toJson() {
    return {
      'implemented': implemented,
      'success': success,
      'stage': stage.name,
      'outputFilePath': outputFilePath,
      'outputWidth': outputWidth,
      'outputHeight': outputHeight,
      'inputFrameCount': inputFrameCount,
      'framesAccepted': framesAccepted,
      'framesRejected': framesRejected,
      'processingDurationMilliseconds': processingDuration.inMilliseconds,
      'algorithmName': algorithmName,
      'algorithmVersion': algorithmVersion,
      'qualityMetrics': qualityMetrics,
      'message': message,
      'effectiveResolution': effectiveResolution,
    };
  }

  factory ReconstructionResult.fromJson(Map<String, dynamic> json) {
    final stageName = json['stage'];
    if (stageName is! String) {
      throw const FormatException('Reconstruction stage is missing.');
    }
    return ReconstructionResult(
      implemented: readBool(json['implemented'], 'implemented'),
      success: readBool(json['success'], 'success'),
      stage: _stage(stageName),
      outputFilePath: readOptionalString(json['outputFilePath']),
      outputWidth: readOptionalInt(json['outputWidth']),
      outputHeight: readOptionalInt(json['outputHeight']),
      inputFrameCount: readInt(json['inputFrameCount'], 'inputFrameCount'),
      framesAccepted: readInt(json['framesAccepted'], 'framesAccepted'),
      framesRejected: readInt(json['framesRejected'], 'framesRejected'),
      processingDuration: Duration(
        milliseconds:
            readOptionalInt(json['processingDurationMilliseconds']) ?? 0,
      ),
      algorithmName: readOptionalString(json['algorithmName']) ?? 'unknown',
      algorithmVersion: readOptionalString(json['algorithmVersion']) ?? '0',
      qualityMetrics: readStringMap(json['qualityMetrics']),
      message: readOptionalString(json['message']) ?? '',
      effectiveResolution: readOptionalString(json['effectiveResolution']),
    );
  }

  static ReconstructionStage _stage(String name) {
    for (final stage in ReconstructionStage.values) {
      if (stage.name == name) {
        return stage;
      }
    }
    throw FormatException('Unknown reconstruction stage: $name');
  }
}
