import 'dart:io';
import 'dart:typed_data';

/// Writes [contents] by flushing a sibling temp file and then renaming it.
///
/// A crash during the write leaves the previous target file intact.
Future<void> writeStringAtomic(File target, String contents) async {
  final temporary = File('${target.path}.tmp');
  final sink = temporary.openWrite();
  try {
    sink.write(contents);
    await sink.flush();
  } catch (error) {
    await sink.close();
    if (await temporary.exists()) {
      await temporary.delete();
    }
    rethrow;
  }
  await sink.close();
  try {
    await temporary.rename(target.path);
  } on FileSystemException {
    if (await target.exists()) {
      await target.delete();
    }
    await temporary.rename(target.path);
  }
}

/// Writes [bytes] by flushing a sibling temp file and then renaming it.
Future<void> writeBytesAtomic(File target, Uint8List bytes) async {
  final temporary = File('${target.path}.tmp');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
  } catch (error) {
    if (await temporary.exists()) {
      await temporary.delete();
    }
    rethrow;
  }
  try {
    await temporary.rename(target.path);
  } on FileSystemException {
    if (await target.exists()) {
      await target.delete();
    }
    await temporary.rename(target.path);
  }
}

/// Copies [source] to [destination] without loading the whole file into memory.
///
/// Deletes a partial destination if the copy fails.
Future<void> copyFile(File source, File destination) async {
  final output = destination.openWrite();
  try {
    await source.openRead().pipe(output);
  } catch (error) {
    try {
      await output.close();
    } catch (_) {
      // The pipe may already have closed the sink.
    }
    if (await destination.exists()) {
      await destination.delete();
    }
    rethrow;
  }
}
