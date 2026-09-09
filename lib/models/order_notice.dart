import 'order_status.dart';

/// A foreground (app-open) alert the site can show the moment something worth
/// knowing happens, without the customer doing anything. These are Firestore-
/// driven and work today on the free plan; the closed-app/background push of
/// the same events is the FCM path (see the Cloud Functions notification
/// backend), which activates once the project moves to the paid plan.
///
/// Two kinds are produced:
///  - [OrderAlertKind.customerStatus]: one of the customer-visible order
///    statuses changed to a notify-worthy state (Confirmed, Out for Delivery,
///    Delivered, Cancelled). Only the owning customer can ever see it — the
///    underlying snapshot is the customer's own `orders` query, which the
///    Firestore rules already gate to that customer.
///  - [OrderAlertKind.adminNewOrder]: a brand-new order arrived in the admin
///    area. Only a signed-in administrator sees it; the alerting watcher runs
///    on the admin-scoped app and never touches the customer side.
enum OrderAlertKind { customerStatus, adminNewOrder }

/// The customer-facing statuses that warrant a notification. The admin's
/// internal "New" and "Contacted" stages deliberately do not interrupt a
/// customer; "Preparing" is a shop-internal step.
const Set<OrderStatus> kNotifyCustomerStatuses = {
  OrderStatus.confirmed,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
  OrderStatus.cancelled,
};

/// One alert ready to be shown (or already showing) in the [OrderAlertHost].
class OrderAlert {
  const OrderAlert({
    required this.kind,
    required this.orderId,
    required this.title,
    required this.body,
    required this.actionLabel,
  });

  final OrderAlertKind kind;

  /// The human order code (matches the WhatsApp/My Orders reference), used as
  /// the stable identity so a repeated snapshot never re-alerts.
  final String orderId;

  final String title;
  final String body;
  final String actionLabel;

  @override
  bool operator ==(Object other) =>
      other is OrderAlert &&
      other.kind == kind &&
      other.orderId == orderId &&
      other.title == title;

  @override
  int get hashCode => Object.hash(kind, orderId, title);
}

/// The customer status-transition headline. Returns a title when [next] is a
/// notify-worthy status and it differs from what was already shown
/// ([previous]). Pure, so the wording contract is unit-tested once.
String? customerStatusHeadline(
  String orderId,
  OrderStatus? previous,
  OrderStatus next,
) {
  if (previous == next) return null; // repeated snapshot of the same status
  if (!kNotifyCustomerStatuses.contains(next)) return null;
  return switch (next) {
    OrderStatus.confirmed => 'Order $orderId is confirmed',
    OrderStatus.outForDelivery => 'Order $orderId is out for delivery',
    OrderStatus.delivered => 'Order $orderId has been delivered',
    OrderStatus.cancelled => 'Order $orderId was cancelled',
    _ => null,
  };
}

/// The supporting line under a [customerStatusHeadline].
String customerStatusBody(OrderStatus next) => switch (next) {
  OrderStatus.confirmed => 'Your mushrooms are in the works.',
  OrderStatus.outForDelivery => 'Your mushrooms are on the way!',
  OrderStatus.delivered => 'Enjoy your fresh mushrooms — thank you!',
  OrderStatus.cancelled =>
    'No payment was taken. Message us on WhatsApp with any questions.',
  _ => '',
};

/// One row from the customer's own orders snapshot: the Firestore document id
/// (stable identity for dedupe/state), the human order code the customer sees
/// (`orderId` - the same code My Orders and WhatsApp show), and the status.
typedef OrderStatusRow = ({String id, String code, OrderStatus status});

/// Pure state machine for one customer-orders snapshot.
///
/// [known] maps orderId -> the last stored status label and is MUTATED to the
/// incoming snapshot so the next event diffs against it. [seeded] is false for
/// the very first snapshot, which must never interrupt the user (the customer
/// is opening the app, not watching a change). Returns the alerts (at most one
/// per row) a real transition warrants; a repeated snapshot of the same status
/// yields nothing, so updating an order to the status it already has can never
/// double-notify.
List<OrderAlert> customerAlertsForSnapshot({
  required Map<String, String> known,
  required Iterable<OrderStatusRow> rows,
  required bool seeded,
}) {
  final fresh = <String, String>{};
  final alerts = <OrderAlert>[];
  for (final row in rows) {
    fresh[row.id] = row.status.label;
    if (!seeded) continue; // first load seeds silently
    final previousRaw = known[row.id];
    if (previousRaw == null) continue; // brand-new doc appeared quietly
    final headline = customerStatusHeadline(
      row.code,
      OrderStatus.fromLabel(previousRaw),
      row.status,
    );
    if (headline != null) {
      alerts.add(
        OrderAlert(
          kind: OrderAlertKind.customerStatus,
          orderId: row.code,
          title: headline,
          body: customerStatusBody(row.status),
          actionLabel: 'View order',
        ),
      );
    }
  }
  known
    ..clear()
    ..addAll(fresh);
  return alerts;
}

/// Pure decision for the admin "new order" watcher: records [id] into
/// [everNew] and answers whether it deserves an alert — yes only once seeding
/// is complete and this id has never been seen before in the session. The
/// first snapshot (seeded == false) always returns false, and an order that
/// was already New earlier never re-alerts even if it cycles back to New.
bool adminNewOrderWorthy({
  required Set<String> everNew,
  required String id,
  required bool seeded,
}) {
  final neverSeen = everNew.add(id);
  return seeded && neverSeen;
}

/// One FCM data map (a backend push message), converted to the same alert the
/// Firestore watchers raise, so the foreground banner reads identically no
/// matter which channel delivered the event. Returns null when the message is
/// not a notify-worthy MYCOSIX push (unknown kind, or a status the customer is
/// not interrupted for).
///
/// The payload is minimal and never trusted as authorisation: the message only
/// reaches this device because the trusted backend targeted this account's own
/// tokens, and tapping the banner routes to a page whose data reads are still
/// rules-gated to the viewer.
OrderAlert? orderAlertForPushMessage({
  required String kind,
  required String orderDocId,
  required String orderCode,
  required String statusLabel,
}) {
  switch (kind) {
    case 'admin-new-order':
      return OrderAlert(
        kind: OrderAlertKind.adminNewOrder,
        orderId: orderCode,
        title: 'New order $orderCode',
        body: 'An order just arrived - review it when you are ready.',
        actionLabel: 'Review',
      );
    case 'order-status':
      final status = OrderStatus.fromLabel(statusLabel);
      if (!kNotifyCustomerStatuses.contains(status)) return null;
      final headline = customerStatusHeadline(orderCode, null, status);
      if (headline == null) return null;
      return OrderAlert(
        kind: OrderAlertKind.customerStatus,
        orderId: orderCode,
        title: headline,
        body: customerStatusBody(status),
        actionLabel: 'View order',
      );
    default:
      return null;
  }
}

/// A stable identity for ONE push event, shared by the FCM foreground channel
/// and the Firestore watchers so the same order event arriving twice (once per
/// channel) is never shown as two banners. [orderDocId] is the Firestore doc
/// id both channels carry; [statusLabel] is '' for admin new-order events.
String pushEventKey({
  required String kind,
  required String orderDocId,
  required String statusLabel,
}) {
  if (kind == 'admin-new-order') return 'admin-new-order:$orderDocId';
  return 'order-status:$orderDocId:$statusLabel';
}
