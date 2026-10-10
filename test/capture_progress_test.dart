import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/utils/formatters.dart';
import 'package:microscopeapp/models/capture_progress.dart';

void main() {
  test('percentage follows saved frames and never shows 100 early', () {
    expect(CaptureProgress.percentFor(saved: 0, requested: 16), 0);
    expect(CaptureProgress.percentFor(saved: 8, requested: 32), 25);
    expect(CaptureProgress.percentFor(saved: 1, requested: 128), 1);
    expect(CaptureProgress.percentFor(saved: 127, requested: 128), 99);
    expect(CaptureProgress.percentFor(saved: 128, requested: 128), 100);
    expect(CaptureProgress.percentFor(saved: 0, requested: 0), 0);
    expect(CaptureProgress.percentFor(saved: 4, requested: 0), 0);

    const partial = CaptureProgress(
      requested: 32,
      saved: 8,
      failed: 2,
      currentFrame: 10,
      elapsed: Duration(seconds: 4),
      isRunning: true,
    );
    expect(partial.percent, 25);
    expect(partial.fraction, 0.25);
    expect(partial.attempted, 10);
  });

  test('formats elapsed time for the capture panel', () {
    expect(formatDuration(Duration.zero), '00:00');
    expect(formatDuration(const Duration(seconds: 5)), '00:05');
    expect(formatDuration(const Duration(seconds: 65)), '01:05');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
  });
}
