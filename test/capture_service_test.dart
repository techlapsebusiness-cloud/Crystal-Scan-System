import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/errors/app_exception.dart';
import 'package:microscopeapp/core/storage/session_store.dart';
import 'package:microscopeapp/features/capture/data/capture_service.dart';
import 'package:microscopeapp/features/capture/domain/capture_cancellation.dart';
import 'package:microscopeapp/models/capture_progress.dart';
import 'package:microscopeapp/models/session_status.dart';

import 'support/fake_still_camera.dart';

void main() {
  late Directory root;
  late Directory shots;
  late SessionStore store;
  late CaptureService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crystal_capture_');
    shots = await Directory.systemTemp.createTemp('crystal_shots_');
    store = SessionStore(root);
    service = CaptureService(
      store: store,
      interFrameDelay: Duration.zero,
      maxConsecutiveFailures: 5,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    if (await shots.exists()) {
      await shots.delete(recursive: true);
    }
  });

  CaptureService strictService({int maxFailures = 5}) {
    return CaptureService(
      store: store,
      interFrameDelay: Duration.zero,
      maxConsecutiveFailures: maxFailures,
    );
  }

  test('saves frames sequentially and reloads the bookkeeping', () async {
    final camera = FakeStillCamera(outputDirectory: shots);
    final snapshots = <CaptureProgress>[];
    final session = await service.capture(
      camera: camera,
      frameCount: 16,
      cancellation: CaptureCancellation(),
      onProgress: (progress, _) => snapshots.add(progress),
    );

    expect(camera.prepareCalls, 1);
    expect(camera.shots, 16);
    expect(session.status, SessionStatus.completed);
    expect(session.savedCount, 16);
    expect(session.failedCount, 0);
    expect(session.frames.map((frame) => frame.fileName).toList(), [
      for (var number = 1; number <= 16; number++)
        'frame_${number.toString().padLeft(4, '0')}.jpg',
    ]);
    expect(session.frames.every((frame) => frame.width == 32 && frame.height == 16), isTrue);
    expect(session.frames.every((frame) => (frame.fileSizeBytes ?? 0) > 0), isTrue);
    expect(session.camera?.refocusBetweenFrames, isFalse);
    expect(snapshots.last.percent, 100);
    expect(snapshots.last.saved, 16);

    final loaded = await store.load(session.id);
    expect(loaded.savedCount, 16);
    expect(loaded.status, SessionStatus.completed);
    for (final frame in loaded.frames) {
      expect(await File(frame.filePath!).exists(), isTrue);
    }
  });

  test('counts failed frames without treating them as saved', () async {
    final camera = FakeStillCamera(
      outputDirectory: shots,
      failFrames: {2},
    );
    final snapshots = <CaptureProgress>[];
    final session = await service.capture(
      camera: camera,
      frameCount: 16,
      cancellation: CaptureCancellation(),
      onProgress: (progress, _) => snapshots.add(progress),
    );

    expect(session.status, SessionStatus.completed);
    expect(session.savedCount, 15);
    expect(session.failedCount, 1);
    expect(session.frames[1].success, isFalse);
    expect(
      snapshots.any((progress) => progress.saved == 1 && progress.failed == 1),
      isTrue,
    );
    expect(snapshots.every((progress) => progress.saved <= 15), isTrue);
  });

  test('stops after consecutive failures and keeps the attempted records', () async {
    final camera = FakeStillCamera(
      outputDirectory: shots,
      failFrames: {1, 2, 3, 4, 5, 6},
    );
    final session = await strictService(maxFailures: 3).capture(
      camera: camera,
      frameCount: 16,
      cancellation: CaptureCancellation(),
    );

    expect(camera.shots, 3);
    expect(session.frames, hasLength(3));
    expect(session.savedCount, 0);
    expect(session.failedCount, 3);
    expect(session.notAttempted, 13);
    expect(session.status, SessionStatus.failed);
    expect(session.errorMessage, contains('consecutive'));
    final loaded = await store.load(session.id);
    expect(loaded.frames, hasLength(3));
    expect(loaded.status, SessionStatus.failed);
  });

  test('marks every attempted frame failed when the run finishes with none saved', () async {
    final camera = FakeStillCamera(
      outputDirectory: shots,
      failFrames: {for (var frame = 1; frame <= 16; frame++) frame},
    );
    final session = await strictService(maxFailures: 20).capture(
      camera: camera,
      frameCount: 16,
      cancellation: CaptureCancellation(),
    );
    expect(session.status, SessionStatus.failed);
    expect(session.savedCount, 0);
    expect(session.failedCount, 16);
    expect(session.errorMessage, 'No frames were saved.');
  });

  test('cancellation stops between frames and leaves an empty or partial session', () async {
    final alreadyCancelled = CaptureCancellation()..cancel();
    final camera = FakeStillCamera(outputDirectory: shots);
    final empty = await service.capture(
      camera: camera,
      frameCount: 16,
      cancellation: alreadyCancelled,
    );
    expect(camera.shots, 0);
    expect(empty.frames, isEmpty);
    expect(empty.status, SessionStatus.cancelled);
    expect((await store.load(empty.id)).status, SessionStatus.cancelled);

    final cancellation = CaptureCancellation();
    final secondCamera = FakeStillCamera(outputDirectory: shots);
    var entries = 0;
    secondCamera.beforeShot = () async {
      entries += 1;
      if (entries == 2) {
        cancellation.cancel();
      }
    };
    final partial = await service.capture(
      camera: secondCamera,
      frameCount: 16,
      cancellation: cancellation,
    );
    expect(secondCamera.shots, 2);
    expect(partial.savedCount, 2);
    expect(partial.status, SessionStatus.cancelled);
    expect(partial.notAttempted, 14);
  });

  test('an interruption is recorded without dropping saved frames', () async {
    final cancellation = CaptureCancellation();
    final camera = FakeStillCamera(outputDirectory: shots);
    var entries = 0;
    camera.beforeShot = () async {
      entries += 1;
      if (entries == 1) {
        cancellation.interrupt();
      }
    };
    final session = await service.capture(
      camera: camera,
      frameCount: 32,
      cancellation: cancellation,
    );
    expect(session.status, SessionStatus.interrupted);
    expect(session.savedCount, 1);
    expect(session.errorMessage, contains('interrupted'));
    expect((await store.load(session.id)).frames, hasLength(1));
  });

  test('rejects a second session while one is running', () async {
    final release = Completer<void>();
    final entered = Completer<void>();
    final camera = FakeStillCamera(outputDirectory: shots);
    camera.beforeShot = () async {
      if (!entered.isCompleted) {
        entered.complete();
      }
      await release.future;
    };
    final running = service.capture(
      camera: camera,
      frameCount: 16,
      cancellation: CaptureCancellation(),
    );
    await entered.future;
    await expectLater(
      service.capture(
        camera: camera,
        frameCount: 16,
        cancellation: CaptureCancellation(),
      ),
      throwsA(isA<CaptureBusyException>()),
    );
    release.complete();
    final session = await running;
    expect(session.savedCount, 16);
    expect(service.isBusy, isFalse);
  });

  test('a camera that is not ready does not invent frames', () async {
    final camera = FakeStillCamera(outputDirectory: shots)..ready = false;
    final session = await service.capture(
      camera: camera,
      frameCount: 16,
      cancellation: CaptureCancellation(),
    );
    expect(camera.shots, 0);
    expect(session.frames, isEmpty);
    expect(session.status, SessionStatus.failed);
    expect((await store.load(session.id)).frames, isEmpty);
  });

  test('rejects frame counts outside the supported set', () async {
    final camera = FakeStillCamera(outputDirectory: shots);
    await expectLater(
      service.capture(
        camera: camera,
        frameCount: 10,
        cancellation: CaptureCancellation(),
      ),
      throwsArgumentError,
    );
    expect(service.isBusy, isFalse);
  });
}
