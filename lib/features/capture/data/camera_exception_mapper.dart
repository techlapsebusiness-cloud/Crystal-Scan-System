import 'package:camera/camera.dart';

import 'package:microscopeapp/core/errors/app_exception.dart';

const Set<String> cameraPermissionCodes = {
  'CameraAccessDenied',
  'CameraAccessDeniedWithoutPrompt',
  'CameraAccessRestricted',
};

AppException mapCameraException(CameraException error) {
  final description = error.description ?? 'The camera reported an error.';
  if (cameraPermissionCodes.contains(error.code)) {
    return CameraPermissionException(
      'Camera permission is required. Enable the camera for Crystal Scan in system settings, then try again.',
      cause: error,
    );
  }
  if (error.code == 'CameraPermissionsRequestOngoing') {
    return CameraUnavailableException(
      'A camera permission request is already in progress. Try again in a moment.',
      cause: error,
    );
  }
  return CameraUnavailableException(description, cause: error);
}
