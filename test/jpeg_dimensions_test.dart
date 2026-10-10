import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/utils/jpeg_dimensions.dart';

import 'support/tiny_jpeg.dart';

void main() {
  test('reads dimensions and skips a marker before SOF', () {
    final simple = tinyJpeg(width: 32, height: 16);
    final size = readJpegSize(simple);
    expect(size?.width, 32);
    expect(size?.height, 16);

    final withApp0 = Uint8List.fromList(<int>[
      0xFF, 0xD8,
      0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46,
      ...simple.sublist(2),
    ]);
    final skipped = readJpegSize(withApp0);
    expect(skipped?.width, 32);
    expect(skipped?.height, 16);
  });

  test('rejects bytes that are not a jpeg', () {
    expect(readJpegSize(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
    expect(readJpegSize(Uint8List(0)), isNull);
    expect(looksLikeJpeg(Uint8List.fromList(<int>[0xFF, 0xD8])), isTrue);
    expect(looksLikeJpeg(Uint8List.fromList(<int>[0x00, 0x00])), isFalse);
  });
}
