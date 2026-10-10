import 'dart:io';
import 'dart:typed_data';

class JpegSize {
  const JpegSize(this.width, this.height);

  final int width;
  final int height;
}

/// Reads width and height from a JPEG SOF marker.
///
/// Returns null when the bytes are not a JPEG or the header is truncated.
/// This does not decode pixel data.
JpegSize? readJpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  var index = 2;
  while (index + 1 < bytes.length) {
    if (bytes[index] != 0xFF) {
      return null;
    }
    while (index < bytes.length && bytes[index] == 0xFF) {
      index++;
    }
    if (index >= bytes.length) {
      return null;
    }
    final marker = bytes[index];
    index++;
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (index + 1 >= bytes.length) {
      return null;
    }
    final segmentLength = (bytes[index] << 8) | bytes[index + 1];
    if (segmentLength < 2 || index + segmentLength > bytes.length) {
      return null;
    }
    if (_isStartOfFrame(marker)) {
      if (segmentLength < 7) {
        return null;
      }
      final height = (bytes[index + 3] << 8) | bytes[index + 4];
      final width = (bytes[index + 5] << 8) | bytes[index + 6];
      if (width <= 0 || height <= 0) {
        return null;
      }
      return JpegSize(width, height);
    }
    if (marker == 0xDA) {
      return null;
    }
    index += segmentLength;
  }
  return null;
}

Future<JpegSize?> readJpegSizeFromFile(File file) async {
  final prefix = await readFilePrefix(file, 262144);
  return readJpegSize(prefix);
}

Future<Uint8List> readFilePrefix(File file, int count) async {
  final handle = await file.open();
  try {
    final length = await handle.length();
    final toRead = length < count ? length : count;
    if (toRead <= 0) {
      return Uint8List(0);
    }
    return await handle.read(toRead);
  } finally {
    await handle.close();
  }
}

bool looksLikeJpeg(Uint8List header) {
  return header.length >= 2 && header[0] == 0xFF && header[1] == 0xD8;
}

bool _isStartOfFrame(int marker) {
  return marker >= 0xC0 &&
      marker <= 0xCF &&
      marker != 0xC4 &&
      marker != 0xC8 &&
      marker != 0xCC;
}
