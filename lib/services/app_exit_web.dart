import 'package:web/web.dart' as web;

/// Web arm of the app-exit facade.
///
/// `window.close()` closes a window that was opened by script or an installed
/// PWA's own window; browsers refuse it for plain tabs. That is the honest
/// platform limit — the installed app gets a working "exit", a tab stays open.
bool get isSupported => true;

void maybeClose() {
  try {
    web.window.close();
  } catch (_) {
    // Never throw from a best-effort close.
  }
}
