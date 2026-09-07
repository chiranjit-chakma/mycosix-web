import 'package:web/web.dart' as web;

/// Web arm of the display-mode facade.
///
/// An installed PWA launched from the home screen / app drawer reports
/// `display-mode: standalone` (or fullscreen/minimal-ui). A normal browser
/// tab reports `browser`. The MYCOSIX account page uses this to show the
/// Wishlist and My Orders sections — locked until sign-in — to installed-app
/// users, while keeping them out of the signed-out browser experience
/// entirely.
bool isStandaloneDisplay() {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    // Some embedded browsers lack matchMedia; treat as not installed.
    return false;
  }
}
