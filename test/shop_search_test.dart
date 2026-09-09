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
import 'package:mycosix/state/admin_reveal.dart';
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

/// The Shop search box: live filtering over the real catalogue. Typing is
/// purely a product search and never summons anything. A *submitted*
/// code-like word (single word, no spaces, 6+ letters, no product match) is
/// the owner's summon: it opens the admin area (in the app this lands on the
/// admin sign-in for a signed-out owner / the dashboard for a signed-in
/// administrator). Real product terms, short words and multi-word queries
/// never summon. The typed value itself is never a credential — the owner-set
/// code lives only in the security rules — so submitting merely opens the
/// gate, which still demands a server-verified administrator.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  // The reveal is a process-wide singleton; keep it hidden between tests.
  setUp(() => AdminReveal.shared.resetForTest());

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

  testWidgets('typing a code word never summons on its own', (tester) async {
    await pumpShop(tester);

    // Just typing the code-shaped word only filters (no match, empty state) —
    // nothing is summoned and nothing is cleared until submit.
    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();

    expect(find.text('No matches for “mycoforest”.'), findsOneWidget);
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
  });

  testWidgets('submitting a code-like word that matches nothing opens admin',
      (tester) async {
    await pumpShop(tester);

    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();
    expect(find.text('No matches for “mycoforest”.'), findsOneWidget);

    // Submit (the search key). A code-like word that matches nothing is the
    // owner's summon: it arms the admin gate (goToAdmin is null in tests, so
    // the stage flips instead of navigating), exactly as the owner asked — the
    // admin login page must open.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);

    // The summon also clears the box, so the shop grid is back.
    expect(find.text('Fresh Oyster Mushrooms'), findsOneWidget);
  });

  testWidgets('real product searches, short words and multi-word queries never summon',
      (tester) async {
    await pumpShop(tester);

    // A product term (matches the catalogue) — submit stays a pure search.
    await tester.enterText(searchField(), 'powder');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);

    // A short single word with no match is a search, not a code.
    await tester.enterText(searchField(), 'oats');
    await tester.pump();
    expect(find.text('No matches for “oats”.'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);

    // A multi-word query is never a code.
    await tester.enterText(searchField(), 'dried mushroom');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
  });

  testWidgets('a summon is idempotent; later ordinary typing stays a product search',
      (tester) async {
    await pumpShop(tester);

    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);

    // A second code-like submit keeps the gate armed (never double-stacks or
    // leaves the shop) and clears the box again.
    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);

    // Ordinary typing after a summon is a normal product search again and
    // changes nothing about the armed gate.
    await tester.enterText(searchField(), 'powder');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
  });
}
