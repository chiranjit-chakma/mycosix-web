import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/cart/cart_page.dart';
import 'package:mycosix/pages/contact/contact_page.dart';
import 'package:mycosix/pages/farm/farm_page.dart';
import 'package:mycosix/pages/home/home_page.dart';
import 'package:mycosix/pages/journey/journey_page.dart';
import 'package:mycosix/pages/legal/privacy_page.dart';
import 'package:mycosix/pages/legal/terms_page.dart';
import 'package:mycosix/pages/product/product_page.dart';
import 'package:mycosix/pages/shop/shop_page.dart';
import 'package:mycosix/pages/team/team_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/site_config_controller.dart';

/// Responsive audit harness.
///
/// Pumps every customer-facing page at the full viewport matrix the brief
/// targets (320px small phones through 1920px + ultrawide, plus short-landscape
/// heights so fixed-height hero / timeline boxes are exercised) with the real
/// bundled fonts and the real seed catalogue, then fails if the page throws a
/// layout exception (RenderFlex overflow, unbounded constraints, ...).
///
/// This is the strongest check available in this environment - headless Chrome
/// here cannot boot the Flutter engine, so real-browser visual multi-width
/// testing is not possible and these exception-based layout sweeps stand in for
/// it (the same technique the committed home-layout test already uses).
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// (label, width, height) — portrait phones, tablets, laptops, desktop, large
/// desktop and ultrawide, plus short-landscape heights.
const viewports = <(String, double, double)>[
  ('320', 320, 568),
  ('360', 360, 780),
  ('375', 375, 667),
  ('390', 390, 844),
  ('414', 414, 896),
  ('480', 480, 800),
  ('600', 600, 960),
  ('768', 768, 1024),
  ('820', 820, 1180),
  ('900', 900, 1200),
  ('1024', 1024, 768),
  ('1280', 1280, 800),
  ('1440', 1440, 900),
  ('1920', 1920, 1080),
  ('2560', 2560, 1080),
  ('844-landscape', 844, 390),
  ('1024-short', 1024, 600),
  ('1920-short', 1920, 600),
];

/// Builds the page under test with access to the freshly created controllers
/// (and the loaded seed catalogue) so a test can pre-fill the cart, etc.
typedef PageBuilder = Widget Function(
    CartController cart, ProductsController products);

/// Pumps [build]'s page at the given viewport and fails if the page threw a
/// layout exception. [extraSettle] is called after first paint (used to scroll
/// lower sections into view, since the page is one tall scroll column).
Future<void> _sweep(WidgetTester tester, double w, double h, PageBuilder build,
    {Future<void> Function(WidgetTester tester)? extraSettle}) async {
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

  final home = build(cart, products);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProductsController>.value(value: products),
        ChangeNotifierProvider<CartController>.value(value: cart),
        // Delivery stays enabled by default (Fb is off in tests), so the
        // pause banner renders nothing and the audit is unaffected.
        ChangeNotifierProvider<SiteConfigController>(
          create: (_) => SiteConfigController(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    ),
  );
  // Let first-frame work (image loading, post-frame fetches, the product
  // page's own byId load) settle before asserting.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  if (extraSettle != null) {
    await extraSettle(tester);
    await tester.pump(const Duration(milliseconds: 30));
  }
  final exception = tester.takeException();
  expect(exception, isNull, reason: 'layout threw at $w x $h: $exception');
}

void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  for (final (label, w, h) in viewports) {
    final at = '$w x $h ($label)';

    testWidgets('cart (empty) no overflow at $at', (tester) async {
      await _sweep(tester, w, h, (cart, products) => const CartPage());
      expect(find.text('Your cart is empty'), findsWidgets);
    });

    testWidgets('cart (two long-named lines) no overflow at $at',
        (tester) async {
      await _sweep(tester, w, h, (cart, products) {
        // The two longest-named packs exercise name wrapping at narrow widths.
        if (products.products.length >= 2) {
          cart.add(products.products[0], quantity: 2);
          cart.add(products.products[1], quantity: 1);
        }
        return const CartPage();
      });
      expect(find.text('Order summary'), findsWidgets);
      // A real cart line actually rendered (both packs added).
      expect(find.textContaining('Family Pack'), findsOneWidget);
    });

    testWidgets('shop no overflow at $at', (tester) async {
      await _sweep(tester, w, h, (cart, products) => const ShopPage());
      expect(find.text('Fresh from the grow room'), findsWidgets);
    });

    testWidgets('product no overflow at $at', (tester) async {
      await _sweep(
        tester, w, h,
        (cart, products) => const ProductPage(productId: 'fresh-oyster-250'),
        extraSettle: (tester) async {
          await tester.scrollUntilVisible(find.text('About this pack'), 200,
              scrollable: find.byType(Scrollable).first);
        },
      );
      expect(find.text('About this pack'), findsWidgets);
    });

    testWidgets('home no overflow at $at', (tester) async {
      await _sweep(tester, w, h, (cart, products) => const HomePage());
      expect(find.text('GROWN\nDIFFERENT.'), findsWidgets);
    });

    testWidgets('farm no overflow at $at', (tester) async {
      await _sweep(
        tester, w, h,
        (cart, products) => const FarmPage(),
        extraSettle: (tester) async {
          await tester.scrollUntilVisible(find.text('Indoors, on purpose'), 200,
              scrollable: find.byType(Scrollable).first);
        },
      );
      expect(find.text('Indoors, on purpose'), findsWidgets);
    });

    testWidgets('journey no overflow at $at', (tester) async {
      await _sweep(
        tester, w, h,
        (cart, products) => const JourneyPage(),
        extraSettle: (tester) async {
          await tester.scrollUntilVisible(find.text('More than mushrooms'), 200,
              scrollable: find.byType(Scrollable).first);
        },
      );
      expect(find.text('More than mushrooms'), findsWidgets);
    });

    testWidgets('team no overflow at $at', (tester) async {
      await _sweep(
        tester, w, h,
        (cart, products) => const TeamPage(),
        extraSettle: (tester) async {
          await tester.scrollUntilVisible(find.text('The founding six'), 200,
              scrollable: find.byType(Scrollable).first);
        },
      );
      expect(find.text('The founding six'), findsWidgets);
    });

    testWidgets('contact no overflow at $at', (tester) async {
      await _sweep(
        tester, w, h,
        (cart, products) => const ContactPage(),
        extraSettle: (tester) async {
          await tester.scrollUntilVisible(find.text('Ordering is easy'), 200,
              scrollable: find.byType(Scrollable).first);
        },
      );
      expect(find.text('Ordering is easy'), findsWidgets);
    });

    testWidgets('privacy no overflow at $at', (tester) async {
      await _sweep(tester, w, h, (cart, products) => const PrivacyPage());
      expect(find.text('Privacy Policy'), findsWidgets);
    });

    testWidgets('terms no overflow at $at', (tester) async {
      await _sweep(tester, w, h, (cart, products) => const TermsPage());
      expect(find.text('Terms & Conditions'), findsWidgets);
    });
  }
}
