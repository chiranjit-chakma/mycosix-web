/// Optional product photo helpers.
///
/// MYCOSIX has no paid services and its Firebase Storage is not provisioned,
/// so an admin-uploaded product photo is stored *on the product document
/// itself* as a compact inline PNG data URL (Firestore allows 1 MiB per
/// document). The shop renders it straight from the document - there is no
/// external host to break and nothing to fake. If Storage is provisioned
/// later, uploads can move there and `image` simply becomes a normal URL; the
/// renderer already accepts http(s) URLs as well, so nothing else changes.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Upper bound (in characters) for an inline image stored on a product.
/// Kept comfortably below Firestore's 1 MiB document cap so a product's text
/// fields always have room next to the photo.
const int maxInlineImageChars = 700 * 1000;

/// Longest side (pixels) of the photo stored on a product. Large enough to
/// look good on the shop cards and the product page, small enough that the
/// stored copy stays a sensible size.
const int maxInlineImageDimension = 900;

/// True when [value] is an inline image (an admin-uploaded photo stored on
/// the product document) rather than a bundled asset path or a normal URL.
bool isInlineImage(String value) => value.startsWith('data:image/');

/// True when [value] is a normal http(s) image URL.
bool isHttpImage(String value) =>
    value.startsWith('http://') || value.startsWith('https://');

/// The MIME type named by an inline image data URL, or null if [value] is not
/// an inline image. Example: `image/png`.
String? inlineImageMime(String value) {
  if (!isInlineImage(value)) return null;
  final semicolon = value.indexOf(';', 5); // after "data:"
  if (semicolon < 0) return null;
  return value.substring(5, semicolon);
}

/// Decodes [bytes] (an image chosen by the admin) and re-encodes it as a
/// small inline PNG data URL that fits on a product document.
///
/// The image is never upscaled; its longest side is capped at [maxDimension].
/// If the PNG at that size is still too large for the document budget
/// ([maxChars]), it is re-encoded smaller and smaller until it fits (down to
/// a tiny thumbnail). Returns null when the bytes are not a decodable image,
/// or when even the smallest attempt cannot fit - the caller then tells the
/// admin to choose a different photo.
Future<String?> encodeInlineProductImage(
  Uint8List bytes, {
  int maxDimension = maxInlineImageDimension,
  int maxChars = maxInlineImageChars,
}) async {
  final ui.Image? source = await _decode(bytes);
  if (source == null) return null;
  try {
    final sw = source.width;
    final sh = source.height;
    if (sw <= 0 || sh <= 0) return null;
    var target = sw >= sh ? sw : sh;
    if (target > maxDimension) target = maxDimension;
    while (true) {
      final (tw, th) = _fitted(sw, sh, target);
      final String url;
      try {
        url = await _pngUrl(source, tw, th);
      } catch (_) {
        return null;
      }
      if (url.length <= maxChars) return url;
      if (target <= 96) return null; // a photo this large cannot be stored
      target = (target * 0.7).round().clamp(96, target - 1).toInt();
    }
  } finally {
    source.dispose();
  }
}

Future<ui.Image?> _decode(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}

/// Scales (sw x sh) down to the largest size whose longest side is [target],
/// preserving the aspect ratio; never upscales either dimension.
(int, int) _fitted(int sw, int sh, int target) {
  if (sw >= sh) {
    final th = (sh * target / sw).round().clamp(1, target);
    return (target, th);
  }
  final tw = (sw * target / sh).round().clamp(1, target);
  return (tw, target);
}

/// Draws [source] into a [tw] x [th] image and returns it as a PNG data URL.
Future<String> _pngUrl(ui.Image source, int tw, int th) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    ),
    ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final scaled = await picture.toImage(tw, th);
  picture.dispose();
  try {
    final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Image encoding is not available.');
    }
    return 'data:image/png;base64,'
        '${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
  } finally {
    scaled.dispose();
  }
}
