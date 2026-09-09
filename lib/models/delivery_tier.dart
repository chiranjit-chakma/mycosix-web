/// One delivery-price band: a fee charged for any delivery point within
/// [upToKm] straight-line kilometres of the shop location.
///
/// Tiers are kept in ascending order of distance. A fee of 0 means free
/// delivery in that band; anything beyond the LAST tier's `upToKm` is simply
/// unavailable (the order is refused with a clear "too far" message). This is
/// the model for "below 2 km free, 5 km ₹40, or unavailable" — the admin sets
/// tiers like [{2, ₹0}, {5, ₹40}] and delivery ends at 5 km.
class DeliveryTier {
  const DeliveryTier({required this.upToKm, required this.fee});

  final double upToKm;
  final double fee;

  /// Sort key for ascending tiers; the fee is never negative.
  bool get isValid => upToKm > 0 && fee >= 0;

  Map<String, Object?> toMap() => {'km': upToKm, 'fee': fee};

  factory DeliveryTier.fromMap(Object? raw) {
    if (raw is! Map) return const DeliveryTier(upToKm: 0, fee: 0);
    final km = raw['km'];
    final fee = raw['fee'];
    // A malformed entry (wrong type, missing key) becomes an invalid tier
    // rather than throwing: the site must keep working off a bad document,
    // and the "drop invalid" contract in SiteSettings holds.
    if (km is! num || fee is! num) {
      return const DeliveryTier(upToKm: 0, fee: 0);
    }
    return DeliveryTier(upToKm: km.toDouble(), fee: fee.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is DeliveryTier && other.upToKm == upToKm && other.fee == fee;

  @override
  int get hashCode => Object.hash(upToKm, fee);

  @override
  String toString() => 'DeliveryTier(≤${upToKm}km → ₹$fee)';
}
