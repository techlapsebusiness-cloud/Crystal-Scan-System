import 'package:microscopeapp/features/reconstruction/data/frame_inspection.dart';
import 'package:microscopeapp/features/reconstruction/data/gray_plane.dart';
import 'package:microscopeapp/features/reconstruction/data/translational_registration.dart';

/// Estimates the motion term H_i for y_i = D(H_i x) + n_i.
///
/// The reconstruction engine calls [estimateTranslation] directly. This
/// service exists for callers that only need a pass/fail alignment check.
abstract class ImageAlignmentService {
  bool get isAvailable;

  Future<void> align(List<String> framePaths);
}

class UnavailableAlignmentService implements ImageAlignmentService {
  const UnavailableAlignmentService();

  @override
  bool get isAvailable => false;

  @override
  Future<void> align(List<String> framePaths) async {
    throw UnsupportedError(
      'Subpixel registration is not implemented. Frames were not aligned.',
    );
  }
}

class LocalAlignmentService implements ImageAlignmentService {
  const LocalAlignmentService();

  @override
  bool get isAvailable => true;

  @override
  Future<void> align(List<String> framePaths) async {
    if (framePaths.length < 2) {
      throw StateError('At least two frames are required for alignment.');
    }
    final referenceImage = await decodeOriented(framePaths.first);
    if (referenceImage == null) {
      throw StateError('The reference frame could not be decoded.');
    }
    final reference = GrayPlane.fromImage(referenceImage);
    var accepted = 1;
    for (final path in framePaths.skip(1)) {
      final image = await decodeOriented(path);
      if (image == null) {
        continue;
      }
      if (image.width != reference.width || image.height != reference.height) {
        continue;
      }
      final estimate = estimateTranslation(reference, GrayPlane.fromImage(image));
      if (estimate.accepted) {
        accepted++;
      }
    }
    if (accepted < 2) {
      throw StateError('No second frame could be aligned to the reference.');
    }
  }
}
