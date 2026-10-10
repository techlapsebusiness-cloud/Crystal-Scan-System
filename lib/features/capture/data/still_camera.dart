import 'package:microscopeapp/models/camera_setup.dart';

class CapturedShot {
  const CapturedShot({
    required this.path,
    this.focusMode,
    this.exposureMode,
    this.flashMode,
    this.exposureOffset,
  });

  final String path;
  final String? focusMode;
  final String? exposureMode;
  final String? flashMode;

  /// Null when the camera plugin cannot read exposure compensation without
  /// changing it. Crystal Scan does not change it.
  final double? exposureOffset;
}

/// A camera that can take one still image at a time.
///
/// The preview owner keeps this object alive. [CaptureService] does not
/// dispose it.
abstract class StillCamera {
  bool get isReady;

  bool get isTakingPicture;

  Future<CameraSetup> prepareStableCapture();

  Future<CapturedShot> takePicture();
}
