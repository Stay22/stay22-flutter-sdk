/// One complete trip snapshot. Omitted fields never inherit a previous notification.
///
/// Native code owns trip validation and normalization, including rejected replacement
/// effects. Constructing this value does not issue or reject a notification command.
final class TravelContext {
  final String? address;
  final double? latitude;
  final double? longitude;

  /// A supported travel date string; native code normalizes it when capturing a request.
  final String? checkinDate;
  final String? checkoutDate;
  final String? hotelName;
  final int? adults;
  final int? children;

  /// Additional trip facts, copied so later caller mutations cannot change this snapshot.
  final Map<String, String>? context;

  TravelContext(
      {this.address,
      this.latitude,
      this.longitude,
      this.checkinDate,
      this.checkoutDate,
      this.hotelName,
      this.adults,
      this.children,
      Map<String, String>? context})
      : context = context == null ? null : Map.unmodifiable(context);

  Map<String, Object?> toMap() => {
        if (address != null) 'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (checkinDate != null) 'checkinDate': checkinDate,
        if (checkoutDate != null) 'checkoutDate': checkoutDate,
        if (hotelName != null) 'hotelName': hotelName,
        if (adults != null) 'adults': adults,
        if (children != null) 'children': children,
        if (context != null) 'context': context,
      };

  @override
  String toString() => 'TravelContext(${toMap()})';
}
