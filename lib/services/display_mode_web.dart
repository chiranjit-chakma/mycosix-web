import 'package:web/web.dart' as web;

/// Web arm of the display-mode facade.
///
/// An installed PWA launched from the home screen / app drawer reports a
/// display mode that is NOT `browser`: `standalone` (Android/iOS/desktop
/// installs), `fullscreen` (full-screen app windows), `minimal-ui` (some
/// older Android browsers), or `window-controls-overlay` (Windows desktop
/// PWAs with a draggable title-bar). A normal browser tab always reports
/// `browser` and is never treated as the app. Matching ANY non-browser mode
/// keeps the installed app reliable across every browser that installs it.
/// This is UI presentation only — it never authorizes anything.
bool isStandaloneDisplay() {
  try {
    // Tear-offs of the interop member are disallowed in dart2js, so call
    // matchMedia directly for each mode.
    return web.window.matchMedia('(display-mode: standalone)').matches ||
        web.window.matchMedia('(display-mode: fullscreen)').matches ||
        web.window.matchMedia('(display-mode: minimal-ui)').matches ||
        web.window.matchMedia('(display-mode: window-controls-overlay)').matches;
  } catch (_) {
    // Some embedded browsers lack matchMedia; treat as not installed.
    return false;
  }
}
