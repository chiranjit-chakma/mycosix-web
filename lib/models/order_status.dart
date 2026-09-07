/// Controlled order statuses.
///
/// Only an authorised admin may move an order between these states; Firestore
/// rules enforce the enum and the client never accepts an arbitrary string.
enum OrderStatus {
  newOrder('New'),
  contacted('Contacted'),
  confirmed('Confirmed'),
  preparing('Preparing'),
  outForDelivery('Out for Delivery'),
  delivered('Delivered'),
  cancelled('Cancelled');

  const OrderStatus(this.label);

  /// The exact label stored on the order document.
  final String label;

  /// The status shown to the customer in My Orders. Deliberately simpler than
  /// the admin-facing [label]: the admin's internal "New" and "Contacted"
  /// stages both read as "Pending", and "Out for Delivery" reads as "Out for
  /// delivery". Changes are live — whenever the admin updates the order, the
  /// next snapshot already carries the new status here.
  String get customerLabel => switch (this) {
        OrderStatus.newOrder => 'Pending',
        OrderStatus.contacted => 'Pending',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.preparing => 'Preparing',
        OrderStatus.outForDelivery => 'Out for delivery',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.cancelled => 'Cancelled',
      };

  /// How many of the four delivery-journey steps
  /// (Placed → Confirmed → On the way → Delivered) this status has reached.
  /// Cancelled orders have none — the tracker shows the cancelled state
  /// instead of a progress line.
  int get deliveryProgress => switch (this) {
        OrderStatus.newOrder => 1,
        OrderStatus.contacted => 1,
        OrderStatus.confirmed => 2,
        OrderStatus.preparing => 2,
        OrderStatus.outForDelivery => 3,
        OrderStatus.delivered => 4,
        OrderStatus.cancelled => 0,
      };

  static OrderStatus fromLabel(String? label) {
    for (final s in OrderStatus.values) {
      if (s.label == label) return s;
    }
    return OrderStatus.newOrder;
  }
}
