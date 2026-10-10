DateTime readDateTime(Object? value, String field) {
  if (value is! String) {
    throw FormatException('Expected a timestamp for $field.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Invalid timestamp for $field.');
  }
  return parsed.toUtc();
}

int readInt(Object? value, String field) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected an integer for $field.');
}

int? readOptionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

double? readOptionalDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

String? readOptionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String && value.isEmpty) {
    return null;
  }
  if (value is String) {
    return value;
  }
  return null;
}

bool readBool(Object? value, String field) {
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected a boolean for $field.');
}

List<String> readStringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [for (final item in value) item.toString()];
}

Map<String, Object?> readStringMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}
