/// Checks for initialization and notification appearance options.
/// Trip and timing business validation belongs to the native lifecycle, including
/// revocation before rejecting an invalid replacement.
library;

/// Trims [value] and rejects a blank result.
String requireNonBlank(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return trimmed;
}

/// Trims [value], mapping null and blank alike to null.
///
/// Blank is treated as absent rather than as an error because clearing an
/// optional field is a legitimate thing to want.
String? normalizeOptional(String? value, String name) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Like [normalizeOptional], but rejects a value that was supplied and blank.
///
/// Used for identifiers the SDK cannot substitute a default for once the caller
/// has opted into setting them.
String? requireOptionalNonBlank(String? value, String name) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank when provided');
  }
  return trimmed;
}

double? normalizeRelevanceScore(double? value) {
  if (value == null) return null;
  if (!value.isFinite || value < 0 || value > 1) {
    throw RangeError.value(
        value, 'relevanceScore', 'must be between 0.0 and 1.0');
  }
  return value;
}

int? normalizeNonNegativeInt(int? value, String name) {
  if (value == null) return null;
  if (value < 0) {
    throw RangeError.value(value, name, 'must not be negative');
  }
  return value;
}
