import 'url_launcher_stub.dart'
    if (dart.library.js_interop) 'url_launcher_web.dart' as impl;

/// Opens external URLs (WhatsApp, Instagram, Google Maps) in a new tab.
///
/// The implementation is chosen at compile time: on web platforms it uses the
/// real browser APIs ([url_launcher_web.dart]); everywhere else (unit tests,
/// future non-web targets) it falls back to a no-op stub so the app's pages
/// still compile and can be pumped in widget tests.
class UrlLauncher {
  UrlLauncher._();

  /// Opens [url] in a new browser tab.
  static void open(String url) => impl.open(url);

  /// Opens [url] in the same tab (full navigation).
  static void navigate(String url) => impl.navigate(url);
}
