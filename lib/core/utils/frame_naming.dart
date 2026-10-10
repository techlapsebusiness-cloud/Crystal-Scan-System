const int frameNumberWidth = 4;

final RegExp _frameNamePattern = RegExp(r'^frame_(\d+)\.jpg$');

/// File name for a 1-based frame index. Frame 1 is `frame_0001.jpg`.
String frameFileName(int frameNumber) {
  if (frameNumber < 1) {
    throw ArgumentError.value(
      frameNumber,
      'frameNumber',
      'Frame numbers start at 1.',
    );
  }
  final digits = frameNumber.toString().padLeft(frameNumberWidth, '0');
  return 'frame_$digits.jpg';
}

/// Parses `frame_0007.jpg` into 7. Returns null for any other name.
int? frameNumberFromName(String name) {
  final match = _frameNamePattern.firstMatch(name);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}
