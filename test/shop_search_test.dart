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
import 'package:mycosix/state/auth_controller.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/site_config_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';

/// An admin session with nothing behind it. The shop box asks a session only
/// two things - whether somebody is signed in, and whether the server accepts
/// the submitted word - so this stands in for a real signed-in administrator
/// without touching Firebase. [submitted] records the last word that actually
/// reached the server, which is how a test proves a wrongly-shaped word was
/// never sent at all (and therefore cannot leak that a code is even a thing).
class _StubAdminSession extends AuthController {
  _StubAdminSession({required this.signedIn, required this.result});

  final bool signedIn;
  final AdminCodeGrant result;

  String? submitted;

  @override
  bool get hasAdminSession => signedIn;

  @override
  Future<AdminCodeGrant> grantAdminWithCode(String code) async {
    submitted = code;
    return result;
  }
}

/// Loads the real bundled fonts so text metrics match production (the default
/// test font is far too wide and would produce false card overflows).
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The Shop search box: live filtering over the real catalogue. Typing is
/// purely a product search and never summons anything. A *submitted* single
/// word (4-64 characters, no spaces, no product match) is the quiet way an
/// administrator enters their own code: the word goes to the server, which
/// alone can tell whether it is the code set for THIS account's email, and
/// only a word it accepts opens the admin area. A wrong word, a word from an
/// account no code was set for, and a word from a visitor who is not signed in
/// are all the same ordinary empty product search — so the box can never be
/// used to discover that an admin area, or a code, exists.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  // The reveal is a process-wide singleton; keep it hidden between tests.
  setUp(() => AdminReveal.shared.resetForTest());

  Finder searchField() => find.byType(TextField);

  Future<void> pumpShop(WidgetTester tester, {AuthController? adminAuth}) async {
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
          if (adminAuth != null)
            ChangeNotifierProvider<AuthController>.value(value: adminAuth),
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

  testWidgets('a code word from a visitor who is not signed in reveals nothing',
      (tester) async {
    await pumpShop(tester);

    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();
    expect(find.text('No matches for “mycoforest”.'), findsOneWidget);

    // Submit (the search key). A code belongs to an email and only the account
    // that email belongs to can use it, so with nobody signed in this stays an
    // ordinary empty product search: not the admin page, not even a sign-in
    // page, and no hint that either exists.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
    expect(find.text('No matches for “mycoforest”.'), findsOneWidget);
  });

  testWidgets('a code the server refuses changes nothing at all', (tester) async {
    final admin = _StubAdminSession(
      signedIn: true,
      result: AdminCodeGrant.incorrectCode,
    );
    await pumpShop(tester, adminAuth: admin);

    await tester.enterText(searchField(), 'wrongword');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // The word did reach the server — that is the only way anyone can know
    // whether it is somebody's code — but the refusal is silent: the shop box
    // simply carries on showing no matches.
    expect(admin.submitted, 'wrongword');
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
    expect(find.text('No matches for “wrongword”.'), findsOneWidget);
  });

  testWidgets('a code the server accepts opens the admin area', (tester) async {
    final admin = _StubAdminSession(
      signedIn: true,
      result: AdminCodeGrant.granted,
    );
    await pumpShop(tester, adminAuth: admin);

    await tester.enterText(searchField(), 'mycoforest');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(admin.submitted, 'mycoforest');
    // goToAdmin is null in tests, so the stage flipping stands for the admin
    // page opening; the box is cleared, so the shop grid is back.
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
    expect(find.text('Fresh Oyster Mushrooms'), findsOneWidget);
  });

  testWidgets('a word that is not code-shaped never reaches the server',
      (tester) async {
    final admin = _StubAdminSession(
      signedIn: true,
      result: AdminCodeGrant.granted,
    );
    await pumpShop(tester, adminAuth: admin);

    // A product term is a product search, however it is shaped.
    await tester.enterText(searchField(), 'powder');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(admin.submitted, isNull);

    // Three characters: too short to be a code. Two words: not a single
    // token. 65 characters: longer than the Admins manager will ever store.
    for (final word in <String>['oat', 'dried mushroom', 'x' * 65]) {
      await tester.enterText(searchField(), word);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(admin.submitted, isNull, reason: 'submitted "$word"');
      expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
    }

    // A four-character single word IS code-shaped — real admin codes can be
    // that short — so it does go to the server.
    await tester.enterText(searchField(), 'abcd');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(admin.submitted, 'abcd');
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
  });
}
