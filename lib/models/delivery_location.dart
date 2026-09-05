/// A confirmed delivery location.
///
/// `confirmed` is only true once the user explicitly confirms the final
/// location — never from a first GPS fix or map drag alone.
class DeliveryLocation {
  const DeliveryLocation({
    required this.latitude,
    required this.longitude,
    required this.mapsUrl,
    this.confirmed = false,
  });

  final double latitude;
  final double longitude;
  final String mapsUrl;
  final bool confirmed;

  DeliveryLocation copyWith({bool? confirmed}) {
    return DeliveryLocation(
      latitude: latitude,
      longitude: longitude,
      mapsUrl: mapsUrl,
      confirmed: confirmed ?? this.confirmed,
    );
  }

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'mapsUrl': mapsUrl,
        'confirmed': confirmed,
      };

  factory DeliveryLocation.fromJson(Map<String, Object?> json) {
    return DeliveryLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      mapsUrl: json['mapsUrl'] as String? ?? '',
      confirmed: json['confirmed'] as bool? ?? false,
    );
  }
}
