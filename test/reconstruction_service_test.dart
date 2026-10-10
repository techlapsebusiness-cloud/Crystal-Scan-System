import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/services/image_alignment_service.dart';
import 'package:microscopeapp/services/image_processing_service.dart';
import 'package:microscopeapp/services/image_quality_service.dart';
import 'package:microscopeapp/services/unavailable_reconstruction_service.dart';

class _RecordingAlignment implements ImageAlignmentService {
  var calls = 0;

  @override
  bool get isAvailable => false;

  @override
  Future<void> align(List<String> framePaths) async {
    calls += 1;
    throw UnsupportedError('alignment was called');
  }
}

void main() {
  test('the unavailable engine does not fabricate an image', () async {
    final directory = await Directory.systemTemp.createTemp('crystal_reconstruct_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final alignment = _RecordingAlignment();
    final processing = ImageProcessingService(
      alignment: alignment,
      superResolution: const UnavailableSuperResolutionService(),
      quality: const UncalibratedQualityService(),
    );
    final output = '${directory.path}/output';
    final missingOriginal = '${directory.path}/frame_0001.jpg';

    final result = await processing.reconstruct(
      ReconstructionRequest(
        sessionId: 'session_20261010_200301_482_ab12',
        originalImagePaths: [missingOriginal, '${directory.path}/frame_0002.jpg'],
        outputDirectory: output,
      ),
    );

    expect(processing.isAvailable, isFalse);
    expect(alignment.calls, 0);
    expect(result.implemented, isFalse);
    expect(result.success, isFalse);
    expect(result.stage, ReconstructionStage.unavailable);
    expect(result.outputFilePath, isNull);
    expect(result.outputWidth, isNull);
    expect(result.outputHeight, isNull);
    expect(result.inputFrameCount, 2);
    expect(result.framesAccepted, 0);
    expect(result.framesRejected, 0);
    expect(result.algorithmName, 'unavailable');
    expect(result.algorithmVersion, '0');
    expect(result.message, contains('not implemented'));
    expect(result.effectiveResolution, contains('Not measured'));
    expect(result.qualityMetrics, isEmpty);
    expect(Directory(output).existsSync(), isFalse);
    expect(File(missingOriginal).existsSync(), isFalse);

    final restored = ReconstructionResult.fromJson(result.toJson());
    expect(restored.implemented, isFalse);
    expect(restored.outputFilePath, isNull);
    expect(restored.stage, ReconstructionStage.unavailable);

    expect(await processing.quality.analyze(missingOriginal), isNull);
  });
}
