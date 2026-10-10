import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/features/reconstruction/presentation/reconstruction_screen.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/frame_record.dart';
import 'package:microscopeapp/models/session_status.dart';
import 'package:microscopeapp/services/image_processing_service.dart';

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
}
