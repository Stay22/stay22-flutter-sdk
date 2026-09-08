import 'validation.dart';

/// Explicit travel intent handed to the SDK by the host app.
///
/// Every field is optional — supply what the app actually knows. The SDK needs
/// at least one of [address], [hotelName] or a coordinate pair to have a
/// destination to work with; without one, scheduling is skipped.
///
/// Setting a travel context replaces the previous one outright. There is no
/// merge, so omitting a field clears it rather than keeping the old value.
class TravelContext {
  /// City, venue, hotel or formatted location, e.g. `"Paris, France"`.
  final String? address;

  final double? latitude;
  final double? longitude;

  /// Check-in date. Accepts `YYYY-MM-DD` or `MM/DD/YYYY`; stored as the former.
  final String? checkinDate;

  /// Check-out date. Accepts `YYYY-MM-DD` or `MM/DD/YYYY`; stored as the former.
  final String? checkoutDate;

  final String? hotelName;
  final int? adults;
  final int? children;

  /// Throws [ArgumentError] on a malformed date and [RangeError] on an
  /// out-of-range coordinate or a negative guest count, before any of this
  /// reaches the platform channel.
  TravelContext({
    String? address,
    double? latitude,
    double? longitude,
    String? checkinDate,
    String? checkoutDate,
    String? hotelName,
    int? adults,
    int? children,
  })  : address = normalizeOptional(address, 'address'),
        latitude = normalizeLatitude(latitude),
        longitude = normalizeLongitude(longitude),
        checkinDate = normalizeDate(checkinDate, 'checkinDate'),
        checkoutDate = normalizeDate(checkoutDate, 'checkoutDate'),
        hotelName = normalizeOptional(hotelName, 'hotelName'),
        adults = normalizeNonNegativeInt(adults, 'adults'),
        children = normalizeNonNegativeInt(children, 'children');

  Map<String, Object?> toMap() => <String, Object?>{
        if (address != null) 'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (checkinDate != null) 'checkinDate': checkinDate,
        if (checkoutDate != null) 'checkoutDate': checkoutDate,
        if (hotelName != null) 'hotelName': hotelName,
        if (adults != null) 'adults': adults,
        if (children != null) 'children': children,
      };

  @override
  String toString() => 'TravelContext(${toMap()})';
}
