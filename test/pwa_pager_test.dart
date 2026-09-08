import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/pwa/pwa_registry.dart';
import 'package:mycosix/pages/pwa/pwa_root.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/router/app_nav.dart';
import 'package:mycosix/router/routes.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads the real bundled fonts so text metrics match production.
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// A plain pager page: a tall colored slab with a label, so horizontal
/// swipes on empty space belong to the pager and vertical drags to the
/// section's own scroll view.
class _PlainSection extends StatelessWidget {
  const _PlainSection(this.index);

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1600,
      color: Colors.primaries[index % Colors.primaries.length].withValues(
        alpha: 0.25,
      ),
      child: Center(
        child: Text(
          'S$index',
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// A pager page carrying a horizontal rail — the installed-app equivalent of a
/// product carousel. The rail must scroll itself and never turn the page.
class _RailSection extends StatelessWidget {
  const _RailSection(this.index);

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.primaries[(index + 1) % Colors.primaries.length].withValues(
        alpha: 0.2,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < 8; i++)
              Container(
                key: Key('hitem-$index-$i'),
                width: 220,
                height: 240,
                margin: const EdgeInsets.all(10),
                color: Colors.primaries[(index + i) % Colors.primaries.length],
                child: Center(child: Text('H$index-$i')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pumps [MxPwaRoot] inside the same provider scope the real app uses, with
/// stand-in sections so the paging behavior is exercised in isolation.
Future<void> _pumpPager(
  WidgetTester tester, {
  int initialIndex = 0,
  List<Widget>? sections,
  Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{},
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final productsRepo = LocalProductRepository();
  final cartRepo = CartRepository(prefs, productsRepo);
  await cartRepo.load();

  tester.view.physicalSize = const Size(480, 900);
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
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        routes: routes,
        home: MxPwaRoot(
          initialIndex: initialIndex,
          sections:
              sections ??
              <Widget>[for (var i = 0; i < 5; i++) _PlainSection(i)],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

double _page(WidgetTester tester) {
  final pv = tester.widget<PageView>(find.byKey(const Key('pwa-pager')));
  return pv.controller!.page!;
}

/// Which bottom-nav destination currently reads as selected.
bool _navSelected(WidgetTester tester, String label) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .any((s) => s.properties.selected == true && s.properties.label == label);
}

void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  testWidgets('pager opens on the requested section and marks it selected', (
    tester,
  ) async {
    await _pumpPager(tester, initialIndex: 2);
    expect(_page(tester), 2.0);
    expect(_navSelected(tester, 'Farm'), isTrue);
    expect(_navSelected(tester, 'Home'), isFalse);
  });

  testWidgets('tapping a bottom-nav destination glides the pager', (
    tester,
  ) async {
    await _pumpPager(tester);
    expect(_page(tester), 0.0);

    await tester.tap(
      find.byKey(const Key('pwa-nav-journey')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_page(tester), 3.0);
    expect(_navSelected(tester, 'Journey'), isTrue);

    await tester.tap(
      find.byKey(const Key('pwa-nav-home')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_page(tester), 0.0);
  });

  testWidgets(
    'swiping empty page space does not change the section (the dock owns navigation)',
    (tester) async {
      await _pumpPager(tester);
      // Horizontal navigation belongs to the floating dock; a swipe on the
      // page's own space must not turn the section, or a product carousel,
      // image rail, map or form could be mistaken for navigation.
      await tester.drag(find.text('S0'), const Offset(-420, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_page(tester), 0.0);
      expect(_navSelected(tester, 'Home'), isTrue);

      // And back the other way.
      await tester.drag(find.text('S0'), const Offset(420, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_page(tester), 0.0);
    },
  );

  testWidgets(
    'a horizontal rail inside a section scrolls itself, not the page',
    (tester) async {
      await _pumpPager(
        tester,
        sections: <Widget>[
          const _RailSection(0),
          for (var i = 1; i < 5; i++) _PlainSection(i),
        ],
      );
      expect(_page(tester), 0.0);

      await tester.drag(
        find.byKey(const Key('hitem-0-1')),
        const Offset(-300, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The page did not turn...
      expect(_page(tester), 0.0);
      // ...but the rail itself scrolled.
      final rail = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byKey(const Key('pwa-section-0')),
              matching: find.byType(Scrollable),
            ),
          )
          .where((s) => s.widget.axisDirection == AxisDirection.right)
          .first;
      expect(rail.position.pixels, greaterThan(0));
    },
  );

  testWidgets('a vertical drag scrolls the section, not the page', (
    tester,
  ) async {
    await _pumpPager(tester);
    await tester.drag(find.text('S0'), const Offset(0, -500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_page(tester), 0.0);
    // The section's own scroll view is the down-scrollable that actually
    // has content (the footer's grid is another, non-scrolling one).
    final vertical = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('pwa-section-0')),
            matching: find.byType(Scrollable),
          ),
        )
        .where(
          (s) =>
              s.widget.axisDirection == AxisDirection.down &&
              s.position.maxScrollExtent > 0,
        )
        .first;
    expect(vertical.position.pixels, greaterThan(0));
  });

  testWidgets('system back on a deeper section glides Home first', (
    tester,
  ) async {
    // The owner flow: from any section but Home, back goes straight to
    // Home in one step (never one section at a time).
    await _pumpPager(tester, initialIndex: 4);
    expect(_page(tester), 4.0);

    await tester.binding.handlePopRoute();
    // _switchTo only glides the pager; _index updates when the glide
    // crosses its midpoint (_onPageChanged), and only then does the dock
    // learn the new section and start its snap. Both animations land in
    // their own frames, so settle until the tree is quiet, like a device
    // streaming frames. (The harness slabs animate nothing on their own.)
    await tester.pumpAndSettle();
    expect(_page(tester), 0.0);
    expect(_navSelected(tester, 'Home'), isTrue);

    // A second back on Home starts the exit guard: the hint appears and
    // the app does not leave (the test arm of the exit facade is a no-op).
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_page(tester), 0.0);
    expect(find.textContaining('Press back again'), findsOneWidget);
  });

  testWidgets('system back on Home shows the exit hint and does not leave', (
    tester,
  ) async {
    await _pumpPager(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_page(tester), 0.0);
    expect(find.textContaining('Press back again'), findsOneWidget);

    // A second back within the window attempts to exit; the test arm of the
    // exit facade is a no-op, so the app stays put.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('pwa-pager')), findsOneWidget);
    expect(_page(tester), 0.0);
  });

  testWidgets(
    'the installed app has no hamburger menu (bottom nav covers it)',
    (tester) async {
      await _pumpPager(tester);
      // No menu button and no drawer: the bottom navigation reaches every
      // primary section, and Team/Contact/legal stay under Profile -> More.
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.byType(Drawer), findsNothing);
      expect(find.byKey(const Key('pwa-nav-home')), findsOneWidget);
      expect(find.byKey(const Key('pwa-nav-profile')), findsOneWidget);
    },
  );

  testWidgets('tapping the current bottom-nav item scrolls it to the top', (
    tester,
  ) async {
    await _pumpPager(tester);
    // Scroll the Home section well down first.
    await tester.drag(find.text('S0'), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final vertical = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('pwa-section-0')),
            matching: find.byType(Scrollable),
          ),
        )
        .where(
          (s) =>
              s.widget.axisDirection == AxisDirection.down &&
              s.position.maxScrollExtent > 0,
        )
        .first;
    expect(vertical.position.pixels, greaterThan(0));

    // Tapping Home while already on Home glides the section back to the top.
    await tester.tap(
      find.byKey(const Key('pwa-nav-home')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(vertical.position.pixels, 0);
  });

  testWidgets(
    'a live pager consumes primary-route navigation; other routes pass through',
    (tester) async {
      await _pumpPager(
        tester,
        routes: <String, WidgetBuilder>{
          Routes.cart: (_) => const Scaffold(body: Center(child: Text('CART'))),
        },
      );
      final ctx = tester.element(find.byType(MxPwaRoot));

      // A primary section: the pager glides instead of stacking a second shell.
      expect(AppNav.go(ctx, Routes.shop), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_page(tester), 1.0);

      // A secondary route: an ordinary push, exactly like the browser.
      expect(AppNav.go(ctx, Routes.cart), isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('CART'), findsOneWidget);
    },
  );

  testWidgets('with no pager (browser tab), primary routes push normally', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => AppNav.go(context, Routes.shop),
                child: const Text('GO'),
              ),
            ),
          ),
        ),
        routes: <String, WidgetBuilder>{
          Routes.shop: (_) =>
              const Scaffold(body: Center(child: Text('SHOP_PLACEHOLDER'))),
        },
      ),
    );
    await tester.pump();

    final ctx = tester.element(find.byType(TextButton));
    expect(PwaRegistry.switchSection(Routes.shop), isFalse);
    expect(AppNav.go(ctx, Routes.shop), isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SHOP_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('the pager unregisters its hooks when it unmounts', (
    tester,
  ) async {
    await _pumpPager(tester);
    expect(PwaRegistry.switchSection(Routes.shop), isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(PwaRegistry.switchSection(Routes.shop), isFalse);
  });
}
