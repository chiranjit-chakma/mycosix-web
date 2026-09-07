import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/home/home_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';

/// Desktop prev/next arrows on the home 'Featured Mushrooms' rail.
///
/// On a mouse there is no natural way to swipe a horizontal rail, so the rail
/// shows round prev/next arrow buttons on desktop (>= 1024) that page through
/// the products; phones/tablets keep the natural swipe and no arrows.
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> _pump(WidgetTester tester, double w, double h) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final productsRepo = LocalProductRepository();
  final cartRepo = CartRepository(prefs, productsRepo);
  await cartRepo.load();
  final products = ProductsController(productsRepo);
  await products.fetchAll();
  final cart = CartController(cartRepo, siteDeliveryFee: MxConfig.deliveryFee);

  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProductsController>.value(value: products),
        ChangeNotifierProvider<CartController>.value(value: cart),
        ChangeNotifierProvider<WishlistController>(
          create: (_) => WishlistController(),
        ),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HomePage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  // Let the first post-frame arrow-state sync settle.
  await tester.pump();
}

IconButton _iconButtonOf(WidgetTester tester, String tooltip) {
  final btn = find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(IconButton),
  ).first;
  return tester.widget<IconButton>(btn);
}

void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  testWidgets('desktop shows Featured rail arrows that page the products',
      (tester) async {
    await _pump(tester, 1440, 900);

    final next = find.byTooltip('Next products');
    final prev = find.byTooltip('Previous products');
    expect(next, findsOneWidget, reason: 'desktop should show a next arrow');
    expect(prev, findsOneWidget, reason: 'desktop should show a previous arrow');

    // The rail sits below the fold on the tall home page — bring the arrow
    // into the viewport before tapping (widgets are all laid out, so the
    // finder alone is not enough).
    final nextBtnFinder = find
        .ancestor(of: next, matching: find.byType(IconButton))
        .first;
    await tester.ensureVisible(nextBtnFinder);
    await tester.pump(const Duration(milliseconds: 60));

    // Initially the rail sits at the start: previous is disabled, next is
    // active when there is more than one screenful of products.
    final nextBtn = tester.widget<IconButton>(nextBtnFinder);
    if (nextBtn.onPressed != null) {
      await tester.tap(nextBtnFinder);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 420));
      final prevBtn = _iconButtonOf(tester, 'Previous products');
      expect(prevBtn.onPressed, isNotNull,
          reason: 'after moving right, previous should become active');
    }
    final exception = tester.takeException();
    expect(exception, isNull, reason: 'rail layout threw: $exception');
  });

  testWidgets('phone keeps the natural swipe and shows no arrows',
      (tester) async {
    await _pump(tester, 390, 844);
    expect(find.byTooltip('Next products'), findsNothing,
        reason: 'phones swipe the rail directly');
    expect(find.byTooltip('Previous products'), findsNothing);
    final exception = tester.takeException();
    expect(exception, isNull, reason: 'rail layout threw: $exception');
  });
}
