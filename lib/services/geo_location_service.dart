import 'dart:async';

import '../models/delivery_location.dart';
import 'location_failure.dart';

/// Geolocation contract the delivery location flow depends on.
///
/// Deliberately pure Dart (no `dart:js_interop`, no `package:web`): importing
/// this file must never break a plain VM test build. The browser-backed
/// implementation lives in `browser_geo_location_service.dart`.
///
/// Never silently accepts the first GPS fix as final — the caller must
/// explicitly confirm the location ([DeliveryLocation.confirmed]).
abstract class GeoLocationService {
  /// Resolves the device's current position.
  /// Throws [LocationFailure] on permission denial, timeout, unavailability,
  /// or unsupported browser.
  Future<({double lat, double lng})> currentPosition();

  /// Builds a Google Maps deep link for a coordinate.
  static String mapsUrlFor(double lat, double lng) {
    return 'https://www.google.com/maps?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}&z=16';
  }
}
