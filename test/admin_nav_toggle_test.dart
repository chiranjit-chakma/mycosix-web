import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/models/site_settings.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/admin_reveal.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/site_config_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';
import 'package:mycosix/widgets/shell.dart';

/// Loads the real bundled fonts so text metrics match production.
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The Admin entry in the site navigation follows the owner's toggle beside
/// Logout in the admin area (siteConfig/public adminNavShortcutEnabled):
///
///  * OFF (the default) — no Admin entry anywhere in the bar or drawer.
///  * ON — an Admin entry appears for every visitor (it is a DOORWAY, exactly
///    like the account-page "Admin" tile — the /admin gate still demands a
///    server-verified administrator before showing any admin content). Tapping
///    it arms the reveal, so a signed-out owner reaches the admin sign-in
///    rather than being silently handed back to the home page.
///  * The bar reacts live when an admin saves the setting — no reload.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  setUp(() => AdminReveal.shared.resetForTest());

  Future<SiteConfigController> pumpShell(
    WidgetTester tester, {
    required bool toggleOn,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();

    final siteConfig = SiteConfigController(
      initial: SiteSettings(adminNavShortcutEnabled: toggleOn),
    );

    tester.view.physicalSize = const Size(1280, 800);
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
          ChangeNotifierProvider<SiteConfigController>.value(
            value: siteConfig,
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
    return siteConfig;
  }

  testWidgets('toggle OFF shows no Admin entry in the desktop top bar',
      (tester) async {
    await pumpShell(tester, toggleOn: false);

    expect(find.text('Admin'), findsNothing);
    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);
  });

  testWidgets('toggle ON adds the Admin entry; tapping it arms the admin gate',
      (tester) async {
    await pumpShell(tester, toggleOn: true);

    // The extra navigation entry is present in the desktop top bar.
    expect(find.text('Admin'), findsOneWidget);

    // Tapping it summons the admin area (as the account-page tile does) rather
    // than a bare route push, so a signed-out owner lands on the sign-in page.
    await tester.tap(find.text('Admin'));
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
  });

  testWidgets('the bar reacts live when the toggle is flipped off', (
    tester,
  ) async {
    final siteConfig = await pumpShell(tester, toggleOn: true);
    expect(find.text('Admin'), findsOneWidget);

    // Simulate the admin switching the toggle OFF (SiteConfigController.apply
    // applies a live snapshot exactly as the Firestore listener would).
    siteConfig.applySettings(const SiteSettings());
    await tester.pump();
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('toggle ON adds an Admin tile to the mobile drawer', (
    tester,
  ) async {
    await pumpShell(tester, toggleOn: true);

    // Mobile width: the Admin entry lives in the drawer next to My Account.
    tester.view.physicalSize = const Size(430, 932);
    await tester.pump();
    expect(find.text('Admin'), findsNothing); // not open yet

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openEndDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('My Account'), findsWidgets);
    expect(find.text('Admin'), findsOneWidget);

    await tester.tap(find.text('Admin'));
    await tester.pump();
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
  });
}
