import 'dart:async';
import 'dart:isolate';

import 'package:microscopeapp/features/reconstruction/data/reconstruction_engine.dart';
import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/services/super_resolution_service.dart';

/// Runs [ReconstructionEngine] on a background isolate.
///
/// Tests call [ReconstructionEngine] directly. The isolate exists so a phone
/// UI thread is not blocked by registration and fusion. OpenCV matrices are
/// not sent across the isolate; only paths and JSON-shaped maps are.
class LocalReconstructionService implements SuperResolutionService {
  const LocalReconstructionService();

  @override
  String get algorithmName => ReconstructionEngine.denoiseAlgorithm;

  @override
  String get algorithmVersion => ReconstructionEngine.version;

  @override
  bool get isAvailable => true;

  @override
  Future<ReconstructionResult> reconstruct(
    ReconstructionRequest request, {
    void Function(ReconstructionProgress progress)? onProgress,
    ReconstructionCancellation? cancellation,
  }) async {
    final receive = ReceivePort();
    final errors = ReceivePort();
    final completer = Completer<ReconstructionResult>();
    SendPort? cancelPort;
    var cancelRequested = cancellation?.isCancelled ?? false;
    cancellation?.onCancel = () {
      cancelRequested = true;
      cancelPort?.send('cancel');
    };

    final subscription = receive.listen((message) {
      if (message is SendPort) {
        cancelPort = message;
        if (cancelRequested) {
          cancelPort?.send('cancel');
        }
        return;
      }
      if (message is! Map) {
        return;
      }
      final type = message['type'];
      if (type == 'progress') {
        final stageName = message['stage'];
        if (stageName is! String) {
          return;
        }
        onProgress?.call(
          ReconstructionProgress(
            stage: _stage(stageName),
            completed: (message['completed'] as num?)?.toInt() ?? 0,
            total: (message['total'] as num?)?.toInt() ?? 0,
            framesAccepted: (message['framesAccepted'] as num?)?.toInt() ?? 0,
            framesRejected: (message['framesRejected'] as num?)?.toInt() ?? 0,
            detail: message['detail']?.toString() ?? '',
          ),
        );
      } else if (type == 'result' && !completer.isCompleted) {
        final payload = message['result'];
        if (payload is Map) {
          completer.complete(ReconstructionResult.fromJson(Map<String, dynamic>.from(payload)));
        }
      }
    });

    errors.listen((message) {
      if (completer.isCompleted) {
        return;
      }
      final text = message is List && message.isNotEmpty ? message.first.toString() : message.toString();
      completer.complete(
        ReconstructionResult(
          implemented: true,
          success: false,
          stage: ReconstructionStage.failed,
          inputFrameCount: request.originalImagePaths.length,
          framesAccepted: 0,
          framesRejected: 0,
          processingDuration: Duration.zero,
          algorithmName: algorithmName,
          algorithmVersion: algorithmVersion,
          message: 'Reconstruction failed before it could save an image. $text',
          effectiveResolution: ReconstructionResult.notMeasuredResolution,
        ),
      );
    });

    try {
      await Isolate.spawn(
        reconstructionIsolateMain,
        <String, Object?>{
          'reply': receive.sendPort,
          'request': request.toJson(),
        },
        onError: errors.sendPort,
        debugName: 'crystal-scan-reconstruction',
      );
    } catch (error) {
      if (!completer.isCompleted) {
        completer.complete(
          ReconstructionResult(
            implemented: true,
            success: false,
            stage: ReconstructionStage.failed,
            inputFrameCount: request.originalImagePaths.length,
            framesAccepted: 0,
            framesRejected: 0,
            processingDuration: Duration.zero,
            algorithmName: algorithmName,
            algorithmVersion: algorithmVersion,
            message: 'Reconstruction could not be started away from the UI thread. $error',
            effectiveResolution: ReconstructionResult.notMeasuredResolution,
          ),
        );
      }
    }

    try {
      return await completer.future;
    } finally {
      await subscription.cancel();
      receive.close();
      errors.close();
    }
  }
}

Future<void> reconstructionIsolateMain(Map<String, Object?> args) async {
  final reply = args['reply']! as SendPort;
  final incoming = ReceivePort();
  reply.send(incoming.sendPort);
  final cancellation = ReconstructionCancellation();
  incoming.listen((message) {
    if (message == 'cancel') {
      cancellation.cancel();
    }
  });
  try {
    final raw = args['request'];
    final request = ReconstructionRequest.fromJson(
      Map<String, dynamic>.from(raw! as Map),
    );
    final result = await ReconstructionEngine().run(
      request,
      cancellation: cancellation,
      onProgress: (progress) {
        reply.send(<String, Object?>{
          'type': 'progress',
          ...progress.toJson(),
        });
      },
    );
    reply.send(<String, Object?>{
      'type': 'result',
      'result': result.toJson(),
    });
  } catch (error) {
    reply.send(<String, Object?>{
      'type': 'result',
      'result': ReconstructionResult(
        implemented: true,
        success: false,
        stage: ReconstructionStage.failed,
        inputFrameCount: 0,
        framesAccepted: 0,
        framesRejected: 0,
        processingDuration: Duration.zero,
        algorithmName: ReconstructionEngine.denoiseAlgorithm,
        algorithmVersion: ReconstructionEngine.version,
        message: 'Reconstruction failed. $error Original frames were not modified.',
        effectiveResolution: ReconstructionResult.notMeasuredResolution,
      ).toJson(),
    });
  } finally {
    incoming.close();
  }
}

ReconstructionStage _stage(String name) {
  for (final stage in ReconstructionStage.values) {
    if (stage.name == name) {
      return stage;
    }
  }
  return ReconstructionStage.failed;
}
