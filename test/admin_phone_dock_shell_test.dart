import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/pages/pwa/pwa_admin_dock_shell.dart';
import 'package:mycosix/pages/pwa/pwa_dock.dart';
import 'package:mycosix/pages/pwa/pwa_registry.dart';
import 'package:mycosix/router/routes.dart';

/// A plain host page the shell wraps.
class _Host extends StatelessWidget {
  const _Host({this.withField = false});

  final bool withField;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: withField
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  key: const Key('host-field'),
                  decoration: const InputDecoration(labelText: 'Type here'),
                ),
              )
            : const Center(child: Text('host body', key: Key('host-body'))),
      ),
    );
  }
}

/// Pumps [PwaAdminDockShell] around [_Host] on a phone-sized screen. Each
/// pump gets a fresh UniqueKey so the dock State never carries over between
/// pumps inside one test.
Future<void> _pumpShell(
  WidgetTester tester, {
  required bool forceDock,
  bool withField = false,
  Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{},
}) async {
  tester.view.physicalSize = const Size(480, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: routes,
      home: PwaAdminDockShell(
        key: UniqueKey(),
        forceDock: forceDock,
        child: _Host(withField: withField),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

PwaDock _dock(WidgetTester tester) =>
    tester.widget<PwaDock>(find.byKey(const Key('admin-phone-dock')));

/// Taps dock slot [target] (0..5) at its on-strip position. A freshly-pumped
/// dock rests on the Admin slot (4), so slot [target] sits [target-4] pitches
/// from the capsule's centre. Only slots within reach of a single tap are
/// exercised here — the far end of the strip needs a drag, as in the real app.
Future<void> _tapDockSlot(WidgetTester tester, int target) async {
  final rect = tester.getRect(find.byKey(const Key('admin-phone-dock')));
  final screenWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final slot = math.min(66.0, (screenWidth - 24.0) / 6);
  final cx = rect.left + rect.width / 2 + (target - 4) * slot;
  await tester.tapAt(Offset(cx, rect.center.dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Drags the strip horizontally by [dx] with a real touch stream (tester.drag
/// splits the slop-crossing move, so the strip's onUpdate sees the movement),
/// then settles past the dock's snap. The dock is a carousel: dragging RIGHT
/// walks toward the FIRST section (Farm), LEFT toward the last (Profile).
Future<void> _dragDock(WidgetTester tester, double dx) async {
  await tester.drag(
    find.byKey(const Key('admin-phone-dock')),
    Offset(dx, 0),
    warnIfMissed: false,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

bool _navSelected(WidgetTester tester, String label) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .any((s) => s.properties.selected == true && s.properties.label == label);
}

void main() {
  tearDown(() => PwaRegistry.switchToSection = null);

  testWidgets(
    'dock not applied returns the child unchanged (browser/toggle-off)',
    (tester) async {
      await _pumpShell(tester, forceDock: false);
      expect(find.byKey(const Key('host-body')), findsOneWidget);
      expect(find.byKey(const Key('admin-phone-dock')), findsNothing);
    },
  );

  testWidgets('dock applied shows the six destinations with Admin selected', (
    tester,
  ) async {
    await _pumpShell(tester, forceDock: true);
    expect(find.byKey(const Key('host-body')), findsOneWidget);
    final labels = _dock(tester).labels;
    expect(labels, hasLength(6));
    expect(
      labels,
      const <String>[
        'Farm',
        'Shop',
        'Home',
        'Journey',
        'Admin',
        'Profile',
      ],
    );
    expect(_navSelected(tester, 'Admin'), isTrue);
    expect(_navSelected(tester, 'Home'), isFalse);
  });

  testWidgets('tapping a section hands the destination to the live pager', (
    tester,
  ) async {
    final switched = <String>[];
    PwaRegistry.switchToSection = (route) {
      switched.add(route);
      return true;
    };
    const expected = <int, String>{
      5: Routes.profile,
      2: Routes.home,
      3: Routes.journey,
      1: Routes.shop,
    };
    for (final entry in expected.entries) {
      await _pumpShell(tester, forceDock: true);
      await _tapDockSlot(tester, entry.key);
    }
    expect(switched, <String>[
      Routes.profile,
      Routes.home,
      Routes.journey,
      Routes.shop,
    ]);
  });

  testWidgets('a drag to the far Farm slot also leaves Admin', (tester) async {
    final switched = <String>[];
    PwaRegistry.switchToSection = (route) {
      switched.add(route);
      return true;
    };
    await _pumpShell(tester, forceDock: true);
    // Farm (slot 0) sits four slots to the RIGHT of the resting Admin slot
    // (4): a long rightward drag runs past it and clamps at the first section.
    await _dragDock(tester, 430);
    expect(switched, <String>[Routes.farm]);
  });

  testWidgets('the Admin slot (this page) never navigates', (tester) async {
    final switched = <String>[];
    PwaRegistry.switchToSection = (route) {
      switched.add(route);
      return true;
    };
    await _pumpShell(tester, forceDock: true);

    await _tapDockSlot(tester, 4); // Admin — already here.
    expect(switched, isEmpty);
    expect(find.byKey(const Key('host-body')), findsOneWidget);
    expect(find.byKey(const Key('admin-phone-dock')), findsOneWidget);
  });

  testWidgets('without a pager the section route replaces the admin page', (
    tester,
  ) async {
    Widget marker(String tag) => Scaffold(
      body: Center(child: Text(tag, key: Key('route-$tag'))),
    );
    // No '/' entry: home already provides that route, and the routes table
    // cannot redeclare it.
    await _pumpShell(
      tester,
      forceDock: true,
      routes: <String, WidgetBuilder>{
        Routes.shop: (_) => marker('shop'),
        Routes.journey: (_) => marker('journey'),
        Routes.farm: (_) => marker('farm'),
        Routes.profile: (_) => marker('profile'),
      },
    );

    await _tapDockSlot(tester, 5); // Profile
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('route-profile')), findsOneWidget);
    expect(find.byKey(const Key('host-body')), findsNothing);
  });

  testWidgets('the dock hides while a field is focused and returns after', (
    tester,
  ) async {
    await _pumpShell(tester, forceDock: true, withField: true);
    expect(find.byKey(const Key('admin-phone-dock')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('host-field')), 'hello');
    await tester.pump();
    expect(find.byKey(const Key('admin-phone-dock')), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('admin-phone-dock')), findsOneWidget);
  });

  testWidgets('a large keyboard inset alone hides the dock, no field needed', (
    tester,
  ) async {
    await _pumpShell(tester, forceDock: true);
    expect(find.byKey(const Key('admin-phone-dock')), findsOneWidget);

    // The on-screen keyboard reporting a tall inset (some browsers/keyboards
    // open with no field focused) must still clear the dock so it can never
    // sit on top of typed or tapped content.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    expect(find.byKey(const Key('admin-phone-dock')), findsNothing);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('admin-phone-dock')), findsOneWidget);
  });
}
