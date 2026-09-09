import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/models/site_settings.dart';
import 'package:mycosix/pages/pwa/pwa_dock.dart';
import 'package:mycosix/pages/pwa/pwa_root.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/admin_reveal.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/products_controller.dart';
import 'package:mycosix/state/site_config_controller.dart';
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

/// A plain pager page so the dock behavior is exercised in isolation.
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

/// Pumps [MxPwaRoot] with the same providers the real app uses, plus a
/// [SiteConfigController] whose navigation toggle is [adminOn], so the dock's
/// optional Admin doorway can be exercised. Starts centred on Home (the
/// pager's anchor) unless [initialIndex] says otherwise.
Future<void> _pumpPager(
  WidgetTester tester, {
  required bool adminOn,
  int initialIndex = kPwaHomeIndex,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final productsRepo = LocalProductRepository();
  final cartRepo = CartRepository(prefs, productsRepo);
  await cartRepo.load();

  tester.view.physicalSize = const Size(480, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final siteConfig = SiteConfigController(
    initial: SiteSettings(adminNavShortcutEnabled: adminOn),
  );
  addTearDown(siteConfig.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SiteConfigController>.value(value: siteConfig),
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
        home: MxPwaRoot(
          initialIndex: initialIndex,
          sections: <Widget>[for (var i = 0; i < 5; i++) _PlainSection(i)],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The live [PwaDock] built by the pager.
PwaDock _dock(WidgetTester tester) =>
    tester.widget<PwaDock>(find.byKey(const Key('pwa-dock')));

/// Which dock destination currently reads as selected.
bool _navSelected(WidgetTester tester, String label) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .any((s) => s.properties.selected == true && s.properties.label == label);
}

/// Which pager page is showing.
double _page(WidgetTester tester) {
  final pv = tester.widget<PageView>(find.byKey(const Key('pwa-pager')));
  return pv.controller!.page!;
}

/// Taps dock destination [label] at its strip position. Replicates the dock's
/// own slot geometry (full expansion, page at top) and the resting anchor in
/// [PwaDock.index], so the tap lands on the requested glyph regardless of how
/// many destinations the strip currently carries.
Future<void> _tapDockLabel(WidgetTester tester, String label) async {
  final dock = _dock(tester);
  final rect = tester.getRect(find.byKey(const Key('pwa-dock')));
  final screenWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final slot = math.min(66.0, (screenWidth - 24.0) / dock.labels.length);
  final item = dock.labels.indexOf(label);
  final cx = rect.left + rect.width / 2 + (item - dock.index) * slot;
  await tester.tapAt(Offset(cx, rect.center.dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  setUp(() => AdminReveal.shared.resetForTest());
  tearDown(() => AdminReveal.shared.goToAdmin = null);

  test('dock/admin index mapping slots Admin between Journey and Profile', () {
    // Without the toggle the dock is 1:1 with the pager.
    for (var pager = 0; pager < 5; pager++) {
      expect(
        dockIndexForPager(pager: pager, adminOn: false, sectionCount: 5),
        pager,
      );
    }
    // With it, Profile (the last section) shifts one slot right of Admin.
    for (var pager = 0; pager < 5; pager++) {
      expect(
        dockIndexForPager(pager: pager, adminOn: true, sectionCount: 5),
        pager >= 4 ? pager + 1 : pager,
      );
    }
    expect(adminDockIndex(5), 4);
    // A dock tap at/after the Admin slot means Profile; the root intercepts
    // the Admin slot itself before this mapping is ever used.
    expect(pagerIndexForDock(dock: 4, adminOn: true, sectionCount: 5), 4);
    expect(pagerIndexForDock(dock: 5, adminOn: true, sectionCount: 5), 4);
    expect(pagerIndexForDock(dock: 5, adminOn: false, sectionCount: 5), 5);
    // Label builders insert Admin between Journey and Profile.
    expect(pwaDockLabels(adminOn: false), const <String>[
      'Farm',
      'Shop',
      'Home',
      'Journey',
      'Profile',
    ]);
    expect(pwaDockLabels(adminOn: true), const <String>[
      'Farm',
      'Shop',
      'Home',
      'Journey',
      'Admin',
      'Profile',
    ]);
    expect(pwaDockIcons(adminOn: false).length, 5);
    expect(pwaDockIcons(adminOn: true).length, 6);
  });

  testWidgets('toggle OFF keeps the dock exactly as before - no Admin', (
    tester,
  ) async {
    await _pumpPager(tester, adminOn: false);
    expect(_dock(tester).labels, const <String>[
      'Farm',
      'Shop',
      'Home',
      'Journey',
      'Profile',
    ]);
    expect(find.byKey(const Key('pwa-nav-admin')), findsNothing);
    expect(_navSelected(tester, 'Home'), isTrue);
  });

  testWidgets('toggle ON shows Admin between Journey and Profile on the dock', (
    tester,
  ) async {
    await _pumpPager(tester, adminOn: true);
    final labels = _dock(tester).labels;
    expect(labels, hasLength(6));
    expect(labels.indexOf('Journey'), 3);
    expect(labels.indexOf('Admin'), 4);
    expect(labels.indexOf('Profile'), 5);
    expect(find.byKey(const Key('pwa-nav-admin')), findsOneWidget);
    expect(_navSelected(tester, 'Home'), isTrue);
    expect(_navSelected(tester, 'Admin'), isFalse);
  });

  testWidgets(
    'tapping Admin arms the admin reveal and never rests the strip on it',
    (tester) async {
      await _pumpPager(tester, adminOn: true);
      expect(AdminReveal.shared.stage, AdminRevealStage.hidden);

      await _tapDockLabel(tester, 'Admin');

      expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
      // Admin is an action, not a page: the pager did not move and the strip
      // springs back to the resting section (Home) rather than resting on a
      // slot with no page beneath it.
      expect(_page(tester), kPwaHomeIndex.toDouble());
      expect(_navSelected(tester, 'Home'), isTrue);
      expect(_navSelected(tester, 'Admin'), isFalse);
    },
  );

  testWidgets('with Admin on, Profile (one slot past Admin) still opens', (
    tester,
  ) async {
    await _pumpPager(tester, adminOn: true);
    await _tapDockLabel(tester, 'Profile');
    expect(_page(tester), 4);
    expect(_navSelected(tester, 'Profile'), isTrue);
    expect(_navSelected(tester, 'Admin'), isFalse);

    // And a section left of Admin keeps its own slot.
    await _tapDockLabel(tester, 'Journey');
    expect(_page(tester), 3);
    expect(_navSelected(tester, 'Journey'), isTrue);
  });
}
