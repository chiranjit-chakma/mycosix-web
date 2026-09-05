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

  static OrderStatus fromLabel(String? label) {
    for (final s in OrderStatus.values) {
      if (s.label == label) return s;
    }
    return OrderStatus.newOrder;
  }
}
