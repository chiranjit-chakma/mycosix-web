import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/product/product_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';
import 'package:mycosix/widgets/mx_image.dart';
import 'package:mycosix/widgets/product_share_button.dart';
import 'package:mycosix/widgets/wishlist_heart.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads the real bundled fonts so text metrics match production.
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The product page gains share + wishlist icons on the image's top-right
/// corner (the compact overlay), while the under-price Share + heart stay —
/// nothing that existed before is removed or hidden.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  Future<void> pumpProductPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => ProductsController(productsRepo),
          ),
          ChangeNotifierProvider(
            create: (_) => CartController(
              cartRepo,
              siteDeliveryFee: MxConfig.deliveryFee,
            ),
          ),
          ChangeNotifierProvider<WishlistController>(
            create: (_) => WishlistController(),
          ),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ProductPage(productId: 'fresh-oyster-250'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('share + wishlist icons float on the product image top-right',
      (tester) async {
    await pumpProductPage(tester);

    final actions = find.byKey(const Key('product-image-actions'));
    expect(actions, findsOneWidget);

    // The overlay sits inside the hero image, not below it.
    final hero = tester.getRect(find.byType(MxImage).first);
    final actRect = tester.getRect(actions);
    expect(actRect.top, greaterThanOrEqualTo(hero.top));
    expect(actRect.left, greaterThanOrEqualTo(hero.left));
    expect(actRect.right, lessThanOrEqualTo(hero.right + 0.1));
    expect(actRect.bottom, lessThanOrEqualTo(hero.bottom + 0.1));

    // Both icons are on the overlay: the compact heart + the compact share.
    expect(
      find.descendant(
        of: actions,
        matching: find.byType(WishlistHeartButton),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: actions,
        matching: find.byIcon(Icons.share_outlined),
      ),
      findsOneWidget,
    );

    // The existing under-price Share + heart are still there (two share
    // buttons total: the new image one + the preserved under-price one).
    expect(find.byType(ProductShareButton), findsNWidgets(2));
    expect(find.byType(WishlistHeartButton), findsWidgets);

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'layout threw: $exception');
  });

  testWidgets('tapping the image share copies the product link',
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

    await pumpProductPage(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('product-image-actions')),
        matching: find.byIcon(Icons.share_outlined),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.text('Link copied - paste it anywhere to share this product'),
      findsOneWidget,
    );
    final setCalls = calls
        .where((c) => c.method == 'Clipboard.setData')
        .toList(growable: false);
    expect(setCalls, isNotEmpty);
    final text = (setCalls.last.arguments as Map)['text'] as String;
    expect(text, contains('/product/fresh-oyster-250'));
  });
}
