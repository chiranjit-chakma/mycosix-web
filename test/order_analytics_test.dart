import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/analytics/order_analytics.dart';
import 'package:mycosix/models/order_status.dart';
import 'package:mycosix/models/store_order.dart';

/// Builds a stored order. Money values mirror what the trusted backend wrote.
StoreOrder order({
  String orderId = 'MYC-AA000001',
  OrderStatus status = OrderStatus.delivered,
  double total = 100,
  List<(String, int, double)> lines = const <(String, int, double)>[
    ('Pink Oyster 200g', 1, 100),
  ],
  DateTime? createdAt,
}) {
  final items = <StoreOrderLine>[
    for (final (name, qty, unit) in lines)
      StoreOrderLine(
        productId: 'p-$name',
        productName: name,
        quantity: qty,
        unitPrice: unit,
        lineTotal: unit * qty,
      ),
  ];
  return StoreOrder(
    orderId: orderId,
    customerName: 'A Customer',
    phone: '+91 90000 00000',
    items: items,
    subtotal: total,
    deliveryFee: 0,
    total: total,
    currency: 'INR',
    latitude: 23.0,
    longitude: 86.0,
    mapsUrl: 'https://maps.app.goo.gl/xyz',
    status: status,
    createdAt: createdAt,
    updatedAt: createdAt,
    deliveredAt: status == OrderStatus.delivered ? createdAt : null,
  );
}

void main() {
  group('computeSalesMetrics', () {
    test('revenue counts only Delivered orders; cancelled is never a sale', () {
      final metrics = computeSalesMetrics([
        order(orderId: 'A', status: OrderStatus.delivered, total: 300),
        order(orderId: 'B', status: OrderStatus.delivered, total: 200),
        order(orderId: 'C', status: OrderStatus.cancelled, total: 999),
        order(orderId: 'D', status: OrderStatus.newOrder, total: 50),
      ]);
      expect(metrics.ordersCount, 4);
      expect(metrics.deliveredCount, 2);
      expect(metrics.cancelledCount, 1);
      expect(metrics.revenue, 500);
      expect(metrics.averageOrderValue, 250);
    });

    test('average order value is zero when nothing delivered', () {
      final metrics = computeSalesMetrics([
        order(orderId: 'A', status: OrderStatus.cancelled, total: 50),
      ]);
      expect(metrics.revenue, 0);
      expect(metrics.averageOrderValue, 0);
    });

    test('quantity sold and best-sellers come from Delivered lines only', () {
      final metrics = computeSalesMetrics([
        order(
          orderId: 'A',
          status: OrderStatus.delivered,
          lines: const [
            ('Oyster 500g', 2, 150),
            ('Pink Oyster 200g', 1, 90),
            ('Oyster 500g', 1, 150),
          ],
        ),
        // Cancelled order with a big line must NOT contribute.
        order(
          orderId: 'B',
          status: OrderStatus.cancelled,
          lines: const [('Gold Oyster 200g', 50, 200)],
        ),
      ]);
      expect(metrics.quantitySold, 4);
      expect(metrics.bestSellers, hasLength(2));
      expect(metrics.bestSellers.first.productName, 'Oyster 500g');
      expect(metrics.bestSellers.first.quantity, 3);
      expect(metrics.bestSellers.first.revenue, 450);
      expect(
        metrics.bestSellers.any((b) => b.productName == 'Gold Oyster 200g'),
        isFalse,
      );
    });

    test('best-seller revenue is the delivered line totals', () {
      final metrics = computeSalesMetrics([
        order(
          orderId: 'A',
          status: OrderStatus.delivered,
          lines: const [('Pink Oyster 200g', 2, 90)],
        ),
      ]);
      expect(metrics.bestSellers.single.revenue, 180);
    });

    test('empty input gives a zeroed result, never fabricated rows', () {
      final metrics = computeSalesMetrics(const []);
      expect(metrics.ordersCount, 0);
      expect(metrics.deliveredCount, 0);
      expect(metrics.revenue, 0);
      expect(metrics.averageOrderValue, 0);
      expect(metrics.bestSellers, isEmpty);
      // Breakdown still lists all seven statuses at zero (canonical order).
      expect(metrics.breakdown, hasLength(7));
      expect(metrics.breakdown.every((s) => s.count == 0), isTrue);
      expect(metrics.breakdown.first.status, OrderStatus.newOrder);
    });

    test('breakdown counts every status including non-delivered', () {
      final metrics = computeSalesMetrics([
        order(orderId: 'A', status: OrderStatus.delivered),
        order(orderId: 'B', status: OrderStatus.cancelled),
        order(orderId: 'C', status: OrderStatus.preparing),
        order(orderId: 'D', status: OrderStatus.delivered),
      ]);
      final counts = {for (final s in metrics.breakdown) s.status: s.count};
      expect(counts[OrderStatus.delivered], 2);
      expect(counts[OrderStatus.cancelled], 1);
      expect(counts[OrderStatus.preparing], 1);
      expect(counts[OrderStatus.outForDelivery], 0);
    });

    test('revenue is unaffected by delivery fee-only differences', () {
      final withFee = StoreOrder(
        orderId: 'F',
        customerName: 'A Customer',
        phone: '+91 90000 00000',
        items: const [
          StoreOrderLine(
            productId: 'p1',
            productName: 'Oyster 500g',
            quantity: 1,
            unitPrice: 150,
            lineTotal: 150,
          ),
        ],
        subtotal: 150,
        deliveryFee: 49,
        total: 199,
        currency: 'INR',
        latitude: 23.0,
        longitude: 86.0,
        mapsUrl: 'https://maps.app.goo.gl/xyz',
        status: OrderStatus.delivered,
        createdAt: DateTime(2026, 9, 6),
        deliveredAt: DateTime(2026, 9, 6),
      );
      final metrics = computeSalesMetrics([withFee]);
      // The real total a delivered customer paid includes the delivery fee.
      expect(metrics.revenue, 199);
      expect(metrics.quantitySold, 1);
    });
  });
}
