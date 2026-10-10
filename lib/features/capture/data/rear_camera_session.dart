import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'package:microscopeapp/core/errors/app_exception.dart';
import 'package:microscopeapp/features/capture/data/camera_exception_mapper.dart';
import 'package:microscopeapp/features/capture/data/still_camera.dart';
import 'package:microscopeapp/features/capture/domain/rear_camera_selection.dart';
import 'package:microscopeapp/models/camera_setup.dart';

const Duration _focusSettleDelay = Duration(milliseconds: 400);
const Duration _exposureSettleDelay = Duration(milliseconds: 200);

/// Rear camera opened once for preview and still capture.
///
/// The lens chosen here is not changed for the rest of the session.
class RearCameraSession implements StillCamera {
  RearCameraSession._(this.controller, this._lensNote);

  final CameraController controller;
  final String? _lensNote;

  static Future<RearCameraSession> open() async {
    final cameras = await _loadCameras();
    final rear = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .toList(growable: false);
    if (rear.isEmpty) {
      throw CameraUnavailableException(
        cameras.isEmpty
            ? 'No camera was found on this device.'
            : 'No rear camera was found.',
      );
    }

    final selection = selectRearCamera([
      for (final camera in rear)
        RearCameraCandidate(name: camera.name, lens: _lensKind(camera.lensType)),
    ]);
    final description = rear.firstWhere(
      (camera) => camera.name == selection.camera.name,
    );
    final controller = CameraController(
      description,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
    } on CameraException catch (error) {
      await controller.dispose();
      throw mapCameraException(error);
    } catch (error) {
      await controller.dispose();
      throw CameraUnavailableException(
        'The rear camera could not be opened.',
        cause: error,
      );
    }
    return RearCameraSession._(controller, selection.note);
  }

  @override
  bool get isReady =>
      controller.value.isInitialized && !controller.value.hasError;

  @override
  bool get isTakingPicture => controller.value.isTakingPicture;

  Future<void> dispose() {
    return controller.dispose();
  }

  @override
  Future<CameraSetup> prepareStableCapture() async {
    _ensureAlive();
    final limitations = <String>[
      if (_lensNote != null) _lensNote,
      'ISO, shutter speed, and focus distance are not exposed by the camera plugin, so they are not recorded.',
      'The current exposure compensation cannot be read without changing it, so it is left untouched and is not recorded.',
      'Autofocus and auto exposure run once before the first frame, then stay locked when the camera accepts the lock. They are not adjusted between frames.',
    ];

    var flashDisabled = false;
    String? flashMode = controller.value.flashMode.name;
    try {
      await controller.setFlashMode(FlashMode.off);
      flashDisabled = controller.value.flashMode == FlashMode.off;
      flashMode = controller.value.flashMode.name;
      if (!flashDisabled) {
        limitations.add('Flash off was requested, but the camera did not report flash off.');
      }
    } on CameraException catch (error) {
      limitations.add('Flash could not be turned off (${error.code}).');
    }

    double? zoomLevel;
    try {
      final minimum = await controller.getMinZoomLevel();
      await controller.setZoomLevel(minimum);
      zoomLevel = minimum;
    } on CameraException catch (error) {
      limitations.add('Zoom was left unchanged (${error.code}).');
    }

    try {
      await controller.lockCaptureOrientation();
    } on CameraException catch (error) {
      limitations.add('Capture orientation could not be locked (${error.code}).');
    }

    var focusLocked = false;
    String? focusMode = controller.value.focusMode.name;
    try {
      if (controller.value.focusPointSupported) {
        await controller.setFocusPoint(const Offset(0.5, 0.5));
      } else {
        limitations.add('This camera does not support setting a focus point.');
      }
      await controller.setFocusMode(FocusMode.auto);
      await Future<void>.delayed(_focusSettleDelay);
      _ensureAlive();
      await controller.setFocusMode(FocusMode.locked);
      focusMode = controller.value.focusMode.name;
      focusLocked = controller.value.focusMode == FocusMode.locked;
      if (!focusLocked) {
        limitations.add('Focus lock was requested, but the camera stayed in $focusMode mode.');
      }
    } on CameraException catch (error) {
      limitations.add(
        'Focus lock is not supported (${error.code}). Focus may change between frames.',
      );
    }

    var exposureLocked = false;
    String? exposureMode = controller.value.exposureMode.name;
    double? minOffset;
    double? maxOffset;
    double? step;
    try {
      minOffset = await controller.getMinExposureOffset();
      maxOffset = await controller.getMaxExposureOffset();
      step = await controller.getExposureOffsetStepSize();
    } on CameraException {
      limitations.add('Exposure compensation range is not available on this camera.');
    }

    try {
      if (controller.value.exposurePointSupported) {
        await controller.setExposurePoint(const Offset(0.5, 0.5));
      } else {
        limitations.add('This camera does not support setting an exposure point.');
      }
      await controller.setExposureMode(ExposureMode.auto);
      await Future<void>.delayed(_exposureSettleDelay);
      _ensureAlive();
      await controller.setExposureMode(ExposureMode.locked);
      exposureMode = controller.value.exposureMode.name;
      exposureLocked = controller.value.exposureMode == ExposureMode.locked;
      if (!exposureLocked) {
        limitations.add(
          'Exposure lock was requested, but the camera stayed in $exposureMode mode.',
        );
      }
    } on CameraException catch (error) {
      limitations.add(
        'Exposure lock is not supported (${error.code}). Exposure may change between frames.',
      );
    }

    final preview = controller.value.previewSize;
    final description = controller.description;
    return CameraSetup(
      cameraName: description.name,
      lensDirection: description.lensDirection.name,
      lensType: description.lensType.name,
      sensorOrientation: description.sensorOrientation,
      requestedResolution: controller.resolutionPreset.name,
      previewWidth: preview?.width.round(),
      previewHeight: preview?.height.round(),
      zoomLevel: zoomLevel,
      focusMode: focusMode,
      exposureMode: exposureMode,
      flashMode: flashMode,
      flashDisabled: flashDisabled,
      focusLocked: focusLocked,
      exposureLocked: exposureLocked,
      refocusBetweenFrames: false,
      minExposureOffset: minOffset,
      maxExposureOffset: maxOffset,
      exposureOffsetStep: step,
      limitations: limitations,
    );
  }

  @override
  Future<CapturedShot> takePicture() async {
    _ensureAlive();
    if (controller.value.isTakingPicture) {
      throw const CaptureBusyException('The camera is already taking a picture.');
    }
    try {
      final file = await controller.takePicture();
      final value = controller.value;
      return CapturedShot(
        path: file.path,
        focusMode: value.focusMode.name,
        exposureMode: value.exposureMode.name,
        flashMode: value.flashMode.name,
        exposureOffset: null,
      );
    } on CameraException catch (error) {
      throw mapCameraException(error);
    }
  }

  void _ensureAlive() {
    if (!controller.value.isInitialized || controller.value.hasError) {
      throw CameraUnavailableException(
        controller.value.errorDescription ?? 'The camera is no longer available.',
      );
    }
  }

  static Future<List<CameraDescription>> _loadCameras() async {
    try {
      return await availableCameras();
    } on CameraException catch (error) {
      throw mapCameraException(error);
    } on MissingPluginException {
      throw const CameraUnavailableException(
        'This platform has no camera plugin. Run Crystal Scan on an Android phone.',
      );
    }
  }

  static RearLensKind _lensKind(CameraLensType type) {
    switch (type) {
      case CameraLensType.wide:
        return RearLensKind.wide;
      case CameraLensType.telephoto:
        return RearLensKind.telephoto;
      case CameraLensType.ultraWide:
        return RearLensKind.ultraWide;
      case CameraLensType.unknown:
        return RearLensKind.unknown;
    }
  }
}
