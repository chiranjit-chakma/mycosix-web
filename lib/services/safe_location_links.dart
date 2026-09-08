// Safe handling of an order's stored location link.
//
// The only location link this app ever generates is a Google Maps link for a
// confirmed co-ordinate:
//   https://www.google.com/maps?q=<lat>,<lng>&z=16
// The Google-map host allowlist below is the same one the Firestore capture
// rules (isCapturedOrderShape in firestore.rules) and the trusted order
// backend (MAPS_HOSTS in functions/index.js) accept, so a stored order link
// can never point at an arbitrary host. An order that predates the rule, or
// one a crafted browser managed to record before it, falls back to a freshly
// built Google Maps link for the order's OWN co-ordinates instead of being
// opened as-is - the stored link opens in a new tab, and an unconstrained
// host there would be a phishing surface.
library;

/// Whether [url] is an https link on Google's own map hosts, in the same
/// shape the Firestore rules accept for a stored order link. Empty (a legacy
/// pin with no link) is not openable, so it counts as unsafe.
bool isSafeGoogleMapsUrl(String url) {
  return _safeMapsUrl.hasMatch(url);
}

/// The link to open for a stored order location: [storedUrl] itself when it
/// is a safe Google Maps link, otherwise a freshly built Google Maps link for
/// the order's co-ordinates - never the stored string verbatim.
String openableLocationUrl(
  String storedUrl,
  double latitude,
  double longitude,
) {
  if (isSafeGoogleMapsUrl(storedUrl)) return storedUrl;
  return mapsUrlFor(latitude, longitude);
}

/// Builds a Google Maps deep link for a coordinate (the one format the app
/// stores for a confirmed delivery point).
String mapsUrlFor(double lat, double lng) {
  return 'https://www.google.com/maps?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}&z=16';
}

// Mirrors the rules regexp in firestore.rules (isCapturedOrderShape): https
// only, host pinned to Google map hosts, and the same per-host path shape the
// backend enforces - /maps paths on google.com, a path on the shorteners.
final RegExp _safeMapsUrl = RegExp(
  r'^https://(www\.google\.com/maps([?/].*)?|'
  r'maps\.google\.com/maps([?/].*)?|'
  r'maps\.app\.goo\.gl/.+|goo\.gl/maps/.+|(www\.)?googlemaps\.com/.+)$',
  caseSensitive: false,
);
