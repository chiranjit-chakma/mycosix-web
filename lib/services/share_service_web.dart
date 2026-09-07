import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'share_common.dart';

/// Web product sharing.
///
/// Opens the browser's native share sheet (phone share / WhatsApp / email / a
/// desktop OS picker) when the Web Share API is available, and otherwise
/// copies the product link to the clipboard. Imported only when compiling for
/// the web, so this browser-only `package:web` code never reaches the VM test
/// runner (which gets share_service_stub.dart instead).
Future<ShareOutcome> shareProductLink({
  required String url,
  String? title,
}) async {
  if (_nativeShareUsable(url, title)) {
    try {
      // Called synchronously from the button's tap handler, so the browser
      // still holds user activation and is allowed to open the share sheet.
      await web.window.navigator.share(_shareData(url, title)).toDart;
      return ShareOutcome.shared;
    } catch (_) {
      // Dismissed, unsupported, or permission blocked: fall back to copying
      // the link so sharing still works everywhere.
    }
  }
  return _copy(url);
}

bool _nativeShareUsable(String url, String? title) {
  try {
    return web.window.navigator.canShare(_shareData(url, title));
  } catch (_) {
    return false; // no Web Share API in this browser
  }
}

web.ShareData _shareData(String url, String? title) =>
    web.ShareData(url: url, title: title ?? '');

Future<ShareOutcome> _copy(String url) async {
  try {
    // navigator.clipboard may be absent (e.g. an insecure context); accessing
    // it then throws, which is caught below.
    await web.window.navigator.clipboard.writeText(url).toDart;
    return ShareOutcome.copied;
  } catch (_) {
    // Fall back to Flutter's own clipboard channel.
  }
  try {
    await Clipboard.setData(ClipboardData(text: url));
    return ShareOutcome.copied;
  } catch (_) {
    return ShareOutcome.unsupported;
  }
}
