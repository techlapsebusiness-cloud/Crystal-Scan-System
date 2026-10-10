import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/services/image_alignment_service.dart';
import 'package:microscopeapp/services/image_quality_service.dart';
import 'package:microscopeapp/services/local_reconstruction_service.dart';
import 'package:microscopeapp/services/super_resolution_service.dart';
import 'package:microscopeapp/services/unavailable_reconstruction_service.dart';

/// Facade the UI calls. Capture and storage do not depend on it.
///
/// The local engine performs registration itself. This facade does not call
/// [alignment] first, so frames are not registered twice. The unavailable
/// engine returns immediately and does not write a file.
class ImageProcessingService {
  const ImageProcessingService({
    required this.alignment,
    required this.superResolution,
    required this.quality,
  });

  factory ImageProcessingService.unavailable() {
    return const ImageProcessingService(
      alignment: UnavailableAlignmentService(),
      superResolution: UnavailableSuperResolutionService(),
      quality: UncalibratedQualityService(),
    );
  }

  factory ImageProcessingService.local() {
    return const ImageProcessingService(
      alignment: LocalAlignmentService(),
      superResolution: LocalReconstructionService(),
      quality: LocalQualityService(),
    );
  }

  final ImageAlignmentService alignment;
  final SuperResolutionService superResolution;
  final ImageQualityService quality;

  bool get isAvailable => superResolution.isAvailable;

  /// Runs the configured engine. Progress events come from that engine.
  Future<ReconstructionResult> reconstruct(
    ReconstructionRequest request, {
    void Function(ReconstructionProgress progress)? onProgress,
    ReconstructionCancellation? cancellation,
  }) {
    return superResolution.reconstruct(
      request,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }
}
