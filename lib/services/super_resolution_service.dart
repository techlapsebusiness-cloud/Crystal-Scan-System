import 'package:microscopeapp/models/reconstruction_result.dart';

export 'package:microscopeapp/models/reconstruction_result.dart'
    show ReconstructionCancellation, ReconstructionProgress;

/// Estimates the unknown high-resolution image x from observed frames y_i.
///
/// A future implementation may solve y_i = D(H_i x) + n_i by validating
/// frames, estimating motion, registering them at subpixel precision, rejecting
/// unusable frames, reconstructing, and saving a new file beside the originals.
/// Resizing one frame, averaging identical frames, or inventing PCB traces is
/// not an implementation of this service.
abstract class SuperResolutionService {
  String get algorithmName;

  String get algorithmVersion;

  bool get isAvailable;

  Future<ReconstructionResult> reconstruct(
    ReconstructionRequest request, {
    void Function(ReconstructionProgress progress)? onProgress,
    ReconstructionCancellation? cancellation,
  });
}
