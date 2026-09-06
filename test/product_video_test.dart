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
/// a product with a playable video — direct .mp4/.webm link OR a YouTube
/// link — gains the "Watch product video" button.
void main() {
  group('resolveProductVideo / hasProductVideo', () {
    test('blank or null means no video', () {
      expect(resolveProductVideo(null), isNull);
      expect(resolveProductVideo(''), isNull);
      expect(resolveProductVideo('   '), isNull);
      expect(hasProductVideo(null), isFalse);
      expect(hasProductVideo(''), isFalse);
    });

    test('only real http(s) web links count as a video', () {
      expect(hasProductVideo('https://example.com/clip.mp4'), isTrue);
      expect(hasProductVideo('http://cdn.example.com/v.webm'), isTrue);
      // Garbage, non-web schemes and local paths never count.
      expect(hasProductVideo('watch?v=abc'), isFalse);
      expect(hasProductVideo('javascript:alert(1)'), isFalse);
      expect(hasProductVideo('file:///C:/video.mp4'), isFalse);
      expect(hasProductVideo('not-a-url'), isFalse);
    });

    test('surrounding whitespace is trimmed before matching', () {
      final ref = resolveProductVideo('  https://example.com/v.mp4  ');
      expect(ref, isNotNull);
      expect(ref!.kind, ProductVideoKind.direct);
      expect(ref.url, 'https://example.com/v.mp4');
    });

    test('a plain http(s) link is a direct media file', () {
      final ref = resolveProductVideo('https://cdn.example.com/grow.mp4');
      expect(ref, isNotNull);
      expect(ref!.kind, ProductVideoKind.direct);
      expect(ref.url, 'https://cdn.example.com/grow.mp4');
    });

    test('YouTube links are recognised and embedded (no-autoplay controls)',
        () {
      const id = 'dQw4w9WgXcQ';
      const expected =
          'https://www.youtube-nocookie.com/embed/$id?playsinline=1&rel=0';
      final forms = <String>[
        'https://www.youtube.com/watch?v=$id',
        'https://youtu.be/$id',
        'https://www.youtube.com/shorts/$id',
        'https://youtube.com/embed/$id',
        'https://www.youtube.com/live/$id',
        'https://music.youtube.com/watch?v=$id',
      ];
      for (final form in forms) {
        final ref = resolveProductVideo(form);
        expect(ref, isNotNull, reason: 'should resolve: $form');
        expect(ref!.kind, ProductVideoKind.youtube, reason: form);
        expect(ref.url, expected, reason: form);
      }
    });

    test('a YouTube page without a real video id is not playable', () {
      expect(resolveProductVideo('https://www.youtube.com/@mycosix'), isNull);
      expect(
          resolveProductVideo('https://youtu.be/abc'), isNull); // too short
      expect(
          resolveProductVideo('https://www.youtube.com/watch?v='), isNull);
    });
  });

  group('videoLinkFieldError (admin field validator)', () {
    test('empty is allowed (no video); bad links are rejected', () {
      expect(videoLinkFieldError(''), isNull);
      expect(videoLinkFieldError('   '), isNull);
      expect(videoLinkFieldError('not-a-link'), isNotNull);
      expect(videoLinkFieldError('file:///C:/v.mp4'), isNotNull);
    });

    test('a YouTube link or a direct media link is accepted', () {
      expect(videoLinkFieldError('https://youtu.be/dQw4w9WgXcQ'), isNull);
      expect(videoLinkFieldError('https://cdn.example.com/grow.mp4'), isNull);
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

    testWidgets('shows the control for a direct video link', (tester) async {
      await tester.pumpWidget(
        wrap(ProductVideoButton(
          product: productWith(videoUrl: 'https://example.com/cook.mp4'),
        )),
      );
      expect(find.text('Watch product video'), findsOneWidget);
    });

    testWidgets('shows the control for a YouTube link too', (tester) async {
      await tester.pumpWidget(
        wrap(ProductVideoButton(
          product: productWith(videoUrl: 'https://youtu.be/dQw4w9WgXcQ'),
        )),
      );
      expect(find.text('Watch product video'), findsOneWidget);
    });
  });
}
