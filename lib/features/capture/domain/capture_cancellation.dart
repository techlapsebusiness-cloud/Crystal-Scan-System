/// Cancellation checked between frames. An in-flight shutter call is allowed
/// to finish, and that frame is still saved.
class CaptureCancellation {
  bool _cancelled = false;
  bool _interrupted = false;

  bool get isCancelled => _cancelled;

  bool get isInterrupted => _interrupted;

  bool get isStopRequested => _cancelled || _interrupted;

  void cancel() {
    _cancelled = true;
  }

  void interrupt() {
    _interrupted = true;
  }
}
