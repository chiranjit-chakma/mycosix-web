import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/admin/admin_access_lock.dart';
import 'package:mycosix/pages/shop/shop_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/admin_reveal.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';

/// Loads the real bundled fonts so text metrics match production (the default
/// test font is far too wide and would produce false card overflows).
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The Shop search box: live filtering over the real catalogue, plus the covert
/// admin summon (the exact owner phrase reveals the sign-in instead of being
/// treated as a search).
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  Finder searchField() => find.byType(TextField);

  setUp(AdminReveal.shared.resetForTest);

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
            create: (_) => CartController(
              cartRepo,
              siteDeliveryFee: MxConfig.deliveryFee,
            ),
          ),
        ],
        child: const MaterialApp(home: ShopPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('typing a term filters the grid to the matching packs',
      (tester) async {
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

  testWidgets('the owner summon phrase reveals admin and is not a search',
      (tester) async {
    await pumpShop(tester);
    final secret = String.fromCharCodes(AdminAccessLock.secretCodePoints);

    await tester.enterText(searchField(), secret);
    await tester.pump();

    // Revealed, and the box is cleared so the phrase never filters products.
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
    final controller =
        tester.widget<TextField>(searchField()).controller!.text;
    expect(controller, isEmpty);
    expect(find.text('Fresh Oyster Mushrooms'), findsOneWidget);
  });

  testWidgets('a partial phrase only searches and never reveals',
      (tester) async {
    await pumpShop(tester);
    final codes = AdminAccessLock.secretCodePoints;
    final partial =
        String.fromCharCodes(codes.sublist(0, codes.length - 1));

    await tester.enterText(searchField(), partial);
    await tester.pump();

    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
    // No product matches a 11-char admin phrase, so the grid shows the empty
    // search state instead of the catalogue.
    expect(find.textContaining('No matches'), findsOneWidget);
  });
}
