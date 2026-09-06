import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation of the PDF viewer/downloader: a Blob of the PDF bytes
/// becomes an object URL that the browser can open or save directly. Nothing
/// leaves the device — no upload, no paid service, no account.
///
/// Imported only when compiling with JavaScript interop (`dart.library.js_interop`),
/// so the browser-only `package:web` code never reaches the VM test runner.
const isSupported = true;

void view(Uint8List bytes, String filename) {
  final url = _objectUrl(bytes);
  web.window.open(url, '_blank');
}

void download(Uint8List bytes, String filename) {
  final url = _objectUrl(bytes);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  // A detached anchor still triggers a download on click in modern browsers.
  anchor.click();
  // The object URL is no longer needed once the download has started.
  Future<void>.delayed(const Duration(seconds: 2), () {
    web.URL.revokeObjectURL(url);
  });
}

/// Builds an in-memory Blob of the PDF and returns its object URL.
String _objectUrl(Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  return web.URL.createObjectURL(blob);
}
