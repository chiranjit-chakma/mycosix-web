import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/delivery_location.dart';
import 'location_failure.dart';

/// Browser geolocation wrapper.
///
/// Never silently accepts the first GPS fix as final — the caller must
/// explicitly confirm the location ([DeliveryLocation.confirmed]).
abstract class GeoLocationService {
  /// Resolves the device's current position.
  /// Throws [LocationFailure] on permission denial, timeout, unavailability,
  /// or unsupported browser.
  Future<({double lat, double lng})> currentPosition();
}

/// Real implementation backed by the W3C Geolocation API.
class BrowserGeoLocationService implements GeoLocationService {
  @override
  Future<({double lat, double lng})> currentPosition() async {
    final completer = Completer<({double lat, double lng})>();
    final timeout = Timer(const Duration(seconds: 12), () {
      if (!completer.isCompleted) {
        completer.completeError(LocationFailure.timeout);
      }
    });

    void onSuccess(web.GeolocationPosition pos) {
      timeout.cancel();
      if (!completer.isCompleted) {
        completer.complete(
          (lat: pos.coords.latitude, lng: pos.coords.longitude),
        );
      }
    }

    void onError(web.GeolocationPositionError err) {
      timeout.cancel();
      if (completer.isCompleted) return;
      switch (err.code) {
        case 1:
          completer.completeError(LocationFailure.permissionDenied);
        case 2:
          completer.completeError(LocationFailure.unavailable);
        case 3:
          completer.completeError(LocationFailure.timeout);
        default:
          completer.completeError(LocationFailure.unknown);
      }
    }

    try {
      web.window.navigator.geolocation.getCurrentPosition(
        onSuccess.toJS,
        onError.toJS,
        web.PositionOptions(
          enableHighAccuracy: true,
          timeout: 12000,
          maximumAge: 30000,
        ),
      );
    } catch (_) {
      // The API can throw synchronously on browsers without geolocation.
      timeout.cancel();
      if (!completer.isCompleted) {
        completer.completeError(LocationFailure.unsupported);
      }
    }

    return completer.future;
  }

  /// Builds a Google Maps deep link for a coordinate.
  static String mapsUrlFor(double lat, double lng) {
    return 'https://www.google.com/maps?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}&z=16';
  }
}
