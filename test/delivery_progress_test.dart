import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/order_status.dart';
import 'package:mycosix/widgets/delivery_progress.dart';

/// Loads the real bundled fonts so text metrics match production.
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The Zomato/Swiggy-style "line filling" tracker inside an order detail:
/// four delivery stages that fill up as the admin moves the order, and a
/// cancelled state instead of any progress when the order is cancelled.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  Widget wrap(OrderStatus status) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DeliveryProgress(status: status),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a pending order shows the tracker sitting at Placed',
      (tester) async {
    await tester.pumpWidget(wrap(OrderStatus.newOrder));

    expect(find.byKey(const Key('delivery-progress')), findsOneWidget);
    expect(
      find.byKey(const Key('delivery-progress-cancelled')),
      findsNothing,
    );
    expect(find.text('We have received your order'), findsOneWidget);
    for (final label in ['Placed', 'Confirmed', 'On the way', 'Delivered']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('out for delivery shows the delivery headline', (tester) async {
    await tester.pumpWidget(wrap(OrderStatus.outForDelivery));

    expect(find.text('Your order is out for delivery'), findsOneWidget);
    expect(find.text('On the way'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delivered order shows the completed headline', (tester) async {
    await tester.pumpWidget(wrap(OrderStatus.delivered));

    expect(find.text('Your order has been delivered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled order shows the cancelled state, no tracker',
      (tester) async {
    await tester.pumpWidget(wrap(OrderStatus.cancelled));

    expect(
      find.byKey(const Key('delivery-progress-cancelled')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('delivery-progress')), findsNothing);
    expect(find.text('Order cancelled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
