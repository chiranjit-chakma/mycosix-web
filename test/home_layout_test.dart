import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/pages/home/home_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';

/// Loads the real bundled fonts so text metrics match production (the default
/// test font, Ahem, is far too wide and would produce false overflows).
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> _pumpHome(WidgetTester tester, double w, double h) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final productsRepo = LocalProductRepository();
  final cartRepo = CartRepository(prefs, productsRepo);
  await cartRepo.load();

  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProductsController(productsRepo),
        ),
        ChangeNotifierProvider(create: (_) => CartController(cartRepo)),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HomePage(),
      ),
    ),
  );
  // Let the featured-products FutureBuilder resolve and paint a frame.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
}

/// Pumps the whole home page at each breakpoint and fails if any layout throws
/// (RenderFlex overflow etc.). The page scrolls as one column, so a single
/// frame lays out every section - any overflow surfaces as a FlutterError.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  const viewports = <(String, double, double)>[
    ('phone-360', 360, 780),
    ('phone-390', 390, 844),
    ('phone-430', 430, 932),
    ('fold-600', 600, 960),
    ('tablet-768', 768, 1024),
    ('tablet-820', 820, 1180),
    ('laptop-1024', 1024, 768),
    ('desktop-1280', 1280, 800),
    ('desktop-1440', 1440, 900),
    ('wide-1600', 1600, 1000),
  ];

  for (final (name, w, h) in viewports) {
    testWidgets('home page has no overflow at $name ($w x $h)',
        (tester) async {
      await _pumpHome(tester, w, h);

      // The page actually rendered its hero and featured section.
      expect(find.text('GROWN\nDIFFERENT.'), findsOneWidget,
          reason: 'hero copy should be present at $name');
      expect(
        find.text('Featured Mushrooms'),
        findsOneWidget,
        reason: 'featured section header should be present at $name',
      );

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'layout threw at $name ($w x $h): $exception');

      // The hero fills the first viewport (clearance + hero art), so the
      // section below it is NOT visible at load - it only appears on scroll.
      final vh = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final featuredTop = tester.getTopLeft(find.text('Featured Mushrooms')).dy;
      expect(featuredTop, greaterThanOrEqualTo(vh - 1.0),
          reason: 'section below hero should not peek into the first viewport '
              'at $name (featured top=$featuredTop, viewport h=$vh)');

      // All six grower avatars render on phones too (they wrap, not drop).
      for (final name in ['Chandan', 'Hruday', 'Preetham', 'Jashwanth',
          'Neha', 'Varshini']) {
        expect(find.text(name), findsWidgets,
            reason: 'grower "$name" should be present at $name viewport');
      }
    });
  }
}
