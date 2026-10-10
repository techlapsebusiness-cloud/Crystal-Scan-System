import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/features/capture/presentation/widgets/capture_progress_panel.dart';
import 'package:microscopeapp/models/capture_progress.dart';

void main() {
  testWidgets('shows saved-frame progress, the current frame, and elapsed time', (
    tester,
  ) async {
    const progress = CaptureProgress(
      requested: 32,
      saved: 8,
      failed: 1,
      currentFrame: 9,
      elapsed: Duration(seconds: 5),
      isRunning: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCrystalTheme(),
        home: const Scaffold(
          body: CaptureProgressPanel(progress: progress, stopping: true),
        ),
      ),
    );

    expect(find.text('25%'), findsOneWidget);
    expect(find.text('8 / 32 saved'), findsOneWidget);
    expect(find.text('Frame 9 of 32 · Failed 1'), findsOneWidget);
    expect(find.text('00:05'), findsOneWidget);
    expect(find.text('Finishing the current frame…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.25);
  });
}
