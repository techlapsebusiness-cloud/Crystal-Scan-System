import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/features/reconstruction/presentation/reconstruction_screen.dart';
import 'package:microscopeapp/features/results/presentation/results_screen.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/frame_record.dart';
import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/models/session_status.dart';
import 'package:microscopeapp/services/image_alignment_service.dart';
import 'package:microscopeapp/services/image_processing_service.dart';
import 'package:microscopeapp/services/image_quality_service.dart';
import 'package:microscopeapp/services/super_resolution_service.dart';

void main() {
  testWidgets('says reconstruction is not implemented and does not show progress', (
    tester,
  ) async {
    final created = DateTime.utc(2026, 10, 10);
    final session = CaptureSession(
      id: 'session_20261010_200301_482_ab12',
      createdAt: created,
      updatedAt: created,
      status: SessionStatus.completed,
      requestedFrameCount: 16,
      directoryPath: '/tmp/crystal_session',
      framesDirectoryPath: '/tmp/crystal_session/frames',
      elapsed: const Duration(seconds: 3),
      frames: [
        FrameRecord(
          frameNumber: 1,
          fileName: 'frame_0001.jpg',
          filePath: '/tmp/crystal_session/frames/frame_0001.jpg',
          success: true,
          capturedAt: created,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCrystalTheme(),
        home: ReconstructionScreen(
          session: session,
          processing: ImageProcessingService.unavailable(),
        ),
      ),
    );

    expect(find.text('Not started'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);

    await tester.tap(find.text('Run reconstruction'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not implemented'), findsWidgets);
    expect(find.text('Not implemented'), findsOneWidget);
    expect(find.textContaining('Not measured'), findsOneWidget);
    expect(find.textContaining('Not available'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.text('Engine: unavailable 0'), findsOneWidget);
  });

  testWidgets('does not offer reconstruction when nothing was saved', (tester) async {
    final created = DateTime.utc(2026, 10, 10);
    final session = CaptureSession(
      id: 'session_20261010_200301_482_ab12',
      createdAt: created,
      updatedAt: created,
      status: SessionStatus.cancelled,
      requestedFrameCount: 16,
      directoryPath: '/tmp/crystal_session',
      framesDirectoryPath: '/tmp/crystal_session/frames',
      elapsed: Duration.zero,
      frames: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCrystalTheme(),
        home: ReconstructionScreen(
          session: session,
          processing: ImageProcessingService.unavailable(),
        ),
      ),
    );

    expect(find.text('No saved frames'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'No saved frames'));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows real progress and opens the saved result', (tester) async {
    final directory = Directory.systemTemp.createTempSync('crystal_ui_');
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final processing = ImageProcessingService(
      alignment: const UnavailableAlignmentService(),
      superResolution: _ScriptedEngine(),
      quality: const UncalibratedQualityService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCrystalTheme(),
        home: ReconstructionScreen(
          session: _session('${directory.path}/session'),
          processing: processing,
        ),
      ),
    );

    await tester.tap(find.text('Run reconstruction'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Native-resolution'), findsWidgets);
    expect(find.text('Export TIFF'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Export TIFF'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.textContaining('TIFF saved'), findsWidgets);
  });

  testWidgets('results screen can share or explain that sharing is unavailable', (tester) async {
    final directory = Directory.systemTemp.createTempSync('crystal_result_');
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final original = File('${directory.path}/frame.png');
    final reconstructed = File('${directory.path}/denoised.png');
    final bytes = img.encodePng(img.Image(width: 4, height: 4, numChannels: 3));
    original.writeAsBytesSync(bytes);
    reconstructed.writeAsBytesSync(bytes);
    final result = ReconstructionResult(
      implemented: true,
      success: true,
      stage: ReconstructionStage.completed,
      outputFilePath: reconstructed.path,
      outputWidth: 4,
      outputHeight: 4,
      inputFrameCount: 2,
      framesAccepted: 2,
      framesRejected: 0,
      processingDuration: const Duration(milliseconds: 12),
      algorithmName: 'weighted-robust-average',
      algorithmVersion: '1',
      message: 'Combined 2 of 2 frames.',
      effectiveResolution:
          'Output file is 4×4 pixels at the input sampling grid. Effective optical resolution was not independently validated.',
      strategy: 'multi-frame-denoise',
      referenceFramePath: original.path,
      inputWidth: 4,
      inputHeight: 4,
      denoisedFilePath: reconstructed.path,
      superResolutionPerformed: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCrystalTheme(),
        home: ResultsScreen(sessionId: 'session_20261010_200301_482_ab12', result: result),
      ),
    );
    expect(find.textContaining('Native-resolution'), findsOneWidget);
    expect(find.text('4×4 pixels'), findsWidgets);

    await tester.tap(find.byTooltip('Fit to screen'));
    await tester.pump();

    await tester.drag(find.byType(Slider), const Offset(40, 0));
    await tester.pump();

    await tester.tap(find.text('Share'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}

CaptureSession _session(String directory) {
  final created = DateTime.utc(2026, 10, 10);
  return CaptureSession(
    id: 'session_20261010_200301_482_ab12',
    createdAt: created,
    updatedAt: created,
    status: SessionStatus.completed,
    requestedFrameCount: 16,
    directoryPath: directory,
    framesDirectoryPath: '$directory/frames',
    elapsed: const Duration(seconds: 3),
    frames: [
      FrameRecord(
        frameNumber: 1,
        fileName: 'frame_0001.jpg',
        filePath: '$directory/frames/frame_0001.jpg',
        success: true,
        capturedAt: created,
      ),
    ],
  );
}

class _ScriptedEngine implements SuperResolutionService {
  @override
  String get algorithmName => 'weighted-robust-average';

  @override
  String get algorithmVersion => '1';

  @override
  bool get isAvailable => true;

  @override
  Future<ReconstructionResult> reconstruct(
    ReconstructionRequest request, {
    void Function(ReconstructionProgress progress)? onProgress,
    ReconstructionCancellation? cancellation,
  }) async {
    onProgress?.call(
      const ReconstructionProgress(
        stage: ReconstructionStage.analyzing,
        completed: 1,
        total: 2,
        framesAccepted: 0,
        framesRejected: 0,
        detail: 'Measuring frame 1 of 2.',
      ),
    );
    final directory = Directory(request.outputDirectory);
    directory.createSync(recursive: true);
    final output = File('${directory.path}/denoised.png');
    output.writeAsBytesSync(img.encodePng(img.Image(width: 2, height: 2, numChannels: 3)));
    return ReconstructionResult(
      implemented: true,
      success: true,
      stage: ReconstructionStage.completed,
      outputFilePath: output.path,
      outputWidth: 2,
      outputHeight: 2,
      inputFrameCount: request.originalImagePaths.length,
      framesAccepted: 1,
      framesRejected: 0,
      processingDuration: const Duration(milliseconds: 4),
      algorithmName: algorithmName,
      algorithmVersion: algorithmVersion,
      message: 'Combined 1 of 1 frames at native resolution.',
      effectiveResolution:
          'Output file is 2×2 pixels at the input sampling grid. Effective optical resolution was not independently validated.',
      superResolutionPerformed: false,
      strategy: 'multi-frame-denoise',
      referenceFramePath: request.originalImagePaths.isEmpty ? null : request.originalImagePaths.first,
      inputWidth: 2,
      inputHeight: 2,
      denoisedFilePath: output.path,
    );
  }
}
