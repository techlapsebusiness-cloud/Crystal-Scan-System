import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/errors/app_exception.dart';
import 'package:microscopeapp/core/storage/session_store.dart';
import 'package:microscopeapp/core/utils/paths.dart';
import 'package:microscopeapp/models/frame_record.dart';
import 'package:microscopeapp/models/session_status.dart';

import 'support/tiny_jpeg.dart';

void main() {
  late Directory root;
  late SessionStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crystal_store_');
    store = SessionStore(root);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('creates an empty session with a unique directory', () async {
    final first = await store.createSession(requestedFrameCount: 16);
    final second = await store.createSession(requestedFrameCount: 32);
    expect(first.frames, isEmpty);
    expect(first.status, SessionStatus.preparing);
    expect(first.id, isNot(second.id));
    expect(await Directory(first.directoryPath).exists(), isTrue);
    expect(await Directory(first.framesDirectoryPath).exists(), isTrue);
    expect(await File(joinPath(first.directoryPath, 'session.json')).exists(), isTrue);

    final loaded = await store.load(first.id);
    expect(loaded.frames, isEmpty);
    expect(loaded.requestedFrameCount, 16);
    expect(loaded.savedCount, 0);
    expect(loaded.failedCount, 0);
  });

  test('keeps metadata valid when a temp write is left behind', () async {
    final session = await store.createSession(requestedFrameCount: 16);
    final temporary = File('${session.directoryPath}/session.json.tmp');
    await temporary.writeAsString('{ this is not json');
    final loaded = await store.load(session.id);
    expect(loaded.id, session.id);
    expect(loaded.status, SessionStatus.preparing);
  });

  test('refuses to overwrite an original frame', () async {
    final session = await store.createSession(requestedFrameCount: 16);
    final source = File('${root.path}/source.jpg');
    final bytes = tinyJpeg(width: 20, height: 10);
    await source.writeAsBytes(bytes);

    final first = await store.commitFrame(
      session: session,
      frameNumber: 1,
      sourcePath: source.path,
      capturedAt: DateTime.utc(2026, 10, 10),
    );
    final replacement = File('${root.path}/other.jpg');
    await replacement.writeAsBytes(tinyJpeg(width: 8, height: 8));
    final second = await store.commitFrame(
      session: session,
      frameNumber: 1,
      sourcePath: replacement.path,
      capturedAt: DateTime.utc(2026, 10, 10, 0, 0, 1),
    );

    expect(first.success, isTrue);
    expect(first.fileName, 'frame_0001.jpg');
    expect(first.width, 20);
    expect(first.height, 10);
    expect(first.fileSizeBytes, greaterThan(0));
    expect(second.success, isFalse);
    expect(second.error, contains('overwrite'));
    expect(await File(first.filePath!).readAsBytes(), bytes);
  });

  test('records empty and non-jpeg files as failed frames', () async {
    final session = await store.createSession(requestedFrameCount: 16);
    final empty = File('${root.path}/empty.jpg')..writeAsBytesSync(<int>[]);
    final junk = File('${root.path}/junk.jpg')..writeAsBytesSync(<int>[1, 2, 3, 4]);

    final emptyRecord = await store.commitFrame(
      session: session,
      frameNumber: 2,
      sourcePath: empty.path,
      capturedAt: DateTime.utc(2026, 10, 10),
    );
    final junkRecord = await store.commitFrame(
      session: session,
      frameNumber: 3,
      sourcePath: junk.path,
      capturedAt: DateTime.utc(2026, 10, 10),
    );
    expect(emptyRecord.success, isFalse);
    expect(emptyRecord.fileName, 'frame_0002.jpg');
    expect(junkRecord.success, isFalse);
    expect(junkRecord.error, contains('not a JPEG'));
  });

  test('marks an interrupted session and adopts a frame missing from metadata', () async {
    final session = await store.createSession(requestedFrameCount: 16);
    final orphan = File(joinPath(session.framesDirectoryPath, 'frame_0001.jpg'));
    await orphan.writeAsBytes(tinyJpeg(width: 64, height: 48));
    final changed = await store.markInterruptedSessions();
    final loaded = await store.load(session.id);

    expect(changed, 1);
    expect(loaded.status, SessionStatus.interrupted);
    expect(loaded.savedCount, 1);
    expect(loaded.frames.single.fileName, 'frame_0001.jpg');
    expect(loaded.frames.single.width, 64);
    expect(loaded.frames.single.height, 48);
    expect(loaded.errorMessage, contains('Saved frames were kept'));

    final again = await store.markInterruptedSessions();
    expect(again, 0);
    expect((await store.load(session.id)).frames, hasLength(1));
  });

  test('does not rewrite a finished session during startup recovery', () async {
    final created = await store.createSession(requestedFrameCount: 16);
    await store.save(
      created.copyWith(
        status: SessionStatus.completed,
        frames: [
          FrameRecord(
            frameNumber: 1,
            fileName: 'frame_0001.jpg',
            success: true,
            capturedAt: DateTime.utc(2026, 10, 10),
            filePath: joinPath(created.framesDirectoryPath, 'frame_0001.jpg'),
            fileSizeBytes: 12,
          ),
        ],
      ),
    );
    expect(await store.markInterruptedSessions(), 0);
    final loaded = await store.load(created.id);
    expect(loaded.status, SessionStatus.completed);
    expect(loaded.savedCount, 1);
  });

  test('reports corrupt metadata without deleting the directory', () async {
    final session = await store.createSession(requestedFrameCount: 16);
    await File(joinPath(session.directoryPath, 'session.json')).writeAsString('{');
    final index = await store.loadIndex();
    expect(index.sessions, isEmpty);
    expect(index.unreadablePaths, [session.directoryPath]);
    expect(await Directory(session.directoryPath).exists(), isTrue);
  });

  test('refuses to delete an unexpected session id', () async {
    await expectLater(
      store.deleteSession('../outside'),
      throwsA(isA<SessionDataException>()),
    );
  });
}
