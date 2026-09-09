import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/router/routes.dart';
import 'package:mycosix/state/admin_reveal.dart';

/// Records pushes to /admin and the current top route, so a test can prove a
/// summon navigated (or did not stack) without building the real router.
class _RouteProbe extends NavigatorObserver {
  int adminPushes = 0;
  String? top;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == Routes.admin) adminPushes++;
    top = route.settings.name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    top = previousRoute?.settings.name;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    top = previousRoute?.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    top = newRoute?.settings.name;
  }
}

/// The secret-code summon (and the toggle's Admin nav entry) must open the
/// admin page every time it is used in a session — not just on the first use
/// after an app launch. Regression: openAdmin() used to early-return whenever
/// the reveal stage was already `signIn`, so after the owner summoned once and
/// then left the admin page, typing the code again did nothing until the app
/// was reloaded. It must navigate again whenever /admin is not already the top
/// route, and must never stack /admin on itself.
void main() {
  final probe = _RouteProbe();
  final navKey = GlobalKey<NavigatorState>();

  setUp(() {
    AdminReveal.shared.resetForTest();
    probe.adminPushes = 0;
    probe.top = null;
    // Mirror main.dart: a summon navigates the app's root navigator to /admin.
    AdminReveal.shared.goToAdmin = () =>
        navKey.currentState?.pushNamed(Routes.admin);
  });

  tearDown(() => AdminReveal.shared.goToAdmin = null);

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: <NavigatorObserver>[
          probe,
          AdminReveal.shared.routeObserver,
        ],
        initialRoute: Routes.home,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('route:${settings.name}')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(probe.top, Routes.home);
  }

  testWidgets('a summon opens /admin again after leaving it — not once per '
      'app launch', (tester) async {
    await pumpApp(tester);

    // Summon #1 while on the public site: navigates to /admin.
    AdminReveal.shared.openAdmin();
    await tester.pumpAndSettle();
    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
    expect(probe.adminPushes, 1);
    expect(probe.top, Routes.admin);

    // The owner leaves the admin page (signs in / changes their mind / backs
    // out) and is back on the public route.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(probe.top, Routes.home);

    // Summon #2 in the same session: this used to do nothing.
    AdminReveal.shared.openAdmin();
    await tester.pumpAndSettle();
    expect(
      probe.adminPushes,
      2,
      reason: 'a repeat summon in the same session must re-navigate',
    );
    expect(probe.top, Routes.admin);

    // Summon while already on /admin: never stacks a second copy.
    AdminReveal.shared.openAdmin();
    await tester.pumpAndSettle();
    expect(probe.adminPushes, 2, reason: 'never stack /admin on itself');
    expect(probe.top, Routes.admin);
  });

  testWidgets('a summon from the fully hidden stage opens /admin', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(AdminReveal.shared.stage, AdminRevealStage.hidden);

    AdminReveal.shared.openAdmin();
    await tester.pumpAndSettle();

    expect(AdminReveal.shared.stage, AdminRevealStage.signIn);
    expect(probe.adminPushes, 1);
    expect(probe.top, Routes.admin);
  });
}
