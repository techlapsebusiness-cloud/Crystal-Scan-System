import 'package:microscopeapp/models/quality_report.dart';

/// Optional quality analysis. It is not calibrated and is not used to reject
/// captured frames.
abstract class ImageQualityService {
  bool get isCalibrated;

  /// Returns null when no calibrated measurement is available.
  Future<QualityReport?> analyze(String imagePath);
}

class UncalibratedQualityService implements ImageQualityService {
  const UncalibratedQualityService();

  @override
  bool get isCalibrated => false;

  @override
  Future<QualityReport?> analyze(String imagePath) async => null;
}
