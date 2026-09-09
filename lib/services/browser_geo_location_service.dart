import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'geo_location_service.dart';
import 'location_failure.dart';

/// Real implementation of [GeoLocationService] backed by the W3C Geolocation
/// API. Web-only: import from main.dart / the app shell, never from a
/// controller that tests must construct on the VM test runner.
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
}
