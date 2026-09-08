// Narrow, browser-free handle on the device's saved delivery point.
//
// The real controller (state/location_controller.dart) sits behind web-only
// services (browser geolocation), so widget tests that compile the profile
// page can never import it on the VM test runner. The profile page depends on
// this tiny contract instead; main.dart exposes the real controller under it
// (ProxyProvider), and a test can fake it in two lines of pure Dart.
library;

/// Something that can erase the device's saved delivery point.
abstract class SavedLocationClear {
  Future<void> clear();
}
