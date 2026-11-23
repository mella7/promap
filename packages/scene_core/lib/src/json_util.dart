/// Helpers for reading JSON with clear error messages, and for comparing
/// JSON-like values.
library;

Map<String, Object?> asMap(Object? value, String what) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$what must be an object');
}

List<Object?> asList(Object? value, String what) {
  if (value is List) return value;
  throw FormatException('$what must be a list');
}

String asString(Object? value, String what) {
  if (value is String) return value;
  throw FormatException('$what must be a string');
}

double asDouble(Object? value, String what) {
  if (value is num) return value.toDouble();
  throw FormatException('$what must be a number');
}

int asInt(Object? value, String what) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  throw FormatException('$what must be a whole number');
}

bool asBool(Object? value, String what) {
  if (value is bool) return value;
  throw FormatException('$what must be true or false');
}

/// True when [value] is made only of JSON types: null, bool, number, string,
/// lists of those, and maps with string keys.
bool isJsonValue(Object? value) {
  if (value == null || value is bool || value is String) return true;
  if (value is num) return value.isFinite;
  if (value is List) return value.every(isJsonValue);
  if (value is Map) {
    return value.keys.every((k) => k is String) &&
        value.values.every(isJsonValue);
  }
  return false;
}

bool deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int deepHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
        value.entries.map((e) => Object.hash(e.key, deepHash(e.value))));
  }
  if (value is List) {
    return Object.hashAll(value.map(deepHash));
  }
  return value.hashCode;
}
