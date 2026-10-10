/// Application-documents subdirectory that holds every capture session.
const String crystalScanSessionsDir = 'crystal_scan/sessions';

String joinPath(String parent, String child) {
  if (parent.isEmpty) {
    return child;
  }
  if (parent.endsWith('/')) {
    return '$parent$child';
  }
  return '$parent/$child';
}

String baseName(String path) {
  var normalized = path;
  if (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final index = normalized.lastIndexOf('/');
  if (index == -1) {
    return normalized;
  }
  return normalized.substring(index + 1);
}

/// True when [candidate] is [root] or a descendant of it.
bool isPathInside(String root, String candidate) {
  final normalRoot = _stripTrailingSlash(root);
  final normalCandidate = _stripTrailingSlash(candidate);
  return normalCandidate == normalRoot ||
      normalCandidate.startsWith('$normalRoot/');
}

String _stripTrailingSlash(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}
