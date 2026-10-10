enum RearLensKind { wide, telephoto, ultraWide, unknown }

class RearCameraCandidate {
  const RearCameraCandidate({required this.name, required this.lens});

  final String name;
  final RearLensKind lens;
}

class RearCameraSelection {
  const RearCameraSelection({required this.camera, this.note});

  final RearCameraCandidate camera;
  final String? note;
}

/// Picks one rear camera and keeps that choice for the whole session.
///
/// A reported wide lens is preferred. When the platform does not label lenses,
/// the first rear camera is the platform default and is not changed later.
RearCameraSelection selectRearCamera(List<RearCameraCandidate> cameras) {
  if (cameras.isEmpty) {
    throw ArgumentError('No rear cameras to select.');
  }
  RearCameraCandidate? wide;
  RearCameraCandidate? unknown;
  for (final camera in cameras) {
    if (camera.lens == RearLensKind.wide && wide == null) {
      wide = camera;
    } else if (camera.lens == RearLensKind.unknown && unknown == null) {
      unknown = camera;
    }
  }
  final chosen = wide ?? unknown ?? cameras.first;
  final note = cameras.length > 1
      ? 'Several rear cameras are available. Crystal Scan stays on '
            '${chosen.name} for the whole session and does not switch lenses.'
      : null;
  return RearCameraSelection(camera: chosen, note: note);
}
