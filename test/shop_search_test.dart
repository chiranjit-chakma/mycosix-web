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
/// purely a product search. A *submitted* code-like word (single word, no
/// spaces, 6+ letters, no product match) doubles as the owner's door to the
/// admin area: a signed-out visitor stays on the shop and gets the labelled
/// "Shop owner? Sign in to Admin" door in the empty state (the client cannot
/// verify the owner-set code, which lives only in the security rules); real
/// product searches and short/multi-word queries never change anything.
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

    // Just typing the code-shaped word only filters (no match, empty state) -
    // the door appears only on submit, so ordinary typing is never disturbed.
    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();

    expect(find.text('No matches for “mycoforest”.'), findsOneWidget);
    expect(find.text('Shop owner? Sign in to Admin'), findsNothing);
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
  });

  testWidgets('submitting a code-like word shows the owner door, no auto-nav',
      (tester) async {
    await pumpShop(tester);

    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();

    // Submit (the search key). A signed-out visitor cannot be verified, so the
    // shop stays put and surfaces the labelled admin door instead.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(find.text('Shop owner? Sign in to Admin'), findsOneWidget);
    // No silent navigation for a guest — the door is an explicit next step.
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);

    // Tapping the door arms the admin gate (goToAdmin is null in tests).
    await tester.tap(find.text('Shop owner? Sign in to Admin'));
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
  });

  testWidgets('a real product search and short words never show the door',
      (tester) async {
    await pumpShop(tester);

    // A product term (matches the catalogue) — submit stays a pure search.
    await tester.enterText(searchField(), 'powder');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('Shop owner? Sign in to Admin'), findsNothing);
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);

    // A short single word with no match is a search, not a code.
    await tester.enterText(searchField(), 'oats');
    await tester.pump();
    expect(find.text('No matches for “oats”.'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('Shop owner? Sign in to Admin'), findsNothing);
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);

    // A multi-word query is never a code.
    await tester.enterText(searchField(), 'dried mushroom');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('Shop owner? Sign in to Admin'), findsNothing);
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
  });

  testWidgets('changing the search text clears a shown owner door',
      (tester) async {
    await pumpShop(tester);

    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('Shop owner? Sign in to Admin'), findsOneWidget);

    await tester.enterText(searchField(), 'myco');
    await tester.pump();
    expect(find.text('Shop owner? Sign in to Admin'), findsNothing);
  });
}
