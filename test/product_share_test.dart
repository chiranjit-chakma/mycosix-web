import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/services/share_service.dart';
import 'package:mycosix/widgets/product_share_button.dart';

/// Customer product sharing: the shared link is the product's own deep link on
/// the current origin, and on a platform with no native share sheet the Share
/// button copies that link to the clipboard with a short confirmation.
void main() {
  group('productShareUrl', () {
    test('builds the product deep link on the app origin', () {
      expect(
        productShareUrl(
          'fresh-oyster-250',
          base: Uri.parse('https://mycosix.web.app/shop'),
        ),
        'https://mycosix.web.app/product/fresh-oyster-250',
      );
    });

    test('works when the customer is already on the product page', () {
      expect(
        productShareUrl(
          'fresh-oyster-250',
          base: Uri.parse('https://mycosix.web.app/product/fresh-oyster-250'),
        ),
        'https://mycosix.web.app/product/fresh-oyster-250',
      );
    });
  });

  group('ProductShareButton', () {
    testWidgets('copies the product link when there is no share sheet',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ProductShareButton(
                productName: 'Fresh Oyster Mushrooms',
                productId: 'fresh-oyster-250',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(
        find.text('Link copied - paste it anywhere to share this product'),
        findsOneWidget,
      );
      final setCalls = calls
          .where((c) => c.method == 'Clipboard.setData')
          .toList(growable: false);
      expect(setCalls, isNotEmpty);
      final text = (setCalls.last.arguments as Map)['text'] as String;
      // On the VM the copy happens through the stub share service, which copies
      // the real share link; its origin depends on the running host, but the
      // deep-link path is always the product page.
      expect(text, contains('/product/fresh-oyster-250'));
    });
  });
}
