enum SessionStatus {
  preparing,
  capturing,
  completed,
  cancelled,
  failed,
  interrupted,
}

SessionStatus sessionStatusFromName(String name) {
  for (final status in SessionStatus.values) {
    if (status.name == name) {
      return status;
    }
  }
  throw FormatException('Unknown session status: $name');
}

String sessionStatusLabel(SessionStatus status) {
  switch (status) {
    case SessionStatus.preparing:
      return 'Preparing';
    case SessionStatus.capturing:
      return 'Capturing';
    case SessionStatus.completed:
      return 'Completed';
    case SessionStatus.cancelled:
      return 'Cancelled';
    case SessionStatus.failed:
      return 'Failed';
    case SessionStatus.interrupted:
      return 'Interrupted';
  }
}
