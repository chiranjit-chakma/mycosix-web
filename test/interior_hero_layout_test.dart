import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/contact/contact_page.dart';
import 'package:mycosix/pages/farm/farm_page.dart';
import 'package:mycosix/pages/journey/journey_page.dart';
import 'package:mycosix/pages/team/team_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/widgets/editorial.dart';

/// Interior-page hero viewport-fill regression test.
///
/// The farm / journey / team / contact pages each open with a shared
/// [MxPageHero] strip. This verifies that the hero fills the first viewport on
/// every device (mirroring the home hero), so the opening image is full-screen
/// and the section below is never half-visible before the user scrolls.
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> _pump(WidgetTester tester, double w, double h,
    Widget Function() build) async {
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
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: build(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  final exception = tester.takeException();
  expect(exception, isNull, reason: 'layout threw at $w x $h: $exception');
}

/// The same viewport spread the responsive audit uses (short-landscape heights
/// included, where the hero's safe floor is taller than the fold).
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

void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  for (final (name, page) in [
    ('farm', () => const FarmPage()),
    ('journey', () => const JourneyPage()),
    ('team', () => const TeamPage()),
    ('contact', () => const ContactPage()),
  ]) {
    for (final (label, w, h) in viewports) {
      testWidgets(
          '$name page hero fills the first viewport at $w x $h ($label)',
          (tester) async {
        await _pump(tester, w, h, page);

        final hero = find.byType(MxPageHero);
        expect(hero, findsOneWidget,
            reason: '$name page should open with one MxPageHero');
        final rect = tester.getRect(hero);
        // The hero tops the page and spans at least the whole viewport, so the
        // following section can never peek in half-visible at load.
        expect(rect.top, closeTo(0, 0.01));
        expect(rect.height, greaterThanOrEqualTo(h - 0.5),
            reason: '$name hero must fill the fold at $w x $h '
                '(got ${rect.height} vs viewport $h)');
      });
    }
  }
}
