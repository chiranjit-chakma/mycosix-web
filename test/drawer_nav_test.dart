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

/// The drawer no longer lists Cart — the top-right cart icon already exists on
/// every page — while the rest of the menu stays.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  testWidgets('drawer has no Cart tile; account tile + top-bar cart stay',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();

    tester.view.physicalSize = const Size(500, 800);
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
              height: 800,
              child: ColoredBox(color: Color(0xFFF2ECDF)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The top-right cart icon is still there for every page.
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);

    // Open the drawer. (pumpAndSettle times out on the shell — use fixed
    // pumps per the codebase convention.)
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openEndDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Normal navigation tiles remain.
    for (final label in ['Home', 'Shop', 'Farm', 'My Account']) {
      expect(find.text(label), findsWidgets);
    }

    // Cart is gone from the drawer (and the bag icon is only the top bar's).
    expect(find.text('Cart'), findsNothing);
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'layout threw: $exception');
  });
}
