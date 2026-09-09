import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mycosix/models/order_notice.dart';
import 'package:mycosix/state/order_alert_controller.dart';
import 'package:mycosix/widgets/order_alert_host.dart';

/// The [OrderAlertHost] surface: an alert the controller raises appears as a
/// floating snackbar over the current page, dismissing it (or tapping the
/// action) clears it, and tapping the action routes without ever crashing even
/// when no named route is mounted. Firebase is never initialised here, so the
/// controller stays inert and only the directly-presented alerts drive the UI.
OrderAlert _customerAlert(String id) => OrderAlert(
      kind: OrderAlertKind.customerStatus,
      orderId: id,
      title: 'Order $id is confirmed',
      body: 'Your mushrooms are in the works.',
      actionLabel: 'View order',
    );

Future<OrderAlertController> _pumpHost(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = OrderAlertController();
  await tester.pumpWidget(
    ChangeNotifierProvider<OrderAlertController>.value(
      value: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OrderAlertHost(
          child: const Scaffold(body: Center(child: Text('page body'))),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('a presented alert appears as a snackbar with its action', (
      tester) async {
    final controller = await _pumpHost(tester);
    controller.present(_customerAlert('A1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('page body'), findsOneWidget);
    expect(find.text('Order A1 is confirmed'), findsOneWidget);
    expect(find.text('Your mushrooms are in the works.'), findsOneWidget);
    expect(find.text('View order'), findsOneWidget);
    // Let the controller's auto-dismiss (7s) and the snackbar's own timer run
    // out so no pending timer is left at teardown.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('dismissing clears the alert and its snackbar', (tester) async {
    final controller = await _pumpHost(tester);
    controller.present(_customerAlert('A2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Order A2 is confirmed'), findsOneWidget);
    controller.dismiss();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(controller.alert, isNull);
    expect(find.text('Order A2 is confirmed'), findsNothing);
    controller.dispose();
  });

  testWidgets('tapping the action dismisses and routes without crashing', (
      tester) async {
    final controller = await _pumpHost(tester);
    controller.present(_customerAlert('A3'));
    await tester.pumpAndSettle(); // finish the snackbar entrance before tapping
    expect(find.text('Order A3 is confirmed'), findsOneWidget);
    await tester.tap(find.byType(SnackBarAction));
    await tester.pumpAndSettle();
    // The action dismisses the alert; the route push is a no-op here because
    // no navigator is mounted under the shared key, so nothing may throw.
    expect(controller.alert, isNull);
    controller.dispose();
  });
}
