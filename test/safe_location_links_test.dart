// Unit tests for the safe location-link policy (lib/services/
// safe_location_links.dart): the only stored location link an order may open
// is one on Google's own map hosts; anything else falls back to a freshly
// built Google Maps link for the order's own co-ordinates - never the stored
// string verbatim. Mirrors the Firestore rules allowlist.
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/services/safe_location_links.dart';

void main() {
  group('isSafeGoogleMapsUrl', () {
    test('accepts the app-generated maps link', () {
      expect(
        isSafeGoogleMapsUrl(
          'https://www.google.com/maps?q=22.572646,88.363895&z=16',
        ),
        isTrue,
      );
    });

    test('accepts google.com/maps paths and google maps share links', () {
      expect(
        isSafeGoogleMapsUrl('https://www.google.com/maps/@22.5,88.3,15z'),
        isTrue,
      );
      expect(
        isSafeGoogleMapsUrl('https://maps.google.com/maps?q=22.5,88.3'),
        isTrue,
      );
      expect(isSafeGoogleMapsUrl('https://maps.app.goo.gl/abc123XYZ'), isTrue);
      expect(isSafeGoogleMapsUrl('https://goo.gl/maps/abc123XYZ'), isTrue);
      expect(isSafeGoogleMapsUrl('https://googlemaps.com/some/share'), isTrue);
      // Case is not significant (the rules allowlist is case-insensitive).
      expect(
        isSafeGoogleMapsUrl('https://WWW.GOOGLE.COM/maps?q=22.5,88.3'),
        isTrue,
      );
    });

    test('rejects arbitrary hosts, lookalike hosts and other schemes', () {
      expect(
        isSafeGoogleMapsUrl('https://evil.example.com/mycosix-login'),
        isFalse,
      );
      expect(
        isSafeGoogleMapsUrl('https://www.google.com.evil.com/maps?q=1,2'),
        isFalse,
      );
      expect(isSafeGoogleMapsUrl('https://google.com.evil.com/'), isFalse);
      expect(
        isSafeGoogleMapsUrl('https://maps.app.goo.gl.evil.com/x'),
        isFalse,
      );
      expect(isSafeGoogleMapsUrl('https://notgoogle.com/maps?q=1,2'), isFalse);
      expect(isSafeGoogleMapsUrl('https://maps.app.goo.gl'), isFalse);
      expect(isSafeGoogleMapsUrl('http://www.google.com/maps?q=1,2'), isFalse);
      expect(isSafeGoogleMapsUrl('javascript:alert(1)'), isFalse);
      expect(isSafeGoogleMapsUrl(''), isFalse);
      expect(
        isSafeGoogleMapsUrl('https://www.google.com/mapsX?q=1,2'),
        isFalse,
      );
    });
  });

  group('openableLocationUrl', () {
    test('safe stored links pass through unchanged', () {
      const link = 'https://www.google.com/maps?q=22.572646,88.363895&z=16';
      expect(openableLocationUrl(link, 22.572646, 88.363895), link);
      const short = 'https://maps.app.goo.gl/abc123XYZ';
      expect(openableLocationUrl(short, 22.5, 88.3), short);
    });

    test('an unsafe stored link falls back to a fresh maps link for the same point', () {
      final fallback = openableLocationUrl(
        'https://evil.example.com/mycosix-login',
        22.572646,
        88.363895,
      );
      expect(fallback, startsWith('https://www.google.com/maps?q='));
      // The fallback pin is the order's own co-ordinate, never the stored url.
      expect(fallback.contains('22.572646'), isTrue);
      expect(fallback.contains('88.363895'), isTrue);
      expect(fallback.contains('evil.example.com'), isFalse);
      // Empty (legacy pin) behaves the same.
      expect(
        openableLocationUrl('', 12.5, 77.25),
        'https://www.google.com/maps?q=12.500000,77.250000&z=16',
      );
    });
  });
}
