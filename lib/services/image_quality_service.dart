import 'package:microscopeapp/features/reconstruction/data/frame_inspection.dart';
import 'package:microscopeapp/models/quality_report.dart';

/// Optional quality analysis. Capture never rejects a frame from this report.
abstract class ImageQualityService {
  bool get isCalibrated;

  /// Returns null when this service does not measure the file.
  ///
  /// A statistical report may still be returned with
  /// [QualityReport.calibrated] set to false. That is not an optical calibration.
  Future<QualityReport?> analyze(String imagePath);
}

class UncalibratedQualityService implements ImageQualityService {
  const UncalibratedQualityService();

  @override
  bool get isCalibrated => false;

  @override
  Future<QualityReport?> analyze(String imagePath) async => null;
}

/// Statistical measurements used by the local reconstruction engine.
///
/// [isCalibrated] stays false: blur, exposure, and texture are evidence for
/// frame selection, not a measurement of optical resolution.
class LocalQualityService implements ImageQualityService {
  const LocalQualityService();

  @override
  bool get isCalibrated => false;

  @override
  Future<QualityReport?> analyze(String imagePath) async {
    final inspection = await inspectFrame(imagePath);
    return QualityReport(
      imagePath: imagePath,
      calibrated: false,
      notes: [
        if (inspection.rejectionReason != null) inspection.rejectionReason!,
        'Statistical measurements only. Effective optical resolution was not independently validated.',
      ],
      metrics: {
        'width': inspection.imageWidth,
        'height': inspection.imageHeight,
        'fileSizeBytes': inspection.fileSizeBytes,
        'sharpness': inspection.sharpness,
        'meanLuminance': inspection.meanLuminance,
        'highlightClip': inspection.highlightClip,
        'shadowClip': inspection.shadowClip,
        'texture': inspection.texture,
        'channels': inspection.channels,
      },
    );
  }
}
