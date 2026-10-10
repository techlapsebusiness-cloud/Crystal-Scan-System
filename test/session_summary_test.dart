import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/features/sessions/presentation/session_summary_screen.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/session_status.dart';

void main() {
  testWidgets('summary shows bookkeeping on a phone-sized layout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final created = DateTime.utc(2026, 10, 10, 12);
    final session = CaptureSession(
      id: 'session_20261010_120000_000_abcd',
      createdAt: created,
      updatedAt: created,
      status: SessionStatus.cancelled,
      requestedFrameCount: 32,
      directoryPath: '/data/user/0/crystal/sessions/session_20261010_120000_000_abcd',
      framesDirectoryPath:
          '/data/user/0/crystal/sessions/session_20261010_120000_000_abcd/frames',
      elapsed: const Duration(seconds: 12),
      frames: const [],
      errorMessage: 'The capture was cancelled.',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCrystalTheme(),
        home: SessionSummaryScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('32'), findsNWidgets(2));
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('00:12'), findsOneWidget);
    expect(find.text('No frames were saved.'), findsOneWidget);
    expect(find.text('The capture was cancelled.'), findsOneWidget);
    expect(find.text('Recapture'), findsOneWidget);
    expect(find.text('Delete session'), findsOneWidget);
    expect(find.text('Continue to reconstruction'), findsOneWidget);
  });
}
