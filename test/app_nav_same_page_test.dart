import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/router/app_nav.dart';
import 'package:mycosix/router/routes.dart';
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

/// The website has no floating scroll arrow in this flow: clicking the
/// navigation item for the page you are already on glides the page back to
/// the top instead of doing nothing (or worse, stacking a duplicate page).
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  testWidgets('clicking the current page nav link scrolls it back to the top', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();

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
            create: (_) =>
                CartController(cartRepo, siteDeliveryFee: MxConfig.deliveryFee),
          ),
          ChangeNotifierProvider<WishlistController>(
            create: (_) => WishlistController(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          initialRoute: Routes.home,
          routes: <String, WidgetBuilder>{
            Routes.home: (context) => MxShell(
              child: SizedBox(
                height: 2000,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: TextButton(
                    key: const Key('same-nav'),
                    onPressed: () => AppNav.go(context, Routes.home),
                    child: const Text('GO HOME'),
                  ),
                ),
              ),
            ),
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Scroll the page well down so the tap has to work to get back up.
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.pixels, greaterThan(0));

    // Clicking the nav link for the page you are already on glides to the
    // top and does not push a duplicate page. (Fixed pumps - pumpAndSettle
    // times out on shell pages per the codebase convention.)
    await tester.tap(find.byKey(const Key('same-nav')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(scrollable.position.pixels, 0);
    expect(find.byType(MxShell), findsOneWidget);
  });
}
