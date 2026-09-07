/// Product-link sharing facade.
///
/// Picks the real implementation for the current compile target: the browser
/// (share_service_web.dart - native share sheet, then clipboard) or the VM
/// test runner (share_service_stub.dart - clipboard only). The shared types
/// and helpers (ShareOutcome, productShareUrl) come from share_common.dart.
library;

export 'share_common.dart';
export 'share_service_stub.dart'
    if (dart.library.js_interop) 'share_service_web.dart';
