import 'package:flutter_test/flutter_test.dart';
import 'package:microscopeapp/core/utils/session_ids.dart';

void main() {
  test('session ids are unique for the same timestamp', () {
    final now = DateTime(2026, 10, 10, 20, 3, 1, 482);
    final first = SessionIds.create(now: now, salt: 0x0A3F);
    final second = SessionIds.create(now: now, salt: 0x0A40);
    expect(first, 'session_20261010_200301_482_0a3f');
    expect(second, isNot(first));
    expect(SessionIds.isValid(first), isTrue);
    expect(SessionIds.isValid(second), isTrue);
    expect(SessionIds.isValid('../crystal_scan'), isFalse);
    expect(SessionIds.isValid('session_20261010_200301_482_A3F1'), isFalse);

    final generated = <String>{};
    for (var salt = 0; salt < 200; salt++) {
      generated.add(SessionIds.create(now: now, salt: salt));
    }
    expect(generated, hasLength(200));
  });
}
