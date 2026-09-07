import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/order_status.dart';

/// The customer-facing status wording and the four-step delivery-journey
/// mapping used by the Zomato-style progress line in My Orders.
void main() {
  group('OrderStatus.customerLabel', () {
    test('reads plainly for the customer', () {
      expect(OrderStatus.newOrder.customerLabel, 'Pending');
      expect(OrderStatus.contacted.customerLabel, 'Pending');
      expect(OrderStatus.confirmed.customerLabel, 'Confirmed');
      expect(OrderStatus.preparing.customerLabel, 'Preparing');
      expect(OrderStatus.outForDelivery.customerLabel, 'Out for delivery');
      expect(OrderStatus.delivered.customerLabel, 'Delivered');
      expect(OrderStatus.cancelled.customerLabel, 'Cancelled');
    });
  });

  group('OrderStatus.deliveryProgress', () {
    test('fills the four delivery steps in order', () {
      // Placed -> Confirmed -> On the way -> Delivered
      expect(OrderStatus.newOrder.deliveryProgress, 1);
      expect(OrderStatus.contacted.deliveryProgress, 1);
      expect(OrderStatus.confirmed.deliveryProgress, 2);
      expect(OrderStatus.preparing.deliveryProgress, 2);
      expect(OrderStatus.outForDelivery.deliveryProgress, 3);
      expect(OrderStatus.delivered.deliveryProgress, 4);
      // Cancelled has no journey — the tracker shows the cancelled state.
      expect(OrderStatus.cancelled.deliveryProgress, 0);
    });
  });
}
