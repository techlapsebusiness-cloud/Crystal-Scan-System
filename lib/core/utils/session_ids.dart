import 'dart:math';

final RegExp _sessionIdPattern = RegExp(
  r'^session_\d{8}_\d{6}_\d{3}_[0-9a-f]{4}$',
);

/// Builds session ids that stay unique even when two captures share a timestamp.
class SessionIds {
  const SessionIds._();

  static bool isValid(String id) => _sessionIdPattern.hasMatch(id);

  static String create({DateTime? now, int? salt}) {
    final time = now ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${time.year.toString().padLeft(4, '0')}'
        '${two(time.month)}'
        '${two(time.day)}'
        '_${two(time.hour)}'
        '${two(time.minute)}'
        '${two(time.second)}'
        '_${time.millisecond.toString().padLeft(3, '0')}';
    final suffix = (salt ?? _nextSalt()).toRadixString(16).padLeft(4, '0');
    return 'session_${stamp}_$suffix';
  }

  static int _nextSalt() {
    try {
      return Random.secure().nextInt(0x10000);
    } on UnsupportedError {
      return Random().nextInt(0x10000);
    }
  }
}
