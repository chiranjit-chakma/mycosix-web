import 'dart:typed_data';

import 'pdf_browser_stub.dart'
    if (dart.library.js_interop) 'pdf_browser_web.dart' as impl;

/// Views and downloads the locally-generated order-receipt PDF in the
/// browser.
///
/// The implementation is chosen at compile time: on web platforms it uses the
/// real browser APIs ([pdf_browser_web.dart]); everywhere else (unit tests,
/// future non-web targets) it falls back to a safe no-op stub so pages that
/// reference it still compile and can be pumped in widget tests.
class PdfBrowser {
  PdfBrowser._();

  /// True on the web, where a generated PDF can actually be opened or saved.
  static bool get isSupported => impl.isSupported;

  /// Opens the PDF in a new tab (the browser's built-in viewer).
  static void view(Uint8List bytes, String filename) =>
      impl.view(bytes, filename);

  /// Saves the PDF to the customer's downloads.
  static void download(Uint8List bytes, String filename) =>
      impl.download(bytes, filename);
}
