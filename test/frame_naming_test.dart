import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/utils/frame_naming.dart';

void main() {
  test('numbers frames as zero-padded jpeg names', () {
    expect(frameFileName(1), 'frame_0001.jpg');
    expect(frameFileName(2), 'frame_0002.jpg');
    expect(frameFileName(16), 'frame_0016.jpg');
    expect(frameFileName(32), 'frame_0032.jpg');
    expect(frameFileName(64), 'frame_0064.jpg');
    expect(frameFileName(128), 'frame_0128.jpg');
    expect(frameNumberFromName('frame_0007.jpg'), 7);
    expect(frameNumberFromName('frame_0128.jpg'), 128);
    expect(frameNumberFromName('frame_0001.jpeg'), isNull);
    expect(frameNumberFromName('notes.txt'), isNull);
    expect(() => frameFileName(0), throwsArgumentError);
  });
}
