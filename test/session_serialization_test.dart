import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/models/camera_setup.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/frame_record.dart';
import 'package:microscopeapp/models/session_status.dart';

void main() {
  test('session metadata round-trips successes and failures', () {
    final created = DateTime.utc(2026, 10, 10, 14, 30, 12);
    final session = CaptureSession(
      id: 'session_20261010_143012_123_ab12',
      createdAt: created,
      updatedAt: created,
      completedAt: created.add(const Duration(seconds: 9)),
      status: SessionStatus.completed,
      requestedFrameCount: 16,
      directoryPath: '/tmp/crystal/session_20261010_143012_123_ab12',
      framesDirectoryPath: '/tmp/crystal/session_20261010_143012_123_ab12/frames',
      elapsed: const Duration(milliseconds: 9050),
      camera: const CameraSetup(
        cameraName: 'rear-0',
        lensDirection: 'back',
        lensType: 'wide',
        sensorOrientation: 90,
        requestedResolution: 'max',
        previewWidth: 1920,
        previewHeight: 1080,
        zoomLevel: 1,
        focusMode: 'locked',
        exposureMode: 'locked',
        flashMode: 'off',
        flashDisabled: true,
        focusLocked: true,
        exposureLocked: true,
        refocusBetweenFrames: false,
        limitations: ['ISO is not exposed by the camera plugin.'],
      ),
      frames: [
        FrameRecord(
          frameNumber: 1,
          fileName: 'frame_0001.jpg',
          filePath: '/tmp/crystal/frames/frame_0001.jpg',
          fileSizeBytes: 120034,
          width: 4000,
          height: 3000,
          success: true,
          capturedAt: created,
          focusMode: 'locked',
          exposureMode: 'locked',
          flashMode: 'off',
        ),
        FrameRecord.failure(
          frameNumber: 2,
          capturedAt: created.add(const Duration(milliseconds: 200)),
          error: 'Shutter failed.',
        ),
      ],
    );

    final restored = CaptureSession.fromJson(
      jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>,
    );

    expect(restored.id, session.id);
    expect(restored.status, SessionStatus.completed);
    expect(restored.requestedFrameCount, 16);
    expect(restored.savedCount, 1);
    expect(restored.failedCount, 1);
    expect(restored.notAttempted, 14);
    expect(restored.elapsed, const Duration(milliseconds: 9050));
    expect(restored.camera?.focusLocked, isTrue);
    expect(restored.camera?.refocusBetweenFrames, isFalse);
    expect(restored.camera?.limitations, ['ISO is not exposed by the camera plugin.']);
    expect(restored.frames[0].width, 4000);
    expect(restored.frames[0].height, 3000);
    expect(restored.frames[0].fileSizeBytes, 120034);
    expect(restored.frames[0].exposureOffset, isNull);
    expect(restored.frames[1].success, isFalse);
    expect(restored.frames[1].fileName, 'frame_0002.jpg');
    expect(restored.frames[1].error, 'Shutter failed.');
    expect(restored.capturedSizeLabel, '4000×3000');
    expect(restored.directoryPath, session.directoryPath);
  });
}
