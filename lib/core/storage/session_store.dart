import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:microscopeapp/core/errors/app_exception.dart';
import 'package:microscopeapp/core/storage/atomic_file.dart';
import 'package:microscopeapp/core/utils/frame_naming.dart';
import 'package:microscopeapp/core/utils/jpeg_dimensions.dart';
import 'package:microscopeapp/core/utils/paths.dart';
import 'package:microscopeapp/core/utils/session_ids.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/frame_record.dart';
import 'package:microscopeapp/models/session_status.dart';

class SessionIndex {
  const SessionIndex({
    required this.sessions,
    required this.unreadablePaths,
  });

  final List<CaptureSession> sessions;
  final List<String> unreadablePaths;
}

/// Stores original frames and `session.json` under
/// `crystal_scan/sessions/<session_id>/`.
class SessionStore {
  SessionStore(Directory directory) : root = Directory(directory.absolute.path);

  final Directory root;

  static Future<SessionStore> openDefault() async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(joinPath(documents.path, crystalScanSessionsDir));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return SessionStore(root);
  }

  Future<CaptureSession> createSession({required int requestedFrameCount}) async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    for (var attempt = 0; attempt < 8; attempt++) {
      final id = SessionIds.create();
      final directory = Directory(joinPath(root.path, id));
      if (await directory.exists()) {
        continue;
      }
      await directory.create(recursive: true);
      final framesDirectory = Directory(joinPath(directory.path, 'frames'));
      await framesDirectory.create();
      final now = DateTime.now().toUtc();
      final session = CaptureSession(
        id: id,
        createdAt: now,
        updatedAt: now,
        status: SessionStatus.preparing,
        requestedFrameCount: requestedFrameCount,
        directoryPath: directory.path,
        framesDirectoryPath: framesDirectory.path,
        elapsed: Duration.zero,
        frames: const [],
      );
      return save(session);
    }
    throw const SessionDataException(
      'Could not allocate a unique session directory.',
    );
  }

  Future<CaptureSession> save(CaptureSession session) async {
    final directory = Directory(session.directoryPath);
    if (!await directory.exists()) {
      throw SessionDataException(
        'Session directory is missing for ${session.id}.',
      );
    }
    final stamped = session.copyWith(updatedAt: DateTime.now().toUtc());
    final file = File(joinPath(directory.path, 'session.json'));
    final payload = const JsonEncoder.withIndent('  ').convert(stamped.toJson());
    await writeStringAtomic(file, '$payload\n');
    return stamped;
  }

  Future<CaptureSession> load(String id) async {
    final directory = _directoryFor(id);
    final file = File(joinPath(directory.path, 'session.json'));
    if (!await file.exists()) {
      throw SessionDataException('Session $id has no metadata file.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Session metadata is not an object.');
    }
    return CaptureSession.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<SessionIndex> loadIndex() async {
    if (!await root.exists()) {
      return const SessionIndex(sessions: [], unreadablePaths: []);
    }
    final sessions = <CaptureSession>[];
    final unreadable = <String>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) {
        continue;
      }
      final name = baseName(entity.path);
      if (!SessionIds.isValid(name)) {
        unreadable.add(entity.path);
        continue;
      }
      try {
        sessions.add(await load(name));
      } on FormatException {
        unreadable.add(entity.path);
      } on SessionDataException {
        unreadable.add(entity.path);
      }
    }
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return SessionIndex(sessions: sessions, unreadablePaths: unreadable);
  }

  /// Marks sessions left in `preparing` or `capturing` as interrupted.
  ///
  /// Also adopts a JPEG that was copied into `frames/` but not yet written
  /// into `session.json`, which is the window where a crash can occur.
  Future<int> markInterruptedSessions() async {
    final index = await loadIndex();
    var updated = 0;
    for (final session in index.sessions) {
      if (session.status != SessionStatus.preparing &&
          session.status != SessionStatus.capturing) {
        continue;
      }
      final withOrphans = await _adoptOrphanFrames(session);
      final interrupted = withOrphans.copyWith(
        status: SessionStatus.interrupted,
        completedAt: withOrphans.completedAt ?? DateTime.now().toUtc(),
        errorMessage:
            withOrphans.errorMessage ??
            'The capture stopped before it finished. Saved frames were kept.',
      );
      await save(interrupted);
      updated++;
    }
    return updated;
  }

  Future<void> deleteSession(String id) async {
    final directory = _directoryFor(id);
    if (!isPathInside(root.path, directory.path)) {
      throw const SessionDataException('Session path is outside storage.');
    }
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Copies a captured file into the session and verifies it.
  ///
  /// Never overwrites an existing frame file. Returns a failure record when
  /// the file is missing, empty, or not a JPEG.
  Future<FrameRecord> commitFrame({
    required CaptureSession session,
    required int frameNumber,
    required String sourcePath,
    required DateTime capturedAt,
    String? focusMode,
    String? exposureMode,
    String? flashMode,
    double? exposureOffset,
  }) async {
    final fileName = frameFileName(frameNumber);
    final framesDirectory = Directory(session.framesDirectoryPath);
    try {
      if (!await framesDirectory.exists()) {
        await framesDirectory.create(recursive: true);
      }
    } on FileSystemException catch (error) {
      throw SessionDataException(
        'Could not create the frames directory.',
        cause: error,
      );
    }

    final destination = File(joinPath(framesDirectory.path, fileName));
    if (await destination.exists()) {
      return FrameRecord.failure(
        frameNumber: frameNumber,
        capturedAt: capturedAt,
        fileName: fileName,
        filePath: destination.path,
        error: 'Refusing to overwrite an existing original frame.',
      );
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      return FrameRecord.failure(
        frameNumber: frameNumber,
        capturedAt: capturedAt,
        fileName: fileName,
        error: 'The captured file was missing.',
      );
    }

    try {
      await copyFile(source, destination);
    } on FileSystemException catch (error) {
      throw SessionDataException(
        'Could not write the frame to storage.',
        cause: error,
      );
    }

    final size = await destination.length();
    if (size <= 0) {
      return FrameRecord.failure(
        frameNumber: frameNumber,
        capturedAt: capturedAt,
        fileName: fileName,
        filePath: destination.path,
        fileSizeBytes: size,
        error: 'The saved file was empty.',
      );
    }

    final header = await readFilePrefix(destination, 2);
    if (!looksLikeJpeg(header)) {
      return FrameRecord.failure(
        frameNumber: frameNumber,
        capturedAt: capturedAt,
        fileName: fileName,
        filePath: destination.path,
        fileSizeBytes: size,
        error: 'The saved file is not a JPEG.',
      );
    }

    final dimensions = await readJpegSizeFromFile(destination);
    return FrameRecord(
      frameNumber: frameNumber,
      fileName: fileName,
      filePath: destination.path,
      fileSizeBytes: size,
      width: dimensions?.width,
      height: dimensions?.height,
      success: true,
      capturedAt: capturedAt,
      focusMode: focusMode,
      exposureMode: exposureMode,
      flashMode: flashMode,
      exposureOffset: exposureOffset,
    );
  }

  Directory _directoryFor(String id) {
    if (!SessionIds.isValid(id)) {
      throw const SessionDataException('Refusing an unexpected session id.');
    }
    return Directory(joinPath(root.path, id));
  }

  Future<CaptureSession> _adoptOrphanFrames(CaptureSession session) async {
    final directory = Directory(session.framesDirectoryPath);
    if (!await directory.exists()) {
      return session;
    }
    final known = session.frames.map((frame) => frame.fileName).toSet();
    final adopted = <FrameRecord>[];
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = baseName(entity.path);
      final number = frameNumberFromName(name);
      if (number == null || known.contains(name)) {
        continue;
      }
      final size = await entity.length();
      final header = await readFilePrefix(entity, 2);
      if (size <= 0 || !looksLikeJpeg(header)) {
        continue;
      }
      final dimensions = await readJpegSizeFromFile(entity);
      final modified = (await entity.stat()).modified.toUtc();
      adopted.add(
        FrameRecord(
          frameNumber: number,
          fileName: name,
          filePath: entity.path,
          fileSizeBytes: size,
          width: dimensions?.width,
          height: dimensions?.height,
          success: true,
          capturedAt: modified,
        ),
      );
    }
    if (adopted.isEmpty) {
      return session;
    }
    adopted.sort((a, b) => a.frameNumber.compareTo(b.frameNumber));
    return session.copyWith(frames: [...session.frames, ...adopted]);
  }
}
