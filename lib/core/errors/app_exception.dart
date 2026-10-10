/// Base type for failures Crystal Scan can explain to the user.
class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// The operating system denied camera access, or will not show the prompt again.
class CameraPermissionException extends AppException {
  const CameraPermissionException(super.message, {super.cause});
}

/// No usable rear camera is available, or the camera plugin is missing.
class CameraUnavailableException extends AppException {
  const CameraUnavailableException(super.message, {super.cause});
}

/// A capture session or shutter operation is already in progress.
class CaptureBusyException extends AppException {
  const CaptureBusyException(super.message, {super.cause});
}

/// Session metadata or its directory could not be read or written safely.
class SessionDataException extends AppException {
  const SessionDataException(super.message, {super.cause});
}
