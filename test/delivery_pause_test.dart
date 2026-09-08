import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/models/site_settings.dart';
import 'package:mycosix/pages/cart/cart_page.dart';
import 'package:mycosix/pages/shop/shop_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/cart_sync_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/site_config_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';

class _NullAuth extends ChangeNotifier implements CartSyncAuth {
  @override
  String? get uid => null;
}

/// Delivery-pause gate: flipping "Delivery enabled" off in admin Settings must
/// reach the customer site live — a banner appears on the shop/cart and the
/// cart's Checkout button is disabled, with no reload.
void main() {
  // The shop grid and cart cards need the real fonts, or the wide default test
  // font overflows the fixed-height cards (false positives).
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  Future<_Ctx> seed({required bool paused}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();
    final products = ProductsController(productsRepo);
    await products.fetchAll();
    final cart = CartController(cartRepo, siteDeliveryFee: MxConfig.deliveryFee);
    // Dormant (no backend, no uid): the cart page's saved-items banner sits
    // under the pause notice and needs the controller present but idle.
    final sync = CartSyncController(
      repository: cartRepo,
      cart: cart,
      auth: _NullAuth(),
    );
    final config = SiteConfigController(
      initial: paused
          ? const SiteSettings(deliveryEnabled: false)
          : const SiteSettings(),
    );
    return _Ctx(
      cart: cart,
      products: products,
      config: config,
      sync: sync,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    _Ctx ctx,
    Widget page,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ctx.app(page));
    await tester.pump();
  }

  Finder banner() => find.text('Deliveries are paused');

  ElevatedButton checkoutButton(WidgetTester tester) => tester.widget<
      ElevatedButton>(find.widgetWithText(ElevatedButton, 'Checkout'));

  testWidgets('shop shows no banner while delivery is enabled', (tester) async {
    final ctx = await seed(paused: false);
    await pump(tester, ctx, const ShopPage());
    expect(banner(), findsNothing);
  });

  testWidgets('a live pause update shows the banner instantly on the shop',
      (tester) async {
    final ctx = await seed(paused: false);
    await pump(tester, ctx, const ShopPage());
    expect(banner(), findsNothing);

    // The admin toggles delivery off in Settings -> the live controller
    // applies the new snapshot and the shop reacts with no reload.
    ctx.config.applySettings(const SiteSettings(deliveryEnabled: false));
    await tester.pump();
    expect(banner(), findsOneWidget);
    expect(find.text('Message us on WhatsApp'), findsOneWidget);

    // Turning it back on removes the banner again.
    ctx.config.applySettings(const SiteSettings());
    await tester.pump();
    expect(banner(), findsNothing);
  });

  testWidgets('cart Checkout is enabled while delivery is on', (tester) async {
    final ctx = await seed(paused: false);
    if (ctx.products.products.isNotEmpty) {
      ctx.cart.add(ctx.products.products.first, quantity: 1);
    }
    await pump(tester, ctx, const CartPage());
    expect(banner(), findsNothing);
    expect(checkoutButton(tester).onPressed, isNotNull);
  });

  testWidgets('cart Checkout is disabled and the banner shows when paused',
      (tester) async {
    final ctx = await seed(paused: true);
    if (ctx.products.products.isNotEmpty) {
      ctx.cart.add(ctx.products.products.first, quantity: 1);
    }
    await pump(tester, ctx, const CartPage());
    expect(banner(), findsOneWidget);
    expect(checkoutButton(tester).onPressed, isNull);
    expect(find.text('Message us on WhatsApp'), findsOneWidget);
  });

  testWidgets('a live pause update disables an already-open cart Checkout',
      (tester) async {
    final ctx = await seed(paused: false);
    if (ctx.products.products.isNotEmpty) {
      ctx.cart.add(ctx.products.products.first, quantity: 1);
    }
    await pump(tester, ctx, const CartPage());
    expect(checkoutButton(tester).onPressed, isNotNull);

    ctx.config.applySettings(const SiteSettings(deliveryEnabled: false));
    await tester.pump();
    expect(banner(), findsOneWidget);
    expect(checkoutButton(tester).onPressed, isNull);
  });
}

/// Loads the real bundled fonts so text metrics match production (the default
/// test font is far too wide and would produce false card overflows).
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

class _Ctx {
  _Ctx({
    required this.cart,
    required this.products,
    required this.config,
    required this.sync,
  });

  final CartController cart;
  final ProductsController products;
  final SiteConfigController config;
  final CartSyncController sync;

  Widget app(Widget page) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ProductsController>.value(value: products),
          ChangeNotifierProvider<CartController>.value(value: cart),
          ChangeNotifierProvider<WishlistController>(
            create: (_) => WishlistController(),
          ),
          ChangeNotifierProvider<SiteConfigController>.value(value: config),
          ChangeNotifierProvider<CartSyncController>.value(value: sync),
        ],
        child: MaterialApp(debugShowCheckedModeBanner: false, home: page),
      );
}
