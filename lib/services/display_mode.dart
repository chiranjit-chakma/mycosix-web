/// Display-mode facade.
///
/// Answers "is this app running as an installed PWA?" — the browser may or
/// may not (per-install) run in `standalone` display mode. Picks the real
/// implementation for the compile target: the browser (display_mode_web.dart —
/// CSS media query) or the VM test runner (display_mode_stub.dart — false).
library;

export 'display_mode_stub.dart'
    if (dart.library.js_interop) 'display_mode_web.dart';
