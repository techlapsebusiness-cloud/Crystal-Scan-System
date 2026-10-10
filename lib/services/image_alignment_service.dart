/// Estimates the motion term H_i for y_i = D(H_i x) + n_i.
///
/// The first version has no registration implementation. Callers must not
/// treat a thrown error as a successful alignment.
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
