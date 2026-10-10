import 'dart:io';
import 'dart:typed_data';

import 'package:microscopeapp/features/capture/data/still_camera.dart';
import 'package:microscopeapp/models/camera_setup.dart';

import 'tiny_jpeg.dart';

class FakeStillCamera implements StillCamera {
  FakeStillCamera({
    required this.outputDirectory,
    this.jpeg,
    this.failFrames = const {},
    this.emptyFrames = const {},
    this.nonJpegFrames = const {},
    CameraSetup? setup,
  }) : setup =
           setup ??
           const CameraSetup(
             cameraName: 'fake-rear',
             lensDirection: 'back',
             lensType: 'wide',
             sensorOrientation: 90,
             requestedResolution: 'max',
             previewWidth: 100,
             previewHeight: 80,
             flashDisabled: true,
             focusLocked: true,
             exposureLocked: true,
             refocusBetweenFrames: false,
             focusMode: 'locked',
             exposureMode: 'locked',
             flashMode: 'off',
             limitations: ['ISO is not exposed by the test camera.'],
           );

  final Directory outputDirectory;
  final Uint8List? jpeg;
  final Set<int> failFrames;
  final Set<int> emptyFrames;
  final Set<int> nonJpegFrames;
  final CameraSetup setup;

  bool ready = true;
  bool taking = false;
  int shots = 0;
  int prepareCalls = 0;
  Future<void> Function()? beforeShot;

  @override
  bool get isReady => ready;

  @override
  bool get isTakingPicture => taking;

  @override
  Future<CameraSetup> prepareStableCapture() async {
    prepareCalls += 1;
    return setup;
  }

  @override
  Future<CapturedShot> takePicture() async {
    if (!ready) {
      throw StateError('Camera is not ready.');
    }
    if (taking) {
      throw StateError('Capture already in progress.');
    }
    taking = true;
    try {
      if (beforeShot != null) {
        await beforeShot!();
      }
      shots += 1;
      final frame = shots;
      if (failFrames.contains(frame)) {
        throw StateError('Shutter failed on frame $frame.');
      }
      final file = File('${outputDirectory.path}/shot_$frame.jpg');
      if (emptyFrames.contains(frame)) {
        await file.writeAsBytes(<int>[]);
      } else if (nonJpegFrames.contains(frame)) {
        await file.writeAsBytes(<int>[1, 2, 3, 4]);
      } else {
        await file.writeAsBytes(jpeg ?? tinyJpeg(width: 32, height: 16));
      }
      return CapturedShot(
        path: file.path,
        focusMode: 'locked',
        exposureMode: 'locked',
        flashMode: 'off',
      );
    } finally {
      taking = false;
    }
  }
}
