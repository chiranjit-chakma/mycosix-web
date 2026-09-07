import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/widgets/location/location_math.dart';

/// Tolerance guard for these assertions: the helpers are single-expression
/// arithmetic, so anything beyond floating rounding means a wrong formula.
void expectNear(double actual, double expected, {double tol = 1e-9}) {
  expect(
    (actual - expected).abs(),
    lessThan(tol + expected.abs() * 1e-9),
    reason: 'expected $actual near $expected',
  );
}

void main() {
  group('metersPerPixelAt', () {
    test('zoom 17 at the equator is the classic tile scale', () {
      // 156543.03392 m per tile pixel at zoom 0; each zoom halves it.
      expectNear(metersPerPixelAt(0, 17), 156543.03392 / 131072);
    });

    test('one zoom step halves the pixel scale', () {
      final z17 = metersPerPixelAt(12.3, 17);
      expectNear(metersPerPixelAt(12.3, 18), z17 / 2);
      expectNear(metersPerPixelAt(12.3, 16), z17 * 2);
    });

    test('higher latitude (closer to the pole) shrinks the scale', () {
      expect(metersPerPixelAt(60, 17), lessThan(metersPerPixelAt(12.3, 17)));
      expectNear(
        metersPerPixelAt(60, 17),
        metersPerPixelAt(0, 17) * 0.5, // cos(60 deg) == 0.5
      );
    });
  });

  group('latitudeDeltaForPixels', () {
    test(
      'down the screen (positive dy) moves south, so the delta is negative',
      () {
        final mpp = metersPerPixelAt(23.8, 17);
        expect(latitudeDeltaForPixels(100, mpp), lessThan(0));
      },
    );

    test('magnitude matches pixels times the per-pixel degrees', () {
      final mpp = metersPerPixelAt(23.8, 17);
      final perPxDeg = mpp / 111320.0;
      expectNear(latitudeDeltaForPixels(250, mpp), -250 * perPxDeg);
    });

    test('a symmetric move around the center lands back on the start', () {
      final mpp = metersPerPixelAt(23.8, 17);
      final lat0 = 23.8;
      final to = lat0 + latitudeDeltaForPixels(-140, mpp); // 140 px north.
      final back = to + latitudeDeltaForPixels(140, mpp); // 140 px south.
      expectNear(back, lat0);
    });
  });

  group('longitudeDeltaForPixels', () {
    test('right of center (positive dx) moves east', () {
      final mpp = metersPerPixelAt(23.8, 17);
      expect(longitudeDeltaForPixels(100, mpp, 23.8), greaterThan(0));
    });

    test('a degree of longitude is wider at the equator than up north', () {
      final mpp = metersPerPixelAt(0, 17);
      final wide = longitudeDeltaForPixels(100, mpp, 0);
      final narrow = longitudeDeltaForPixels(100, mpp, 60);
      expect(narrow, greaterThan(wide)); // Fewer degrees per pixel up north.
      expectNear(narrow, wide * 2);
    });

    test('round trip: pixels to degrees and back to pixels', () {
      final lat = 23.8;
      final mpp = metersPerPixelAt(lat, 17);
      const dx = 213.0;
      final dLng = longitudeDeltaForPixels(dx, mpp, lat);
      // Invert the helper with the same geometry: px = deg * 111320 / mpp.
      final perPxD = mpp / (111320.0 * math.cos(lat * math.pi / 180));
      expectNear(dLng / perPxD, dx, tol: 1e-9);
    });
  });

  group('zoom anchoring (the spot under the pin never drifts)', () {
    test('pin at the center: zoom keeps the center put', () {
      final pinLat = 12.2958;
      final mpp18 = metersPerPixelAt(pinLat, 18);
      expectNear(centerLatitudeForPin(pinLat, 0, mpp18), pinLat);
      final pinLng = 76.6394;
      expectNear(centerLongitudeForPin(pinLng, 0, mpp18, pinLat), pinLng);
    });

    test('pin above center: zooming in shifts the anchor south by half', () {
      final lat0 = 12.2958;
      final mpp17 = metersPerPixelAt(lat0, 17);
      const dy = -60.0; // 60 px above the center.
      final pinLat = lat0 + latitudeDeltaForPixels(dy, mpp17);
      final mpp18 = metersPerPixelAt(lat0, 18);
      final anchor = centerLatitudeForPin(pinLat, dy, mpp18);
      // At the new scale the geo at dy must equal the pin geo again.
      final geoBack = anchor + latitudeDeltaForPixels(dy, mpp18);
      expectNear(geoBack, pinLat);
    });

    test(
      'pin right of center: anchoring keeps the same longitude under it',
      () {
        final lat0 = 12.2958;
        final lng0 = 76.6394;
        final mpp17 = metersPerPixelAt(lat0, 17);
        const dx = 90.0;
        final pinLng = lng0 + longitudeDeltaForPixels(dx, mpp17, lat0);
        final mpp18 = metersPerPixelAt(lat0, 18);
        final anchor = centerLongitudeForPin(pinLng, dx, mpp18, lat0);
        final geoBack = anchor + longitudeDeltaForPixels(dx, mpp18, lat0);
        expectNear(geoBack, pinLng);
      },
    );
  });
}
