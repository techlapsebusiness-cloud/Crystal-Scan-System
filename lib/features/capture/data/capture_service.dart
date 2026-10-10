import 'package:microscopeapp/core/errors/app_exception.dart';
import 'package:microscopeapp/core/storage/session_store.dart';
import 'package:microscopeapp/features/capture/data/still_camera.dart';
import 'package:microscopeapp/features/capture/domain/capture_cancellation.dart';
import 'package:microscopeapp/features/capture/domain/frame_counts.dart';
import 'package:microscopeapp/models/capture_progress.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/frame_record.dart';
import 'package:microscopeapp/models/session_status.dart';

typedef CaptureProgressListener =
    void Function(CaptureProgress progress, CaptureSession session);

/// Captures still frames one at a time into a unique session directory.
///
/// Image quality scores are intentionally not consulted. A blur metric is not
/// calibrated for this camera pipeline and must not reject frames.
class CaptureService {
  CaptureService({
    required this.store,
    this.interFrameDelay = const Duration(milliseconds: 100),
    this.maxConsecutiveFailures = 5,
  });

  final SessionStore store;

  /// Pause after a frame returns, before the next shutter call. This is a
  /// device-pipeline settle delay, not a frame-rate guarantee.
  final Duration interFrameDelay;

  /// Stops the run when the camera fails this many times in a row, so a
  /// disconnected camera is not asked for the rest of a long sequence.
  final int maxConsecutiveFailures;

  bool _busy = false;

  bool get isBusy => _busy;

  Future<CaptureSession> capture({
    required StillCamera camera,
    required int frameCount,
    required CaptureCancellation cancellation,
    CaptureProgressListener? onProgress,
  }) async {
    if (!isAllowedFrameCount(frameCount)) {
      throw ArgumentError.value(
        frameCount,
        'frameCount',
        'Choose 16, 32, 64, or 128 frames.',
      );
    }
    if (_busy) {
      throw const CaptureBusyException(
        'A capture session is already running.',
      );
    }

    _busy = true;
    final clock = Stopwatch()..start();
    try {
      var session = await store.createSession(requestedFrameCount: frameCount);
      _emit(onProgress, session, clock, currentFrame: 0, running: true);

      if (!camera.isReady || camera.isTakingPicture) {
        return _finish(
          session,
          status: SessionStatus.failed,
          errorMessage: 'The camera was not ready to capture.',
          clock: clock,
          onProgress: onProgress,
        );
      }

      try {
        final setup = await camera.prepareStableCapture();
        session = session.copyWith(
          status: SessionStatus.capturing,
          camera: setup,
          elapsed: clock.elapsed,
        );
        await store.save(session);
      } catch (error) {
        return _finish(
          session,
          status: SessionStatus.failed,
          errorMessage: error.toString(),
          clock: clock,
          onProgress: onProgress,
        );
      }

      var consecutiveFailures = 0;
      for (var frame = 1; frame <= frameCount; frame++) {
        final stop = _stopStatus(cancellation);
        if (stop != null) {
          return _finish(
            session,
            status: stop,
            errorMessage: stop == SessionStatus.interrupted
                ? 'The capture was interrupted. Saved frames were kept.'
                : null,
            clock: clock,
            onProgress: onProgress,
          );
        }
        if (!camera.isReady || camera.isTakingPicture) {
          return _finish(
            session,
            status: SessionStatus.interrupted,
            errorMessage: 'The camera became unavailable during capture.',
            clock: clock,
            onProgress: onProgress,
          );
        }

        _emit(onProgress, session, clock, currentFrame: frame, running: true);

        FrameRecord record;
        try {
          final shot = await camera.takePicture();
          record = await store.commitFrame(
            session: session,
            frameNumber: frame,
            sourcePath: shot.path,
            capturedAt: DateTime.now().toUtc(),
            focusMode: shot.focusMode,
            exposureMode: shot.exposureMode,
            flashMode: shot.flashMode,
            exposureOffset: shot.exposureOffset,
          );
        } on SessionDataException catch (error) {
          record = FrameRecord.failure(
            frameNumber: frame,
            capturedAt: DateTime.now().toUtc(),
            error: error.message,
          );
          session = session.copyWith(
            frames: [...session.frames, record],
            elapsed: clock.elapsed,
          );
          await store.save(session);
          return _finish(
            session,
            status: SessionStatus.failed,
            errorMessage: error.message,
            clock: clock,
            onProgress: onProgress,
          );
        } catch (error) {
          record = FrameRecord.failure(
            frameNumber: frame,
            capturedAt: DateTime.now().toUtc(),
            error: error.toString(),
          );
        }

        consecutiveFailures = record.success ? 0 : consecutiveFailures + 1;
        session = session.copyWith(
          frames: [...session.frames, record],
          elapsed: clock.elapsed,
        );
        await store.save(session);
        _emit(onProgress, session, clock, currentFrame: frame, running: true);

        final stopAfterFrame = _stopStatus(cancellation);
        if (stopAfterFrame != null) {
          return _finish(
            session,
            status: stopAfterFrame,
            errorMessage: stopAfterFrame == SessionStatus.interrupted
                ? 'The capture was interrupted. Saved frames were kept.'
                : null,
            clock: clock,
            onProgress: onProgress,
          );
        }
        if (consecutiveFailures >= maxConsecutiveFailures) {
          return _finish(
            session,
            status: SessionStatus.failed,
            errorMessage:
                'Capture stopped after $consecutiveFailures consecutive frame failures.',
            clock: clock,
            onProgress: onProgress,
          );
        }
        final hasAnotherFrame = frame < frameCount;
        if (hasAnotherFrame && interFrameDelay > Duration.zero) {
          await Future<void>.delayed(interFrameDelay);
        }
      }

      final finishedStatus = session.savedCount == 0 && session.failedCount > 0
          ? SessionStatus.failed
          : SessionStatus.completed;
      return _finish(
        session,
        status: finishedStatus,
        errorMessage: finishedStatus == SessionStatus.failed
            ? 'No frames were saved.'
            : null,
        clock: clock,
        onProgress: onProgress,
      );
    } finally {
      _busy = false;
    }
  }

  SessionStatus? _stopStatus(CaptureCancellation cancellation) {
    if (cancellation.isInterrupted) {
      return SessionStatus.interrupted;
    }
    if (cancellation.isCancelled) {
      return SessionStatus.cancelled;
    }
    return null;
  }

  Future<CaptureSession> _finish(
    CaptureSession session, {
    required SessionStatus status,
    required String? errorMessage,
    required Stopwatch clock,
    required CaptureProgressListener? onProgress,
  }) async {
    final finished = await store.save(
      session.copyWith(
        status: status,
        completedAt: DateTime.now().toUtc(),
        elapsed: clock.elapsed,
        errorMessage: errorMessage ?? session.errorMessage,
      ),
    );
    _emit(
      onProgress,
      finished,
      clock,
      currentFrame: finished.frames.length,
      running: false,
    );
    return finished;
  }

  void _emit(
    CaptureProgressListener? onProgress,
    CaptureSession session,
    Stopwatch clock, {
    required int currentFrame,
    required bool running,
  }) {
    onProgress?.call(
      CaptureProgress(
        requested: session.requestedFrameCount,
        saved: session.savedCount,
        failed: session.failedCount,
        currentFrame: currentFrame,
        elapsed: clock.elapsed,
        isRunning: running,
      ),
      session,
    );
  }
}
