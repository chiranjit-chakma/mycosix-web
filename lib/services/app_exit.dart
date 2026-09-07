/// Facade: try to close the browser window (installed PWA arm).
///
/// The VM/test arm is a no-op that reports "not supported", so widget tests
/// exercise the guard logic without ever touching a real window.
library;

import 'app_exit_stub.dart'
    if (dart.library.js_interop) 'app_exit_web.dart' as impl;

class AppExit {
  AppExit._();

  /// Whether this build can attempt to close the app window.
  static bool get isSupported => impl.isSupported;

  /// Best-effort close. A normal browser tab cannot be closed by script, so
  /// this only truly works for an installed PWA's own window — and even there
  /// it is a request the browser may ignore.
  static void maybeClose() => impl.maybeClose();
}
