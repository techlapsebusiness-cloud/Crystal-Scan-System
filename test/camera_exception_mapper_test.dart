import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/errors/app_exception.dart';
import 'package:microscopeapp/features/capture/data/camera_exception_mapper.dart';

void main() {
  test('maps permission denials separately from other camera errors', () {
    final denied = mapCameraException(
      CameraException('CameraAccessDenied', 'Camera access permission was denied.'),
    );
    expect(denied, isA<CameraPermissionException>());

    final blocked = mapCameraException(
      CameraException('CameraAccessDeniedWithoutPrompt', 'denied'),
    );
    expect(blocked, isA<CameraPermissionException>());

    final missing = mapCameraException(
      CameraException('CameraNotFound', 'No camera'),
    );
    expect(missing, isA<CameraUnavailableException>());
    expect(missing, isNot(isA<CameraPermissionException>()));
  });
}
