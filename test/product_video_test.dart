import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/product.dart';
import 'package:mycosix/widgets/product_video.dart';

Product productWith({String? videoUrl}) => Product(
      id: 'p1',
      name: 'Fresh Oyster Mushrooms',
      description: 'Fresh by MYCOSIX',
      category: 'Fresh',
      image: 'a.jpg',
      variant: 'Fresh',
      weight: '250 g',
      price: 80,
      stock: 5,
      available: true,
      videoUrl: videoUrl,
    );

/// A product without a video must look exactly like one (no dangling control);
/// a product with a playable video gains the "Watch product video" button.
void main() {
  group('cleanProductVideo / hasProductVideo', () {
    test('blank or null means no video', () {
      expect(cleanProductVideo(null), isNull);
      expect(cleanProductVideo(''), isNull);
      expect(cleanProductVideo('   '), isNull);
      expect(hasProductVideo(null), isFalse);
      expect(hasProductVideo(''), isFalse);
    });

    test('only real http(s) web links count as a video', () {
      expect(cleanProductVideo('https://example.com/clip.mp4'),
          'https://example.com/clip.mp4');
      expect(cleanProductVideo('http://cdn.example.com/v.webm'),
          isNotNull);
      // Garbage, non-web schemes and local paths never count.
      expect(cleanProductVideo('watch?v=abc'), isNull);
      expect(cleanProductVideo('javascript:alert(1)'), isNull);
      expect(cleanProductVideo('file:///C:/video.mp4'), isNull);
      expect(hasProductVideo('watch?v=abc'), isFalse);
    });

    test('surrounding whitespace is trimmed before matching', () {
      expect(cleanProductVideo('  https://example.com/v.mp4  '),
          'https://example.com/v.mp4');
    });
  });

  group('ProductVideoButton', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('renders nothing when the product has no video',
        (tester) async {
      await tester.pumpWidget(wrap(ProductVideoButton(product: productWith())));
      expect(find.text('Watch product video'), findsNothing);
    });

    testWidgets('renders nothing for blank or non-web values', (tester) async {
      await tester.pumpWidget(
        wrap(ProductVideoButton(product: productWith(videoUrl: '  '))),
      );
      expect(find.text('Watch product video'), findsNothing);

      await tester.pumpWidget(
        wrap(ProductVideoButton(product: productWith(videoUrl: 'not-a-url'))),
      );
      expect(find.text('Watch product video'), findsNothing);
    });

    testWidgets('shows the control only when a playable video exists',
        (tester) async {
      await tester.pumpWidget(
        wrap(ProductVideoButton(
          product: productWith(videoUrl: 'https://example.com/cook.mp4'),
        )),
      );
      expect(find.text('Watch product video'), findsOneWidget);
    });
  });
}
