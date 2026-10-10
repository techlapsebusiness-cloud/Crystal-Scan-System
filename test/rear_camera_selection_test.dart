import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/features/capture/domain/rear_camera_selection.dart';

void main() {
  test('prefers the wide rear camera and does not switch later', () {
    final selection = selectRearCamera(const [
      RearCameraCandidate(name: 'ultra', lens: RearLensKind.ultraWide),
      RearCameraCandidate(name: 'main', lens: RearLensKind.wide),
      RearCameraCandidate(name: 'tele', lens: RearLensKind.telephoto),
    ]);
    expect(selection.camera.name, 'main');
    expect(selection.note, contains('does not switch'));
  });

  test('uses the first unlabeled rear camera when lens types are unknown', () {
    final selection = selectRearCamera(const [
      RearCameraCandidate(name: 'camera-0', lens: RearLensKind.unknown),
      RearCameraCandidate(name: 'camera-1', lens: RearLensKind.unknown),
    ]);
    expect(selection.camera.name, 'camera-0');
  });
}
