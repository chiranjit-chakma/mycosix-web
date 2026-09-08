import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_colors.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/pages/pwa/pwa_root.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/widgets/footer.dart';
import 'package:mycosix/repositories/product_repository.dart';
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

/// A plain pager page: a tall colored slab with a label, so drags on the
/// page's own space never collide with the dock.
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

/// A pager page with a text field at the top, so the keyboard focus path
/// (the dock hiding while an editable field is open) can be exercised.
class _InputSection extends StatelessWidget {
  const _InputSection(this.index);

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1600,
      color: Colors.primaries[index % Colors.primaries.length].withValues(
        alpha: 0.25,
      ),
      // Align keeps the field at its natural size near the top; without it
      // the tall slab would stretch the field the full 1600px and the dock
      // would cover its centre.
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 160, left: 24, right: 24),
          child: SizedBox(
            width: 300,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'type here',
                filled: true,
                fillColor: MxColors.creamSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pumps [MxPwaRoot] inside the same provider scope the real app uses, with
/// stand-in sections so the dock behavior is exercised in isolation.
Future<void> _pumpPager(
  WidgetTester tester, {
  int initialIndex = 0,
  List<Widget>? sections,
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

/// Which dock destination currently reads as selected.
bool _navSelected(WidgetTester tester, String label) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .any((s) => s.properties.selected == true && s.properties.label == label);
}

/// The section's own scrollable (the down-scrollable with actual content).
ScrollableState _sectionScroll(WidgetTester tester, int index) {
  return tester
      .stateList<ScrollableState>(
        find.descendant(
          of: find.byKey(Key('pwa-section-$index')),
          matching: find.byType(Scrollable),
        ),
      )
      .where(
        (s) =>
            s.widget.axisDirection == AxisDirection.down &&
            s.position.maxScrollExtent > 0,
      )
      .first;
}

/// A deliberate drag of [offset] across the dock, released, and settled
/// past both the dock's snap and the pager's glide.
// A real touch streams many move events, so a drag recognizer with the
// default DragStartBehavior.start consumes the slop-crossing move in onStart
// and only reports subsequent moves via onUpdate. A single moveBy then up
// would therefore never reach the strip's onUpdate; tester.drag splits the
// drag into a slop move plus remainder steps, which is what real input does.
Future<void> _dragDock(WidgetTester tester, Offset offset) async {
  await tester.drag(
    find.byKey(const Key('pwa-dock')),
    offset,
    warnIfMissed: false,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  testWidgets('pager opens on the requested section and the dock marks it selected', (
    tester,
  ) async {
    await _pumpPager(tester, initialIndex: 2);
    expect(_page(tester), 2.0);
    expect(_navSelected(tester, 'Farm'), isTrue);
    expect(_navSelected(tester, 'Home'), isFalse);
  });

  testWidgets('dragging the dock left advances to the next section and snaps', (
    tester,
  ) async {
    await _pumpPager(tester);
    expect(_page(tester), 0.0);

    await _dragDock(tester, const Offset(-90, 0));
    expect(_page(tester), 1.0);
    expect(_navSelected(tester, 'Shop'), isTrue);
    expect(_navSelected(tester, 'Home'), isFalse);
  });

  testWidgets('dragging the dock right returns to the previous section', (
    tester,
  ) async {
    await _pumpPager(tester, initialIndex: 1);
    await _dragDock(tester, const Offset(90, 0));
    expect(_page(tester), 0.0);
    expect(_navSelected(tester, 'Home'), isTrue);
  });

  testWidgets('releasing between items snaps to the nearest section', (
    tester,
  ) async {
    await _pumpPager(tester);
    // Just under half a slot: the strip springs back to Home.
    await _dragDock(tester, const Offset(-30, 0));
    expect(_page(tester), 0.0);

    // Just past half a slot: it advances to Shop.
    await _pumpPager(tester);
    await _dragDock(tester, const Offset(-60, 0));
    expect(_page(tester), 1.0);
  });

  testWidgets('a fast swipe carries momentum across the next slot', (
    tester,
  ) async {
    await _pumpPager(tester);
    await tester.fling(
      find.byKey(const Key('pwa-dock')),
      const Offset(-120, 0),
      1200,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The fling lands on Farm, a full section beyond the drag distance.
    expect(_page(tester), 2.0);
  });

  testWidgets('the dock clamps at the first and last sections', (tester) async {
    await _pumpPager(tester);
    // Dragging right (previous) at the first section: nowhere to go back.
    await _dragDock(tester, const Offset(100, 0));
    expect(_page(tester), 0.0);

    // A long drag reaches the far end, and no further.
    await _dragDock(tester, const Offset(-420, 0));
    expect(_page(tester), 4.0);
    expect(_navSelected(tester, 'Profile'), isTrue);

    // From the last section, dragging right steps back toward Home.
    await _dragDock(tester, const Offset(90, 0));
    expect(_page(tester), 3.0);
  });

  testWidgets('mid-drag the item nearest the center is already the selection', (
    tester,
  ) async {
    await _pumpPager(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pwa-dock'))),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-50, 0));
    await tester.pump();
    // Before release: the live selection has already moved to Shop.
    expect(_navSelected(tester, 'Shop'), isTrue);
    expect(_navSelected(tester, 'Home'), isFalse);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_page(tester), 1.0);
  });

  testWidgets('changing direction mid-drag keeps the strip with the finger', (
    tester,
  ) async {
    await _pumpPager(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pwa-dock'))),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-80, 0));
    await gesture.moveBy(const Offset(80, 0));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The net movement is zero, so Home stays centered and selected.
    expect(_page(tester), 0.0);
    expect(_navSelected(tester, 'Home'), isTrue);
  });

  testWidgets('a vertical drag on the dock scrolls the page, not the section', (
    tester,
  ) async {
    await _pumpPager(tester);
    await tester.drag(
      find.byKey(const Key('pwa-dock')),
      const Offset(0, -300),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The page did not turn and the section itself scrolled: the dock never
    // eats a vertical gesture.
    expect(_page(tester), 0.0);
    expect(_sectionScroll(tester, 0).position.pixels, greaterThan(0));
  });

  testWidgets('scrolling a section compresses the dock; scrolling back expands it', (
    tester,
  ) async {
    await _pumpPager(tester);
    final dock = find.byKey(const Key('pwa-dock'));
    expect(tester.getSize(dock).height, 78.0);
    // Expanded: the strip spans almost the full width (480 - 24 margins).
    final expandedWidth = tester.getSize(dock).width;
    expect(expandedWidth, closeTo(456.0, 0.5));

    // Scroll the section down: the dock compresses on BOTH axes — shorter
    // and narrower — never abruptly hides.
    await tester.drag(find.text('S0'), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(dock).height, 58.0);
    expect(tester.getSize(dock).width, closeTo(456.0 * 0.66, 0.5));
    expect(tester.getSize(dock).width, lessThan(expandedWidth - 100));

    // Scroll back up: the dock expands again on both axes.
    await tester.drag(find.text('S0'), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(dock).height, 78.0);
    expect(tester.getSize(dock).width, closeTo(expandedWidth, 0.5));
  });

  testWidgets('the dock rides a frosted glass carrier with no per-icon cells', (
    tester,
  ) async {
    await _pumpPager(tester);
    final dock = find.byKey(const Key('pwa-dock'));
    // The glyphs float on one frosted glass card: the blur shell is there,
    // and so is the wash/hairline/shadow decoration over it - the same
    // recipe as the browser's floating top pill, so the dock is clearly
    // visible over any page.
    expect(
      find.descendant(of: dock, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    final carrier = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: dock, matching: find.byType(DecoratedBox)),
        )
        .where((d) {
          final deco = d.decoration;
          return deco is BoxDecoration &&
              deco.color == MxColors.creamSoft.withValues(alpha: 0.92);
        });
    expect(carrier, isNotEmpty);
    // The carrier is purely visual: no per-icon material cell tints the
    // glyphs, so the active item still reads through its colour and scale.
    expect(
      find.descendant(of: dock, matching: find.byType(Material)),
      findsNothing,
    );
    // The icons themselves are there and the active one is marked.
    expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    expect(_navSelected(tester, 'Home'), isTrue);
  });

  testWidgets('focusing a text field hides the dock; leaving it restores it', (
    tester,
  ) async {
    await _pumpPager(
      tester,
      sections: <Widget>[
        const _InputSection(0),
        const _PlainSection(1),
        const _PlainSection(2),
        const _PlainSection(3),
        const _PlainSection(4),
      ],
    );
    final veil = find.byKey(const Key('pwa-keyboard-veil'));
    expect(tester.widget<AnimatedOpacity>(veil).opacity, 1.0);

    // An editable field takes focus -> the dock slips away.
    await tester.tap(find.byType(TextField), warnIfMissed: false);
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(veil).opacity, 0.0);

    // Focus leaves -> the dock returns untouched.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<AnimatedOpacity>(veil).opacity, 1.0);
  });

  testWidgets('a keyboard inset hides the dock and restoring it keeps the page', (
    tester,
  ) async {
    await _pumpPager(tester);
    // Scroll the section down first so there is state to preserve.
    await tester.drag(find.text('S0'), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final scroll = _sectionScroll(tester, 0);
    final pixels = scroll.position.pixels;
    expect(pixels, greaterThan(0));

    final veil = find.byKey(const Key('pwa-keyboard-veil'));
    expect(tester.widget<AnimatedOpacity>(veil).opacity, 1.0);

    // The platform reports a deep keyboard inset inside the layout viewport.
    tester.view.viewInsets = FakeViewPadding(bottom: 320);
    addTearDown(() => tester.view.viewInsets = FakeViewPadding());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<AnimatedOpacity>(veil).opacity, 0.0);
    // No layout jump, no navigation reset: the page stays exactly where it was.
    expect(scroll.position.pixels, pixels);

    // Keyboard dismissed: the dock returns, page still undisturbed.
    tester.view.viewInsets = FakeViewPadding();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<AnimatedOpacity>(veil).opacity, 1.0);
    expect(scroll.position.pixels, pixels);
  });

  testWidgets('tapping a dock item selects it, even near the strip edge', (
    tester,
  ) async {
    await _pumpPager(tester);
    // Journey sits three slots from Home — still tappable, no swipe needed.
    await tester.tap(
      find.byKey(const Key('pwa-nav-journey')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_page(tester), 3.0);
    expect(_navSelected(tester, 'Journey'), isTrue);
  });

  testWidgets('a nudge that settles on the current section leaves the page alone', (
    tester,
  ) async {
    await _pumpPager(tester);
    // Scroll Home well down first.
    await tester.drag(find.text('S0'), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_sectionScroll(tester, 0).position.pixels, greaterThan(0));

    // A small drag that returns to Home must not yank the page back to the
    // top — released-on-the-same-section only springs the strip.
    await _dragDock(tester, const Offset(-30, 0));
    expect(_page(tester), 0.0);
    expect(_sectionScroll(tester, 0).position.pixels, greaterThan(0));
  });

  testWidgets('tapping the current section scrolls it to the top (dock included)', (
    tester,
  ) async {
    await _pumpPager(tester);
    await tester.drag(find.text('S0'), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final scroll = _sectionScroll(tester, 0);
    expect(scroll.position.pixels, greaterThan(0));

    await tester.tap(
      find.byKey(const Key('pwa-nav-home')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, 0);
  });

  testWidgets('the large page footer stays on Home only; other sections carry none', (
    tester,
  ) async {
    await _pumpPager(tester);
    // Home's own subtree carries the footer...
    expect(
      find.descendant(
        of: find.byKey(const Key('pwa-section-0')),
        matching: find.byType(MxFooter),
      ),
      findsOneWidget,
    );
    // ...and each other destination renders none in its own subtree.
    for (var i = 1; i < 5; i++) {
      await _dragDock(tester, const Offset(-90, 0));
      expect(_page(tester), i.toDouble());
      expect(
        find.descendant(
          of: find.byKey(Key('pwa-section-$i')),
          matching: find.byType(MxFooter),
        ),
        findsNothing,
      );
    }
    // Walk back Home one section per drag (from the last section a single
    // far-end tap maps to the neighbour - drags stay exact at the edges).
    for (var i = 4; i > 0; i--) {
      await _dragDock(tester, const Offset(90, 0));
      expect(_page(tester), (i - 1).toDouble());
    }
    // Exactly one footer exists in the whole tree: the other sections never
    // mount one, in the cache band or after a revisit.
    expect(_page(tester), 0.0);
    expect(find.byType(MxFooter), findsOneWidget);
  });

  testWidgets('a section scrolled earlier opens at the top on its next arrival', (
    tester,
  ) async {
    await _pumpPager(tester);
    // Home: scroll well down (this also compresses the dock - and while the
    // dock is compressed its slots are shorter, so section changes happen
    // by tapping item centres, which always map to their exact item).
    await tester.drag(find.text('S0'), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final home = _sectionScroll(tester, 0);
    expect(home.position.pixels, greaterThan(0));

    // To Shop by tapping its glyph: Shop opens at the top (never scrolled).
    await tester.tap(
      find.byKey(const Key('pwa-nav-shop')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_page(tester), 1.0);
    expect(_sectionScroll(tester, 1).position.pixels, 0);

    // Scroll Shop down, then tap Home: Home must arrive at the top, not at
    // the position it was left in.
    await tester.drag(find.text('S1'), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_sectionScroll(tester, 1).position.pixels, greaterThan(0));

    await tester.tap(
      find.byKey(const Key('pwa-nav-home')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_page(tester), 0.0);
    expect(home.position.pixels, 0);
  });

  testWidgets('each successful section change fires exactly one subtle haptic', (
    tester,
  ) async {
    final ticks = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          ticks.add(call);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpPager(tester);
    // Home -> Shop: exactly one tick, of the subtle selection flavour.
    await _dragDock(tester, const Offset(-90, 0));
    expect(_page(tester), 1.0);
    expect(ticks.length, 1);
    // HapticFeedback.vibrate carries the tick type as its plain argument
    // (the HapticFeedbackType enum's toString on this Flutter version).
    expect(ticks.single.arguments, endsWith('selectionClick'));

    // Shop -> Farm: one more tick - and nothing repeats while settling.
    await _dragDock(tester, const Offset(-90, 0));
    expect(_page(tester), 2.0);
    expect(ticks.length, 2);

    // A nudge that settles back on Farm changes nothing: no tick.
    await _dragDock(tester, const Offset(-30, 0));
    expect(_page(tester), 2.0);
    expect(ticks.length, 2);
  });
}
