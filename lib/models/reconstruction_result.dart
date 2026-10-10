import 'package:microscopeapp/core/utils/json_readers.dart';

enum ReconstructionStage {
  notStarted,
  preparing,
  analyzing,
  selectingReference,
  estimatingMotion,
  aligning,
  rejecting,
  denoising,
  superResolving,
  reconstructing,
  saving,
  completed,
  failed,
  cancelled,
  unavailable,
}

String reconstructionStageLabel(ReconstructionStage stage) {
  switch (stage) {
    case ReconstructionStage.notStarted:
      return 'Not started';
    case ReconstructionStage.preparing:
      return 'Preparing images';
    case ReconstructionStage.analyzing:
      return 'Analyzing image quality';
    case ReconstructionStage.selectingReference:
      return 'Selecting a reference';
    case ReconstructionStage.estimatingMotion:
      return 'Estimating motion';
    case ReconstructionStage.aligning:
      return 'Aligning frames';
    case ReconstructionStage.rejecting:
      return 'Rejecting unreliable frames';
    case ReconstructionStage.denoising:
      return 'Denoising';
    case ReconstructionStage.superResolving:
      return 'Super-resolving';
    case ReconstructionStage.reconstructing:
      return 'Reconstructing';
    case ReconstructionStage.saving:
      return 'Saving output';
    case ReconstructionStage.completed:
      return 'Completed';
    case ReconstructionStage.failed:
      return 'Failed';
    case ReconstructionStage.cancelled:
      return 'Cancelled';
    case ReconstructionStage.unavailable:
      return 'Not implemented';
  }
}

/// Knobs for a reconstruction run. Defaults keep the pipeline automatic.
class ReconstructionOptions {
  const ReconstructionOptions({
    this.allowSuperResolution = true,
    this.rejectOutliers = true,
    this.maxSuperResolutionPixels = 4000000,
  });

  final bool allowSuperResolution;
  final bool rejectOutliers;

  /// Output pixel budget for a 2× reconstruction. Larger results stay at the
  /// native sampling grid instead of being resized to fit.
  final int maxSuperResolutionPixels;

  Map<String, Object?> toJson() {
    return {
      'allowSuperResolution': allowSuperResolution,
      'rejectOutliers': rejectOutliers,
      'maxSuperResolutionPixels': maxSuperResolutionPixels,
    };
  }

  factory ReconstructionOptions.fromJson(Map<String, dynamic> json) {
    return ReconstructionOptions(
      allowSuperResolution: readBoolOr(json['allowSuperResolution'], true),
      rejectOutliers: readBoolOr(json['rejectOutliers'], true),
      maxSuperResolutionPixels:
          readOptionalInt(json['maxSuperResolutionPixels']) ?? 4000000,
    );
  }
}

class ReconstructionRequest {
  const ReconstructionRequest({
    required this.sessionId,
    required this.originalImagePaths,
    required this.outputDirectory,
    this.options = const ReconstructionOptions(),
  });

  final String sessionId;

  /// Absolute paths of the original captures. Implementations must not
  /// overwrite these files.
  final List<String> originalImagePaths;
  final String outputDirectory;
  final ReconstructionOptions options;

  Map<String, Object?> toJson() {
    return {
      'sessionId': sessionId,
      'originalImagePaths': originalImagePaths,
      'outputDirectory': outputDirectory,
      'options': options.toJson(),
    };
  }

  factory ReconstructionRequest.fromJson(Map<String, dynamic> json) {
    final paths = json['originalImagePaths'];
    final options = json['options'];
    return ReconstructionRequest(
      sessionId: readOptionalString(json['sessionId']) ?? '',
      originalImagePaths: paths is List ? [for (final path in paths) path.toString()] : const [],
      outputDirectory: readOptionalString(json['outputDirectory']) ?? '',
      options: options is Map
          ? ReconstructionOptions.fromJson(Map<String, dynamic>.from(options))
          : const ReconstructionOptions(),
    );
  }
}

class ReconstructionProgress {
  const ReconstructionProgress({
    required this.stage,
    required this.completed,
    required this.total,
    required this.framesAccepted,
    required this.framesRejected,
    required this.detail,
  });

  final ReconstructionStage stage;
  final int completed;
  final int total;
  final int framesAccepted;
  final int framesRejected;
  final String detail;

  Map<String, Object?> toJson() {
    return {
      'stage': stage.name,
      'completed': completed,
      'total': total,
      'framesAccepted': framesAccepted,
      'framesRejected': framesRejected,
      'detail': detail,
    };
  }
}

/// Cooperative cancel flag. The UI calls [cancel]; the worker polls [isCancelled].
class ReconstructionCancellation {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  set onCancel(void Function() listener) {
    _onCancel = listener;
    if (_cancelled) {
      listener();
    }
  }

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _onCancel?.call();
  }
}

class FrameReconstructionReport {
  const FrameReconstructionReport({
    required this.path,
    required this.accepted,
    this.rejectionReason,
    this.width,
    this.height,
    this.fileSizeBytes,
    this.sharpness,
    this.meanLuminance,
    this.highlightClip,
    this.shadowClip,
    this.texture,
    this.dx,
    this.dy,
    this.angleDegrees,
    this.registrationMae,
    this.overlap,
    this.periodicAmbiguity = false,
    this.lowTexture = false,
    this.reference = false,
  });

  final String path;
  final bool accepted;
  final String? rejectionReason;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final double? sharpness;
  final double? meanLuminance;
  final double? highlightClip;
  final double? shadowClip;
  final double? texture;
  final double? dx;
  final double? dy;
  final double? angleDegrees;
  final double? registrationMae;
  final double? overlap;
  final bool periodicAmbiguity;
  final bool lowTexture;
  final bool reference;

  Map<String, Object?> toJson() {
    return {
      'path': path,
      'accepted': accepted,
      'rejectionReason': rejectionReason,
      'width': width,
      'height': height,
      'fileSizeBytes': fileSizeBytes,
      'sharpness': sharpness,
      'meanLuminance': meanLuminance,
      'highlightClip': highlightClip,
      'shadowClip': shadowClip,
      'texture': texture,
      'dx': dx,
      'dy': dy,
      'angleDegrees': angleDegrees,
      'registrationMae': registrationMae,
      'overlap': overlap,
      'periodicAmbiguity': periodicAmbiguity,
      'lowTexture': lowTexture,
      'reference': reference,
    };
  }

  factory FrameReconstructionReport.fromJson(Map<String, dynamic> json) {
    return FrameReconstructionReport(
      path: readOptionalString(json['path']) ?? '',
      accepted: readBoolOr(json['accepted'], false),
      rejectionReason: readOptionalString(json['rejectionReason']),
      width: readOptionalInt(json['width']),
      height: readOptionalInt(json['height']),
      fileSizeBytes: readOptionalInt(json['fileSizeBytes']),
      sharpness: readOptionalDouble(json['sharpness']),
      meanLuminance: readOptionalDouble(json['meanLuminance']),
      highlightClip: readOptionalDouble(json['highlightClip']),
      shadowClip: readOptionalDouble(json['shadowClip']),
      texture: readOptionalDouble(json['texture']),
      dx: readOptionalDouble(json['dx']),
      dy: readOptionalDouble(json['dy']),
      angleDegrees: readOptionalDouble(json['angleDegrees']),
      registrationMae: readOptionalDouble(json['registrationMae']),
      overlap: readOptionalDouble(json['overlap']),
      periodicAmbiguity: readBoolOr(json['periodicAmbiguity'], false),
      lowTexture: readBoolOr(json['lowTexture'], false),
      reference: readBoolOr(json['reference'], false),
    );
  }
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
    this.superResolutionPerformed = false,
    this.strategy = '',
    this.referenceFramePath,
    this.inputWidth,
    this.inputHeight,
    this.scaleFactor = 1,
    this.warnings = const [],
    this.frameReports = const [],
    this.inputFramePaths = const [],
    this.denoisedFilePath,
    this.superResolutionFilePath,
    this.metadataFilePath,
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

  /// Pixel dimensions of an output file are not a substitute for this.
  final String? effectiveResolution;
  final bool superResolutionPerformed;
  final String strategy;
  final String? referenceFramePath;
  final int? inputWidth;
  final int? inputHeight;
  final double scaleFactor;
  final List<String> warnings;
  final List<FrameReconstructionReport> frameReports;
  final List<String> inputFramePaths;
  final String? denoisedFilePath;
  final String? superResolutionFilePath;
  final String? metadataFilePath;

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
      'superResolutionPerformed': superResolutionPerformed,
      'strategy': strategy,
      'referenceFramePath': referenceFramePath,
      'inputWidth': inputWidth,
      'inputHeight': inputHeight,
      'scaleFactor': scaleFactor,
      'warnings': warnings,
      'frameReports': [for (final report in frameReports) report.toJson()],
      'inputFramePaths': inputFramePaths,
      'denoisedFilePath': denoisedFilePath,
      'superResolutionFilePath': superResolutionFilePath,
      'metadataFilePath': metadataFilePath,
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
        milliseconds: readOptionalInt(json['processingDurationMilliseconds']) ?? 0,
      ),
      algorithmName: readOptionalString(json['algorithmName']) ?? 'unknown',
      algorithmVersion: readOptionalString(json['algorithmVersion']) ?? '0',
      qualityMetrics: readStringMap(json['qualityMetrics']),
      message: readOptionalString(json['message']) ?? '',
      effectiveResolution: readOptionalString(json['effectiveResolution']),
      superResolutionPerformed: readBoolOr(json['superResolutionPerformed'], false),
      strategy: readOptionalString(json['strategy']) ?? '',
      referenceFramePath: readOptionalString(json['referenceFramePath']),
      inputWidth: readOptionalInt(json['inputWidth']),
      inputHeight: readOptionalInt(json['inputHeight']),
      scaleFactor: readOptionalDouble(json['scaleFactor']) ?? 1,
      warnings: readStringList(json['warnings']),
      frameReports: _reports(json['frameReports']),
      inputFramePaths: readStringList(json['inputFramePaths']),
      denoisedFilePath: readOptionalString(json['denoisedFilePath']),
      superResolutionFilePath: readOptionalString(json['superResolutionFilePath']),
      metadataFilePath: readOptionalString(json['metadataFilePath']),
    );
  }

  static List<FrameReconstructionReport> _reports(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map) FrameReconstructionReport.fromJson(Map<String, dynamic>.from(item)),
    ];
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
