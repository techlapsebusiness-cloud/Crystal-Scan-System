import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/services/super_resolution_service.dart';

/// Explicit stand-in used until a reconstruction engine exists.
///
/// It does not decode frames, write an output image, or report a resolution.
class UnavailableSuperResolutionService implements SuperResolutionService {
  const UnavailableSuperResolutionService();

  static const String name = 'unavailable';
  static const String version = '0';

  @override
  String get algorithmName => name;

  @override
  String get algorithmVersion => version;

  @override
  bool get isAvailable => false;

  @override
  Future<ReconstructionResult> reconstruct(ReconstructionRequest request) async {
    final clock = Stopwatch()..start();
    clock.stop();
    return ReconstructionResult.unavailable(
      inputFrameCount: request.originalImagePaths.length,
      algorithmName: algorithmName,
      algorithmVersion: algorithmVersion,
      processingDuration: clock.elapsed,
    );
  }
}
