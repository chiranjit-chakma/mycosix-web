import 'package:flutter/services.dart';

import 'share_common.dart';

/// Non-web product sharing.
///
/// There is no browser share sheet on the VM test runner, so a share copies
/// the product link to the clipboard. The real browser implementation (native
/// share sheet first, then clipboard) lives in share_service_web.dart and is
/// only ever compiled for the web.
Future<ShareOutcome> shareProductLink({
  required String url,
  String? title,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: url));
    return ShareOutcome.copied;
  } catch (_) {
    return ShareOutcome.unsupported;
  }
}
