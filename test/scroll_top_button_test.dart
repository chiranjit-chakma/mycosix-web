import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';
import 'package:mycosix/widgets/shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads the real bundled fonts so text metrics match production.
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// Every page scrolls inside [MxShell]; the premium "back to top" button
/// appears once the page is well down, and tapping it glides back to the top.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  testWidgets('scroll-to-top button appears when scrolled and glides back',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();

    tester.view.physicalSize = const Size(900, 800);
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
          home: MxShell(
            child: SizedBox(
              width: double.infinity,
              height: 2400,
              child: ColoredBox(color: Color(0xFFF2ECDF)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final button = find.byKey(const Key('scroll-top-button'));
    expect(button, findsOneWidget);

    // Hidden at the top: not interactive.
    IgnorePointer overlayFor(WidgetTester t, Finder f) {
      return t.widget<IgnorePointer>(
        find.ancestor(of: f, matching: find.byType(IgnorePointer)).first,
      );
    }

    expect(overlayFor(tester, button).ignoring, isTrue);

    // Scroll the page well down.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, greaterThan(420));

    // Now the button is interactive.
    expect(overlayFor(tester, button).ignoring, isFalse);

    // Tap it and it glides back to the top.
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(scrollable.position.pixels, lessThan(10));

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'layout threw: $exception');
  });
}
