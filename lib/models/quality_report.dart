/// Optional quality measurement. Version 1 does not calibrate or apply one,
/// and capture never rejects a frame from this report.
class QualityReport {
  const QualityReport({
    required this.imagePath,
    required this.calibrated,
    this.notes = const [],
    this.metrics = const {},
  });

  final String imagePath;
  final bool calibrated;
  final List<String> notes;
  final Map<String, Object?> metrics;
}
