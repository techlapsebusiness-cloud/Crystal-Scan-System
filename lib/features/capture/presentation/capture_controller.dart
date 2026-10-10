import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'package:microscopeapp/core/errors/app_exception.dart';
import 'package:microscopeapp/features/capture/data/capture_service.dart';
import 'package:microscopeapp/features/capture/data/rear_camera_session.dart';
import 'package:microscopeapp/features/capture/domain/capture_cancellation.dart';
import 'package:microscopeapp/features/capture/domain/frame_counts.dart';
import 'package:microscopeapp/models/camera_setup.dart';
import 'package:microscopeapp/models/capture_progress.dart';
import 'package:microscopeapp/models/capture_session.dart';

enum CapturePhase { opening, ready, capturing, permissionDenied, unavailable, error }

class CaptureController extends ChangeNotifier {
  CaptureController({
    required this.captureService,
    required this.openCamera,
  });

  final CaptureService captureService;
  final Future<RearCameraSession> Function() openCamera;

  CapturePhase phase = CapturePhase.opening;
  String? message;
  int frameCount = 16;
  CaptureProgress progress = const CaptureProgress(
    requested: 16,
    saved: 0,
    failed: 0,
    currentFrame: 0,
    elapsed: Duration.zero,
    isRunning: false,
  );
  CameraSetup? cameraSetup;

  RearCameraSession? _camera;
  RearCameraSession? _pendingDispose;
  CaptureCancellation? _cancellation;
  Timer? _ticker;
  final Stopwatch _clock = Stopwatch();
  Future<void> _chain = Future<void>.value();
  bool _startInFlight = false;
  bool _releaseWhenIdle = false;
  bool _disposed = false;

  bool get isCapturing => phase == CapturePhase.capturing;

  bool get stopRequested => _cancellation?.isStopRequested ?? false;

  bool get hasInitializedCamera => _camera?.isReady ?? false;

  CameraController? get previewController {
    final camera = _camera;
    if (camera == null || !camera.isReady) {
      return null;
    }
    return camera.controller;
  }

  bool get canChangeSettings => phase == CapturePhase.ready && !_startInFlight;

  void selectFrameCount(int count) {
    if (!canChangeSettings || !isAllowedFrameCount(count) || count == frameCount) {
      return;
    }
    frameCount = count;
    progress = progress.copyWith(requested: count);
    _notify();
  }

  Future<void> initialize() {
    return _serialize(_initialize);
  }

  Future<void> releaseCamera() {
    return _serialize(() async {
      if (_startInFlight) {
        _releaseWhenIdle = true;
        return;
      }
      await _release();
    });
  }

  void cancel() {
    _cancellation?.cancel();
    _notify();
  }

  void interrupt() {
    _cancellation?.interrupt();
    _notify();
  }

  Future<CaptureSession?> startCapture() {
    if (_disposed || _startInFlight || phase != CapturePhase.ready) {
      return Future<CaptureSession?>.value();
    }
    _startInFlight = true;
    phase = CapturePhase.capturing;
    message = null;
    cameraSetup = null;
    progress = CaptureProgress(
      requested: frameCount,
      saved: 0,
      failed: 0,
      currentFrame: 0,
      elapsed: Duration.zero,
      isRunning: true,
    );
    _notify();
    final future = _serialize(_captureBody);
    return future.whenComplete(() {
      _startInFlight = false;
    });
  }

  Future<CaptureSession?> _captureBody() async {
    final camera = _camera;
    final cancellation = CaptureCancellation();
    _cancellation = cancellation;
    _clock
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_clock.isRunning || _disposed) {
        return;
      }
      progress = progress.copyWith(elapsed: _clock.elapsed, isRunning: true);
      _notify();
    });

    try {
      if (camera == null || !camera.isReady) {
        phase = CapturePhase.error;
        message = 'The camera is not ready.';
        progress = progress.copyWith(isRunning: false);
        return null;
      }
      final session = await captureService.capture(
        camera: camera,
        frameCount: frameCount,
        cancellation: cancellation,
        onProgress: _onProgress,
      );
      progress = progress.copyWith(
        saved: session.savedCount,
        failed: session.failedCount,
        requested: session.requestedFrameCount,
        elapsed: session.elapsed,
        isRunning: false,
        currentFrame: session.frames.length,
      );
      cameraSetup = session.camera ?? cameraSetup;
      return session;
    } on CaptureBusyException catch (error) {
      message = error.message;
      progress = progress.copyWith(isRunning: false);
      return null;
    } catch (error) {
      phase = CapturePhase.error;
      message = error.toString();
      progress = progress.copyWith(isRunning: false);
      return null;
    } finally {
      _clock.stop();
      _ticker?.cancel();
      _ticker = null;
      _cancellation = null;
      if (_releaseWhenIdle || _pendingDispose != null) {
        await _release();
      }
      if (!_disposed && phase == CapturePhase.capturing) {
        phase = _camera == null ? CapturePhase.opening : CapturePhase.ready;
      }
      _notify();
    }
  }

  void _onProgress(CaptureProgress next, CaptureSession session) {
    progress = next;
    cameraSetup = session.camera ?? cameraSetup;
    _notify();
  }

  Future<void> _initialize() async {
    if (_disposed || _startInFlight) {
      return;
    }
    if (_camera != null && _camera!.isReady) {
      phase = CapturePhase.ready;
      message = null;
      _notify();
      return;
    }
    await _release();
    phase = CapturePhase.opening;
    message = null;
    _notify();
    try {
      final camera = await openCamera();
      if (_disposed) {
        await camera.dispose();
        return;
      }
      _camera = camera;
      camera.controller.addListener(_onCameraValue);
      phase = CapturePhase.ready;
      message = null;
    } on CameraPermissionException catch (error) {
      phase = CapturePhase.permissionDenied;
      message = error.message;
    } on CameraUnavailableException catch (error) {
      phase = CapturePhase.unavailable;
      message = error.message;
    } catch (error) {
      phase = CapturePhase.error;
      message = 'The camera could not be opened.';
    }
    _notify();
  }

  void _onCameraValue() {
    final camera = _camera;
    if (camera == null || _disposed || isCapturing) {
      return;
    }
    if (camera.controller.value.hasError) {
      phase = CapturePhase.error;
      message =
          camera.controller.value.errorDescription ??
          'The camera reported an error.';
      _notify();
    }
  }

  Future<void> _release() async {
    final camera = _camera ?? _pendingDispose;
    _camera = null;
    _pendingDispose = null;
    _releaseWhenIdle = false;
    if (camera == null) {
      return;
    }
    camera.controller.removeListener(_onCameraValue);
    try {
      await camera.dispose();
    } catch (error) {
      // The platform view may already be gone.
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _chain.then((_) => action());
    _chain = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _cancellation?.interrupt();
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      camera.controller.removeListener(_onCameraValue);
      if (_startInFlight) {
        _pendingDispose = camera;
        _releaseWhenIdle = true;
      } else {
        unawaited(
          camera.dispose().then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        );
      }
    }
    super.dispose();
  }
}
