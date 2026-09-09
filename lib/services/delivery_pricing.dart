import '../models/delivery_location.dart';
import '../models/site_settings.dart';
import '../widgets/location/location_math.dart';

/// The delivery charge quoted for a cart, computed from the customer's pin
/// distance to the configured shop point. Pure and unit-testable.
class DeliveryQuote {
  const DeliveryQuote({
    required this.fee,
    this.distanceKm,
    required this.unavailable,
    required this.known,
  });

  /// What delivery costs for this cart (0 = free). Meaningless when
  /// [unavailable] is true.
  final double fee;

  /// Straight-line distance in km from the shop to the pin, when the pricing
  /// is distance-based AND a customer pin exists.
  final double? distanceKm;

  /// True when the pin is beyond every delivery tier — the spot is outside
  /// the delivery area, so an order cannot be placed to it.
  final bool unavailable;

  /// True when the quote is genuinely distance-based (shop point + tiers
  /// configured and a customer pin exists). When false, [fee] is the flat
  /// fallback and the row should read as an estimate.
  final bool known;

  /// A human label for the distance, e.g. "3.4 km" (empty when unknown).
  String get distanceLabel =>
      distanceKm == null ? '' : '${distanceKm!.toStringAsFixed(1)} km';
}

/// The single pricing rule both the site and the order backend implement:
///
///  * No customer pin, or no shop point/tiers configured → the flat fallback
///    fee ([fallbackFee], the legacy `deliveryFee`), marked not `known`.
///  * Otherwise the straight-line distance from the shop to the pin is
///    measured, and the FIRST tier whose `upToKm` covers it sets the fee
///    (0 = free). A distance beyond every tier's `upToKm` is `unavailable`.
///
/// The trusted backend recomputes the same rule from the same
/// `siteConfig/public` document at order time, so the fee the customer sees
/// here is always the fee the backend charges.
DeliveryQuote computeDeliveryQuote({
  required SiteSettings settings,
  DeliveryLocation? customer,
  required double fallbackFee,
}) {
  if (!settings.hasDistancePricing || customer == null) {
    return DeliveryQuote(
      fee: fallbackFee,
      known: false,
      unavailable: false,
    );
  }
  final km = haversineKm(
    settings.shopLatitude!,
    settings.shopLongitude!,
    customer.latitude,
    customer.longitude,
  );
  for (final tier in settings.deliveryTiers) {
    if (!tier.isValid) continue;
    if (km <= tier.upToKm) {
      return DeliveryQuote(
        fee: tier.fee,
        distanceKm: km,
        known: true,
        unavailable: false,
      );
    }
  }
  return DeliveryQuote(
    fee: 0,
    distanceKm: km,
    known: true,
    unavailable: true,
  );
}
