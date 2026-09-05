import 'package:web/web.dart' as web;

/// Web implementation of the link opener: real browser navigation.
///
/// Imported only when compiling with JavaScript interop (`dart.library.js_interop`),
/// so the browser-only `package:web` code never reaches the VM test runner.
void open(String url) {
  web.window.open(url, '_blank');
}

void navigate(String url) {
  web.window.location.href = url;
}
