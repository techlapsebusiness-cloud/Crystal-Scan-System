/// Progress of a capture. [percent] follows frames that were saved, not
/// frames that were merely attempted.
class CaptureProgress {
  const CaptureProgress({
    required this.requested,
    required this.saved,
    required this.failed,
    required this.currentFrame,
    required this.elapsed,
    required this.isRunning,
  });

  final int requested;
  final int saved;
  final int failed;
  final int currentFrame;
  final Duration elapsed;
  final bool isRunning;

  int get attempted => saved + failed;

  double get fraction {
    if (requested <= 0) {
      return 0;
    }
    final value = saved / requested;
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  int get percent => percentFor(saved: saved, requested: requested);

  /// Rounds the saved/requested ratio. Zero stays 0, a finished run is 100,
  /// and a partial run never displays 100.
  static int percentFor({required int saved, required int requested}) {
    if (requested <= 0 || saved <= 0) {
      return 0;
    }
    if (saved >= requested) {
      return 100;
    }
    final rounded = ((saved * 100) / requested).round();
    if (rounded >= 100) {
      return 99;
    }
    if (rounded < 0) {
      return 0;
    }
    return rounded;
  }

  CaptureProgress copyWith({
    int? requested,
    int? saved,
    int? failed,
    int? currentFrame,
    Duration? elapsed,
    bool? isRunning,
  }) {
    return CaptureProgress(
      requested: requested ?? this.requested,
      saved: saved ?? this.saved,
      failed: failed ?? this.failed,
      currentFrame: currentFrame ?? this.currentFrame,
      elapsed: elapsed ?? this.elapsed,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}
