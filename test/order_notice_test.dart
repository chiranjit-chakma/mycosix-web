import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/models/order_notice.dart';
import 'package:mycosix/models/order_status.dart';

/// Pure-notification logic: which order events deserve a foreground alert and
/// the wording of each. These helpers are the single tested source of truth the
/// live watcher streams delegate to, so the no-duplicate and first-load-seeds-
/// silently contracts are locked here once.
///
/// Each snapshot row carries BOTH identities deliberately: `id` is the
/// Firestore document id (the stable, unique key used for state/dedupe) while
/// `code` is the human order number the customer sees on My Orders and in
/// WhatsApp. Tests keep them different to prove the two never get confused.
void main() {
  group('customerStatusHeadline', () {
    test('null when the status did not change', () {
      expect(
          customerStatusHeadline('A1', OrderStatus.confirmed,
              OrderStatus.confirmed),
          isNull);
      expect(
          customerStatusHeadline('A1', OrderStatus.preparing,
              OrderStatus.preparing),
          isNull);
    });

    test('null for statuses that do not interrupt the customer', () {
      expect(
          customerStatusHeadline('A1', OrderStatus.confirmed,
              OrderStatus.preparing),
          isNull);
      expect(
          customerStatusHeadline('A1', OrderStatus.preparing,
              OrderStatus.contacted),
          isNull);
    });

    test('wording for each notify-worthy destination', () {
      expect(
          customerStatusHeadline(
              'A1', OrderStatus.newOrder, OrderStatus.confirmed),
          'Order A1 is confirmed');
      expect(
          customerStatusHeadline(
              'A1', OrderStatus.contacted, OrderStatus.outForDelivery),
          'Order A1 is out for delivery');
      expect(
          customerStatusHeadline(
              'A1', OrderStatus.preparing, OrderStatus.delivered),
          'Order A1 has been delivered');
      expect(
          customerStatusHeadline(
              'A1', OrderStatus.preparing, OrderStatus.cancelled),
          'Order A1 was cancelled');
    });
  });

  group('customerStatusBody', () {
    test('a supporting line exists for every notify-worthy status', () {
      expect(customerStatusBody(OrderStatus.confirmed), isNotEmpty);
      expect(customerStatusBody(OrderStatus.outForDelivery), isNotEmpty);
      expect(customerStatusBody(OrderStatus.delivered), isNotEmpty);
      expect(customerStatusBody(OrderStatus.cancelled), isNotEmpty);
    });

    test('internal-only statuses stay quiet', () {
      expect(customerStatusBody(OrderStatus.newOrder), isEmpty);
      expect(customerStatusBody(OrderStatus.preparing), isEmpty);
    });
  });

  group('customerAlertsForSnapshot', () {
    test('first snapshot seeds silently and never alerts', () {
      final known = <String, String>{};
      final alerts = customerAlertsForSnapshot(
        known: known,
        rows: const [
          (id: 'docA', code: 'A1', status: OrderStatus.newOrder),
          (id: 'docB', code: 'A2', status: OrderStatus.delivered),
        ],
        seeded: false,
      );
      expect(alerts, isEmpty);
      // State is keyed by document id, never by the display code.
      expect(known, {'docA': 'New', 'docB': 'Delivered'});
    });

    test('a repeated snapshot of the same status never double-notifies', () {
      final known = <String, String>{};
      customerAlertsForSnapshot(
          known: known,
          rows: const [(id: 'docA', code: 'A1', status: OrderStatus.confirmed)],
          seeded: false);
      final second = customerAlertsForSnapshot(
          known: known,
          rows: const [(id: 'docA', code: 'A1', status: OrderStatus.confirmed)],
          seeded: true);
      expect(second, isEmpty);
      expect(known, {'docA': 'Confirmed'});
    });

    test('a real transition produces one alert carrying the human code', () {
      final known = <String, String>{};
      customerAlertsForSnapshot(
          known: known,
          rows: const [(id: 'docA', code: 'A1', status: OrderStatus.newOrder)],
          seeded: false);
      final alerts = customerAlertsForSnapshot(
        known: known,
        rows: const [(id: 'docA', code: 'A1', status: OrderStatus.confirmed)],
        seeded: true,
      );
      expect(alerts, hasLength(1));
      final a = alerts.single;
      expect(a.kind, OrderAlertKind.customerStatus);
      expect(a.orderId, 'A1'); // the code the customer recognises
      expect(a.title, 'Order A1 is confirmed');
      expect(a.body, customerStatusBody(OrderStatus.confirmed));
      expect(a.actionLabel, 'View order');
      expect(known, {'docA': 'Confirmed'});
    });

    test('a transition to an internal status is silent but state advances', () {
      final known = <String, String>{};
      customerAlertsForSnapshot(
          known: known,
          rows: const [(id: 'docA', code: 'A1', status: OrderStatus.confirmed)],
          seeded: false);
      final alerts = customerAlertsForSnapshot(
          known: known,
          rows: const [(id: 'docA', code: 'A1', status: OrderStatus.preparing)],
          seeded: true);
      expect(alerts, isEmpty);
      expect(known, {'docA': 'Preparing'});
    });

    test('a multi-row snapshot only alerts the rows that actually changed', () {
      final known = <String, String>{};
      customerAlertsForSnapshot(
        known: known,
        rows: const [
          (id: 'docA', code: 'A1', status: OrderStatus.newOrder),
          (id: 'docB', code: 'A2', status: OrderStatus.contacted),
        ],
        seeded: false,
      );
      final alerts = customerAlertsForSnapshot(
        known: known,
        rows: const [
          (id: 'docA', code: 'A1', status: OrderStatus.newOrder), // unchanged
          (id: 'docB', code: 'A2', status: OrderStatus.delivered), // changed
        ],
        seeded: true,
      );
      expect(alerts, hasLength(1));
      expect(alerts.single.orderId, 'A2');
      expect(alerts.single.title, 'Order A2 has been delivered');
    });

    test('a brand-new order appearing mid-session does not alert', () {
      // The customer placed it themselves - only a later status change is news.
      final known = <String, String>{};
      customerAlertsForSnapshot(
          known: known,
          rows: const [(id: 'docA', code: 'A1', status: OrderStatus.newOrder)],
          seeded: false);
      final alerts = customerAlertsForSnapshot(
        known: known,
        rows: const [
          (id: 'docA', code: 'A1', status: OrderStatus.newOrder),
          (id: 'docB', code: 'A9', status: OrderStatus.newOrder),
        ],
        seeded: true,
      );
      expect(alerts, isEmpty);
      expect(known, {'docA': 'New', 'docB': 'New'});
    });

    test('an order deleted and later re-added does not re-alert', () {
      final known = <String, String>{};
      customerAlertsForSnapshot(
          known: known,
          rows: const [(id: 'docA', code: 'A1', status: OrderStatus.confirmed)],
          seeded: false);
      // docA disappears (not in this snapshot) -> dropped from known.
      customerAlertsForSnapshot(
          known: known, rows: const <OrderStatusRow>[], seeded: true);
      expect(known, isEmpty);
      // Re-added already-Confirmed: no transition history, so silent.
      final alerts = customerAlertsForSnapshot(
          known: known,
          rows: const [(id: 'docA', code: 'A1', status: OrderStatus.confirmed)],
          seeded: true);
      expect(alerts, isEmpty);
    });

    test('two documents sharing a display code never conflate state', () {
      // The same human code can only come from a copy/import bug, but state
      // must stay per document id so one doc's transition cannot be swallowed
      // by the other's.
      final known = <String, String>{};
      customerAlertsForSnapshot(
        known: known,
        rows: const [
          (id: 'docA', code: 'X1', status: OrderStatus.newOrder),
          (id: 'docB', code: 'X1', status: OrderStatus.newOrder),
        ],
        seeded: false,
      );
      // docB moves to Confirmed; only docB may alert, and its code X1 shows.
      final alerts = customerAlertsForSnapshot(
        known: known,
        rows: const [
          (id: 'docA', code: 'X1', status: OrderStatus.newOrder),
          (id: 'docB', code: 'X1', status: OrderStatus.confirmed),
        ],
        seeded: true,
      );
      expect(alerts, hasLength(1));
      expect(alerts.single.orderId, 'X1');
      // And docA's later transition still alerts independently.
      final more = customerAlertsForSnapshot(
        known: known,
        rows: const [
          (id: 'docA', code: 'X1', status: OrderStatus.confirmed),
          (id: 'docB', code: 'X1', status: OrderStatus.confirmed),
        ],
        seeded: true,
      );
      expect(more, hasLength(1));
      expect(more.single.orderId, 'X1');
    });
  });

  group('adminNewOrderWorthy', () {
    test('the seeding snapshot never alerts but remembers the id', () {
      final everNew = <String>{};
      expect(adminNewOrderWorthy(everNew: everNew, id: 'docB', seeded: false),
          isFalse);
      expect(everNew, {'docB'});
    });

    test('a first sighting after seeding alerts exactly once', () {
      final everNew = <String>{};
      adminNewOrderWorthy(everNew: everNew, id: 'docB', seeded: false); // seed
      expect(adminNewOrderWorthy(everNew: everNew, id: 'docC', seeded: true),
          isTrue);
      expect(everNew, {'docB', 'docC'});
    });

    test('an id already seen never re-alerts, even cycling back to New', () {
      final everNew = <String>{};
      adminNewOrderWorthy(everNew: everNew, id: 'docB', seeded: false);
      expect(adminNewOrderWorthy(everNew: everNew, id: 'docB', seeded: true),
          isFalse);
      adminNewOrderWorthy(everNew: everNew, id: 'docC', seeded: true);
      expect(adminNewOrderWorthy(everNew: everNew, id: 'docC', seeded: true),
          isFalse);
    });
  });
}
