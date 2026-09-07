import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/farm/farm_page.dart';
import 'package:mycosix/pages/home/home_page.dart';
import 'package:mycosix/pages/journey/journey_page.dart';
import 'package:mycosix/pages/profile/profile_page.dart';
import 'package:mycosix/pages/shop/shop_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/router/routes.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/customer_auth_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/site_config_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';
import 'package:mycosix/widgets/page.dart';
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

Future<void> _pumpProviders(
  WidgetTester tester,
  Widget home, {
  Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{},
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final productsRepo = LocalProductRepository();
  final cartRepo = CartRepository(prefs, productsRepo);
  await cartRepo.load();

  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProductsController(productsRepo)),
        ChangeNotifierProvider(
          create: (_) =>
              CartController(cartRepo, siteDeliveryFee: MxConfig.deliveryFee),
        ),
        ChangeNotifierProvider<WishlistController>(
          create: (_) => WishlistController(),
        ),
        ChangeNotifierProvider<SiteConfigController>(
          create: (_) => SiteConfigController(),
        ),
        ChangeNotifierProvider<CustomerAuthController>(
          create: (_) => CustomerAuthController(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        routes: routes,
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The installed app renders each primary page in its EMBEDDED form (no page
/// shell — the paging shell supplies the chrome). This locks that: the pages
/// still build, and they must NOT carry their own [MxShell].
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  final pages = <String, Widget>{
    'home': const HomePage(embedded: true),
    'shop': const ShopPage(embedded: true),
    'farm': const FarmPage(embedded: true),
    'journey': const JourneyPage(embedded: true),
    'profile': const ProfilePage(embedded: true),
  };

  pages.forEach((name, page) {
    testWidgets('$name renders embedded (no page shell, no overflow)', (
      tester,
    ) async {
      // The installed app renders each section inside the paging shell's own
      // scroll view — mirror that shape (scroll view, no per-page MxShell).
      await _pumpProviders(
        tester,
        Scaffold(body: SingleChildScrollView(child: page)),
      );

      expect(find.byType(MxShell), findsNothing);
      final exception = tester.takeException();
      expect(exception, isNull, reason: '$name embedded threw: $exception');
    });
  });

  testWidgets('profile keeps Team/Contact/legal reachable under More', (
    tester,
  ) async {
    await _pumpProviders(tester, const ProfilePage());

    // The More panel lists exactly the pages the brief says must stay
    // reachable in the installed app. (The footer also mentions Contact, so
    // scope the assertions to the More panel.)
    expect(find.text('MORE'), findsOneWidget);
    final morePanel = find
        .ancestor(of: find.text('Team'), matching: find.byType(MxPanel))
        .first;
    for (final label in <String>[
      'Team',
      'Contact',
      'Privacy Policy',
      'Terms & Conditions',
    ]) {
      expect(
        find.descendant(of: morePanel, matching: find.text(label)),
        findsOneWidget,
        reason: 'More panel should list $label',
      );
    }
  });

  testWidgets('tapping Team under More navigates to the Team page', (
    tester,
  ) async {
    await _pumpProviders(
      tester,
      const ProfilePage(),
      routes: <String, WidgetBuilder>{
        Routes.team: (_) =>
            const Scaffold(body: Center(child: Text('TEAM_PLACEHOLDER'))),
      },
    );

    // The More panel sits below the account panel; bring the tile into view,
    // then nudge it clear of the floating top bar before tapping.
    await tester.ensureVisible(find.text('Team'));
    await tester.pump();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 160),
    );
    await tester.pump();
    await tester.tap(find.text('Team'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('TEAM_PLACEHOLDER'), findsOneWidget);
  });
}
