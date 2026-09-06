import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/util/product_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('inline image classification helpers', () {
    test('isInlineImage only accepts data:image/ URLs', () {
      expect(isInlineImage('data:image/png;base64,AAA'), isTrue);
      expect(isInlineImage('data:image/jpeg;base64,AAA'), isTrue);
      expect(isInlineImage('assets/products/oyster.webp'), isFalse);
      expect(isInlineImage('https://example.com/p.jpg'), isFalse);
      expect(isInlineImage(''), isFalse);
    });

    test('isHttpImage only accepts http(s) URLs', () {
      expect(isHttpImage('https://example.com/p.jpg'), isTrue);
      expect(isHttpImage('http://example.com/p.jpg'), isTrue);
      expect(isHttpImage('data:image/png;base64,AAA'), isFalse);
      expect(isHttpImage('assets/products/oyster.webp'), isFalse);
    });

    test('inlineImageMime reports the declared type', () {
      expect(inlineImageMime('data:image/png;base64,AAA'), 'image/png');
      expect(inlineImageMime('data:image/jpeg;base64,AAA'), 'image/jpeg');
      expect(inlineImageMime('assets/x.png'), isNull);
    });
  });

  group('encodeInlineProductImage', () {
    testWidgets('downscales a large source into a fitting PNG data URL',
        (tester) async {
      await tester.runAsync(() async {
        final bytes = await _renderPng(1000, 700);
        final url = await encodeInlineProductImage(
          bytes,
          maxDimension: 900,
          maxChars: maxInlineImageChars,
        );
        expect(url, isNotNull, reason: 'solid image must always fit');
        expect(url!.startsWith('data:image/png;base64,'), isTrue);
        final dims = await _decodedDimensions(url);
        expect(dims, isNotNull);
        // Longest side capped at 900 and the 1000:700 aspect kept.
        expect(dims!.$1, lessThanOrEqualTo(900));
        expect(dims.$2, lessThanOrEqualTo(900));
        final ratio = dims.$1 / dims.$2;
        expect((ratio - 1000 / 700).abs(), lessThan(0.05));
      });
    });

    testWidgets('keeps a small source at its own size (never upscales)',
        (tester) async {
      await tester.runAsync(() async {
        final bytes = await _renderPng(200, 120);
        final url = await encodeInlineProductImage(
          bytes,
          maxDimension: 900,
          maxChars: maxInlineImageChars,
        );
        expect(url, isNotNull);
        final dims = await _decodedDimensions(url!);
        expect(dims, isNotNull);
        expect(dims!.$1, lessThanOrEqualTo(200));
        expect(dims.$2, lessThanOrEqualTo(120));
      });
    });

    testWidgets('shrinks repeatedly until the stored URL fits the budget',
        (tester) async {
      await tester.runAsync(() async {
        // Random noise is effectively incompressible as PNG, so no size will
        // fit a 1 KB budget - the loop must give up and return null rather
        // than storing an over-budget image.
        final bytes = await _renderNoisePng(900, 700);
        final url = await encodeInlineProductImage(
          bytes,
          maxDimension: 900,
          maxChars: 1000,
        );
        expect(url, isNull);
      });
    });

    testWidgets('returns null when the bytes are not an image', (tester) async {
      await tester.runAsync(() async {
        final bytes = Uint8List.fromList(List.filled(64, 0));
        final url = await encodeInlineProductImage(bytes);
        expect(url, isNull);
      });
    });
  });
}

/// Renders a flat-colour image and returns its PNG bytes.
Future<Uint8List> _renderPng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF4E6B4A),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// Renders random (noise) pixels and returns their PNG bytes.
Future<Uint8List> _renderNoisePng(int w, int h) async {
  final rgba = Uint8List(w * h * 4);
  final rnd = Random(7);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = rnd.nextInt(256);
    rgba[i + 1] = rnd.nextInt(256);
    rgba[i + 2] = rnd.nextInt(256);
    rgba[i + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// Decodes an inline image data URL back to its pixel dimensions.
Future<(int, int)?> _decodedDimensions(String dataUrl) async {
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  final b64 = dataUrl.substring(comma + 1);
  try {
    final bytes = base64Decode(b64);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final dims = (image.width, image.height);
    image.dispose();
    codec.dispose();
    return dims;
  } catch (_) {
    return null;
  }
}
