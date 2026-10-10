import 'dart:typed_data';

/// A minimal JPEG header with an SOF0 marker. It is not a decodable image;
/// it is enough for dimension parsing and the capture file checks.
Uint8List tinyJpeg({required int width, required int height}) {
  return Uint8List.fromList(<int>[
    0xFF, 0xD8, // SOI
    0xFF, 0xC0, // SOF0
    0x00, 0x0B, // segment length
    0x08, // precision
    (height >> 8) & 0xFF,
    height & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    0x01, 0x01, 0x11, 0x00,
    0xFF, 0xD9, // EOI
  ]);
}
