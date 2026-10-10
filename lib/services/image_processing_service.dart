import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/services/image_alignment_service.dart';
import 'package:microscopeapp/services/image_quality_service.dart';
import 'package:microscopeapp/services/super_resolution_service.dart';
import 'package:microscopeapp/services/unavailable_reconstruction_service.dart';

/// Facade the UI calls. Capture and storage do not depend on it.
///
/// While super-resolution is unavailable, alignment is not run and no output
/// file is created. Quality analysis is not used to accept or reject frames.
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

  final ImageAlignmentService alignment;
  final SuperResolutionService superResolution;
  final ImageQualityService quality;

  bool get isAvailable => superResolution.isAvailable && alignment.isAvailable;

  /// Runs reconstruction only when an engine is available.
  ///
  /// The unavailable engine returns immediately and does not align frames or
  /// write a file. A future engine can register frames here before solving
  /// for the high-resolution image.
  Future<ReconstructionResult> reconstruct(ReconstructionRequest request) async {
    if (!isAvailable) {
      return superResolution.reconstruct(request);
    }
    await alignment.align(request.originalImagePaths);
    return superResolution.reconstruct(request);
  }
}
