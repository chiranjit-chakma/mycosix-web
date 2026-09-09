import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/delivery_location.dart';
import 'package:mycosix/models/delivery_tier.dart';
import 'package:mycosix/models/site_settings.dart';
import 'package:mycosix/services/delivery_pricing.dart';
import 'package:mycosix/widgets/location/location_math.dart';

/// Tolerance guard: single-expression arithmetic, so anything beyond
/// floating rounding means a wrong formula.
void expectNear(double actual, double expected, {double tol = 1e-6}) {
  expect(
    (actual - expected).abs(),
    lessThan(tol + expected.abs() * 1e-9),
    reason: 'expected $actual near $expected',
  );
}

const shop = DeliveryLocation(
  latitude: 17.385, // Hyderabad — the site's shop point in these tests.
  longitude: 78.4867,
  mapsUrl: 'https://maps.app.goo.gl/x',
  confirmed: true,
);

SiteSettings settings({List<DeliveryTier>? tiers, double? shopLat, double? shopLng}) {
  return SiteSettings(
    deliveryFee: 39,
    shopLatitude: shopLat ?? 17.385,
    shopLongitude: shopLng ?? 78.4867,
    deliveryTiers: tiers ?? const [],
  );
}

void main() {
  group('haversineKm', () {
    test('same point is zero', () {
      expectNear(haversineKm(12.3, 77.6, 12.3, 77.6), 0);
    });

    test('one degree of latitude is ~111.2 km', () {
      expectNear(haversineKm(12.0, 77.0, 13.0, 77.0), 111.195, tol: 0.5);
    });

    test('Hyderabad to Mysore is ~600 km', () {
      expectNear(haversineKm(17.385, 78.4867, 12.2958, 76.6394), 600, tol: 3);
    });
  });

  group('computeDeliveryQuote', () {
    test('flat fallback when the shop/tiers are not configured', () {
      final q = computeDeliveryQuote(
        settings: const SiteSettings(deliveryFee: 39),
        customer: shop,
        fallbackFee: 39,
      );
      expect(q.known, isFalse);
      expect(q.unavailable, isFalse);
      expect(q.fee, 39);
      expect(q.distanceKm, isNull);
    });

    test('flat fallback when no customer pin exists', () {
      final q = computeDeliveryQuote(
        settings: settings(tiers: const [DeliveryTier(upToKm: 2, fee: 0)]),
        customer: null,
        fallbackFee: 39,
      );
      expect(q.known, isFalse);
      expect(q.fee, 39);
    });

    test('inside the first tier is free', () {
      final q = computeDeliveryQuote(
        settings: settings(
          tiers: const [
            DeliveryTier(upToKm: 2, fee: 0),
            DeliveryTier(upToKm: 5, fee: 40),
          ],
        ),
        customer: shop, // pin == shop point
        fallbackFee: 39,
      );
      expect(q.known, isTrue);
      expect(q.unavailable, isFalse);
      expect(q.fee, 0);
      expectNear(q.distanceKm!, 0);
      expect(q.distanceLabel, '0.0 km');
    });

    test('a mid tier sets its fee', () {
      // ~4.8 km west — inside the 5 km tier, beyond the free 2 km tier.
      final customer = DeliveryLocation(
        latitude: 17.385,
        longitude: 78.4867 - 0.045,
        mapsUrl: 'https://maps.app.goo.gl/y',
        confirmed: true,
      );
      final q = computeDeliveryQuote(
        settings: settings(
          tiers: const [
            DeliveryTier(upToKm: 2, fee: 0),
            DeliveryTier(upToKm: 5, fee: 40),
          ],
        ),
        customer: customer,
        fallbackFee: 39,
      );
      expect(q.known, isTrue);
      expect(q.unavailable, isFalse);
      expect(q.fee, 40);
      expectNear(q.distanceKm!, 4.8, tol: 0.1);
    });

    test('beyond the last tier is unavailable', () {
      final q = computeDeliveryQuote(
        settings: settings(
          tiers: const [DeliveryTier(upToKm: 2, fee: 0)],
        ),
        customer: const DeliveryLocation(
          latitude: 22.0,
          longitude: 88.0, // Kolkata, ~1000 km from Hyderabad
          mapsUrl: 'https://maps.app.goo.gl/z',
          confirmed: true,
        ),
        fallbackFee: 39,
      );
      expect(q.known, isTrue);
      expect(q.unavailable, isTrue);
      expect(q.fee, 0); // never charged when unavailable
    });

    test('invalid tiers are skipped (distance can still be unknown)', () {
      final q = computeDeliveryQuote(
        settings: SiteSettings(
          deliveryFee: 39,
          shopLatitude: 17.385,
          shopLongitude: 78.4867,
          deliveryTiers: const [
            DeliveryTier(upToKm: 0, fee: 0), // invalid: km must be > 0
            DeliveryTier(upToKm: 5, fee: 40),
          ],
        ),
        customer: shop,
        fallbackFee: 39,
      );
      expect(q.known, isTrue);
      expect(q.fee, 40);
    });
  });

  group('DeliveryTier', () {
    test('parses and validates', () {
      expect(const DeliveryTier(upToKm: 2, fee: 0).isValid, isTrue);
      expect(const DeliveryTier(upToKm: 0, fee: 0).isValid, isFalse);
      expect(const DeliveryTier(upToKm: 2, fee: -1).isValid, isFalse);
      final t = DeliveryTier.fromMap({'km': 2.5, 'fee': 40});
      expect(t.upToKm, 2.5);
      expect(t.fee, 40);
      expect(DeliveryTier.fromMap(null).isValid, isFalse);
      expect(DeliveryTier.fromMap({'km': 'x'}).isValid, isFalse);
    });
  });

  group('SiteSettings tiers', () {
    test('fromMap drops invalid tiers and sorts ascending', () {
      final s = SiteSettings.fromMap({
        'deliveryTiers': [
          {'km': 10, 'fee': 90},
          {'km': 2, 'fee': 0},
          {'km': 5, 'fee': -5}, // invalid — dropped
          {'km': 'x'},
        ],
      });
      expect(s.deliveryTiers.length, 2);
      expect(s.deliveryTiers[0].upToKm, 2);
      expect(s.deliveryTiers[1].upToKm, 10);
      expect(s.hasDistancePricing, isFalse); // no shop point in the map
    });

    test('hasDistancePricing needs a shop point AND a valid tier', () {
      expect(
        settings(tiers: const [DeliveryTier(upToKm: 5, fee: 40)])
            .hasDistancePricing,
        isTrue,
      );
      expect(
        SiteSettings(
          deliveryFee: 39,
          deliveryTiers: const [DeliveryTier(upToKm: 5, fee: 40)],
        ).hasDistancePricing,
        isFalse,
      );
      expect(
        settings(tiers: const []).hasDistancePricing,
        isFalse,
      );
      expect(settings(tiers: const []).maxDeliveryKm, isNull);
      expect(
        settings(tiers: const [DeliveryTier(upToKm: 5, fee: 40)]).maxDeliveryKm,
        5,
      );
    });
  });
}
