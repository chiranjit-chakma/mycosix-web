/// Pure pixel <-> geographic conversion for the checkout map, kept separate
/// from the widgets so the math is unit-testable in isolation.
///
/// Conventions:
///  * Screen pixels are measured from the map center: positive x runs east
///    (right on screen), positive y runs south (down the screen).
///  * The scale is Web-Mercator's meters-per-pixel at the map's center
///    latitude, which is exact on the horizontal axis and a good
///    approximation across one map viewport on the vertical axis.
///  * Zoom is the web-Mercator zoom level used by the Google embed (the
///    meters-per-pixel scale halves with every step of zoom).
library;

import 'dart:math' as math;

/// Meters covered by one screen pixel at [latitudeDeg] and web-Mercator
/// [zoom]. Doubling the zoom halves the scale.
double metersPerPixelAt(double latitudeDeg, int zoom) =>
    156543.03392 * math.cos(latitudeDeg * math.pi / 180) / math.pow(2, zoom);

/// Degrees of latitude spanned by [dyPx] pixels at [metersPerPixel] (the
/// value from [metersPerPixelAt]). Positive dy is down the screen, which is
/// south, so the delta is negative.
double latitudeDeltaForPixels(double dyPx, double metersPerPixel) =>
    -dyPx * metersPerPixel / 111320.0;

/// Degrees of longitude spanned by [dxPx] pixels at [metersPerPixel] near
/// [latitudeDeg]. Positive dx is right on screen, which is east.
double longitudeDeltaForPixels(
  double dxPx,
  double metersPerPixel,
  double latitudeDeg,
) => dxPx * metersPerPixel / (111320.0 * math.cos(latitudeDeg * math.pi / 180));

/// Center latitude for a zoom step that keeps the spot under the pin fixed:
/// the map center that must pair with a pin tip [pinDyPx] off center so that
/// the pixel at that offset still shows [pinLatitude] at the new scale
/// [metersPerPixel].
double centerLatitudeForPin(
  double pinLatitude,
  double pinDyPx,
  double metersPerPixel,
) => pinLatitude + pinDyPx * metersPerPixel / 111320.0;

/// Longitude counterpart of [centerLatitudeForPin].
double centerLongitudeForPin(
  double pinLongitude,
  double pinDxPx,
  double metersPerPixel,
  double latitudeDeg,
) =>
    pinLongitude -
    pinDxPx *
        metersPerPixel /
        (111320.0 * math.cos(latitudeDeg * math.pi / 180));

/// Great-circle (haversine) distance in kilometres between two coordinates.
/// This is the distance delivery pricing measures: the straight-line
/// (crow-flies) distance from the shop point to the customer's pin.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const radiusKm = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * radiusKm * math.asin(math.sqrt(a.toDouble()));
}
