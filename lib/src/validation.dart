/// Dart-side argument checks.
///
/// Dart is the only way into this plugin, so ranges, date shapes and
/// integrality are enforced here and the platform channel is never touched with
/// a value the SDK would have to reject. The native bridges re-check types,
/// blank strings and enum values as a second line of defence; they do not
/// duplicate what lives here.
library;

final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _slashDate = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');

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

double? normalizeLatitude(double? value) {
  if (value == null) return null;
  if (!value.isFinite || value < -90 || value > 90) {
    throw RangeError.value(
        value, 'latitude', 'must be a finite value between -90 and 90');
  }
  return value;
}

double? normalizeLongitude(double? value) {
  if (value == null) return null;
  if (!value.isFinite || value < -180 || value > 180) {
    throw RangeError.value(
        value, 'longitude', 'must be a finite value between -180 and 180');
  }
  return value;
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

/// Normalizes a travel date to the `YYYY-MM-DD` the SDK expects.
///
/// `MM/DD/YYYY` is accepted and rewritten, because it is the format a host app
/// is most likely to already be holding. A blank value clears the date rather
/// than failing. A syntactically valid but non-existent date such as
/// `2026-02-30` is rejected — the pattern alone would let it through, and the
/// SDK would build a booking link for a day that never happens.
String? normalizeDate(String? value, String name) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final iso = _isoDate.firstMatch(trimmed);
  if (iso != null) {
    _requireRealDate(
      year: int.parse(iso.group(1)!),
      month: int.parse(iso.group(2)!),
      day: int.parse(iso.group(3)!),
      name: name,
      original: trimmed,
    );
    return trimmed;
  }

  final slash = _slashDate.firstMatch(trimmed);
  if (slash != null) {
    final month = slash.group(1)!;
    final day = slash.group(2)!;
    final year = slash.group(3)!;
    _requireRealDate(
      year: int.parse(year),
      month: int.parse(month),
      day: int.parse(day),
      name: name,
      original: trimmed,
    );
    return '$year-$month-$day';
  }

  throw ArgumentError.value(
      value, name, 'must use YYYY-MM-DD or MM/DD/YYYY format');
}

void _requireRealDate({
  required int year,
  required int month,
  required int day,
  required String name,
  required String original,
}) {
  // DateTime rolls overflow forward (Feb 30 becomes Mar 2), so a round-trip
  // comparison is what actually catches an impossible date.
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw ArgumentError.value(original, name, 'must be a real calendar date');
  }
}
