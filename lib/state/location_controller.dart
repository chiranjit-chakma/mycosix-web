import 'package:flutter/foundation.dart';

import '../models/delivery_location.dart';
import '../repositories/cart_repository.dart';
import '../services/geo_location_service.dart';
import '../services/location_failure.dart';

/// Application state for delivery location.
///
/// A location only becomes usable once the user EXPLICITLY confirms it
/// (confirmed == true). GPS fixes and map drags set the candidate, never the
/// final location.
class LocationController extends ChangeNotifier {
  LocationController(this._repo, this._geo);

  final CartRepository _repo;
  final GeoLocationService _geo;

  DeliveryLocation? get location => _repo.location;

  bool get isConfirmed => location?.confirmed ?? false;

  String? get mapsUrl => location?.mapsUrl;

  /// True while a "use current location" request is in flight.
  bool locating = false;

  /// Last error message from a failed location attempt, if any.
  LocationFailure? lastFailure;

  /// Sets a candidate location from the map (NOT confirmed yet).
  Future<void> setCandidate(double lat, double lng) async {
    final url = BrowserGeoLocationService.mapsUrlFor(lat, lng);
    await _repo.saveLocation(
      DeliveryLocation(
        latitude: lat,
        longitude: lng,
        mapsUrl: url,
        confirmed: false,
      ),
    );
    lastFailure = null;
    notifyListeners();
  }

  /// Explicit user confirmation of the current candidate.
  Future<void> confirm() async {
    final current = _repo.location;
    if (current == null) return;
    await _repo.saveLocation(current.copyWith(confirmed: true));
    notifyListeners();
  }

  /// Resets a confirmed location back to unconfirmed (user moved the pin).
  Future<void> invalidate() async {
    final current = _repo.location;
    if (current == null) return;
    await _repo.saveLocation(current.copyWith(confirmed: false));
    notifyListeners();
  }

  /// Requests the device position and sets it as an UNCONFIRMED candidate.
  Future<DeliveryLocation?> useCurrentLocation() async {
    if (locating) return null;
    locating = true;
    lastFailure = null;
    notifyListeners();

    try {
      final pos = await _geo.currentPosition();
      final url = BrowserGeoLocationService.mapsUrlFor(pos.lat, pos.lng);
      final candidate = DeliveryLocation(
        latitude: pos.lat,
        longitude: pos.lng,
        mapsUrl: url,
        confirmed: false,
      );
      await _repo.saveLocation(candidate);
      return candidate;
    } on LocationFailure catch (f) {
      lastFailure = f;
      rethrow;
    } catch (_) {
      lastFailure = LocationFailure.unknown;
      rethrow;
    } finally {
      locating = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    await _repo.clearLocation();
    notifyListeners();
  }
}
