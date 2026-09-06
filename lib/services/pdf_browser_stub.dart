import 'dart:typed_data';

/// Non-web stand-in for the PDF viewer/downloader, so pages that reference
/// [PdfBrowser] compile and run under the VM test runner.
///
/// Opening or saving a file is genuinely impossible off the web; every call is
/// a safe no-op and [isSupported] is false so callers can hide the buttons.
const isSupported = false;

void view(Uint8List bytes, String filename) {}

void download(Uint8List bytes, String filename) {}
