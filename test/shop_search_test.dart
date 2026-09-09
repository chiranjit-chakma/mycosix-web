import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/shop/shop_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/site_config_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';

/// Loads the real bundled fonts so text metrics match production (the default
/// test font is far too wide and would produce false card overflows).
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The Shop search box: live filtering over the real catalogue. It is purely a
/// product search — typing any text filters, nothing is treated as an admin
/// summon (admin entry lives on the account page).
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  Finder searchField() => find.byType(TextField);

  Future<void> pumpShop(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();
    final products = ProductsController(productsRepo);
    await products.fetchAll();

    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: products),
          ChangeNotifierProvider(
            create: (_) =>
                CartController(cartRepo, siteDeliveryFee: MxConfig.deliveryFee),
          ),
          ChangeNotifierProvider<WishlistController>(
            create: (_) => WishlistController(),
          ),
          // Delivery is enabled by default (Fb is off in tests).
          ChangeNotifierProvider<SiteConfigController>(
            create: (_) => SiteConfigController(),
          ),
        ],
        child: const MaterialApp(home: ShopPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('typing a term filters the grid to the matching packs', (
    tester,
  ) async {
    await pumpShop(tester);

    // Full catalogue loads.
    expect(find.text('Oyster Mushroom Powder'), findsOneWidget);
    expect(find.text('Fresh Oyster Mushrooms'), findsOneWidget);

    await tester.enterText(searchField(), 'powder');
    await tester.pump();

    expect(find.text('Oyster Mushroom Powder'), findsOneWidget);
    expect(find.text('Fresh Oyster Mushrooms'), findsNothing);
    expect(find.text('Dried Oyster Mushroom Slices'), findsNothing);

    // Clearing the box restores the full grid.
    await tester.enterText(searchField(), '');
    await tester.pump();
    expect(find.text('Fresh Oyster Mushrooms'), findsOneWidget);
  });
}
