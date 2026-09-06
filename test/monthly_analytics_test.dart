import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/analytics/monthly.dart';
import 'package:mycosix/models/batch.dart';
import 'package:mycosix/models/order_status.dart';
import 'package:mycosix/models/store_order.dart';

Batch batch({
  required String id,
  required String productionDate,
  int produced = 0,
  int sold = 0,
  int waste = 0,
}) {
  return Batch(
    id: id,
    batchId: 'MYCO-BATCH-$id',
    variety: 'Oyster',
    productionDate: productionDate,
    expectedHarvestDate: '2026-12-31',
    producedQty: produced,
    soldQty: sold,
    wasteQty: waste,
    status: BatchStatus.closed,
  );
}

StoreOrder delivered({
  required String orderId,
  required DateTime createdAt,
  double total = 100,
  int qty = 1,
}) {
  return StoreOrder(
    orderId: orderId,
    customerName: 'A Customer',
    phone: '+91 90000 00000',
    items: [
      StoreOrderLine(
        productId: 'p1',
        productName: 'Oyster',
        quantity: qty,
        unitPrice: total / qty,
        lineTotal: total,
      ),
    ],
    subtotal: total,
    deliveryFee: 0,
    total: total,
    currency: 'INR',
    latitude: 23.0,
    longitude: 86.0,
    mapsUrl: 'https://maps.app.goo.gl/xyz',
    status: OrderStatus.delivered,
    createdAt: createdAt,
    updatedAt: createdAt,
    deliveredAt: createdAt,
  );
}

void main() {
  test('groups production and delivered sales into their calendar months', () {
    final rows = buildMonthlyRows(
      batches: [
        batch(
          id: '2026-001',
          productionDate: '2026-01-10',
          produced: 100,
          sold: 40,
          waste: 5,
        ),
        batch(
          id: '2026-002',
          productionDate: '2026-02-03',
          produced: 80,
        ),
      ],
      deliveredOrders: [
        delivered(
          orderId: 'F1',
          createdAt: DateTime(2026, 2, 14, 10),
          total: 300,
          qty: 3,
        ),
      ],
    );

    expect(rows, hasLength(2));
    expect(rows.first.monthLabel, 'Jan 2026');
    expect(rows.first.monthKey, '2026-01');
    expect(rows.first.producedQty, 100);
    expect(rows.first.wasteQty, 5);
    expect(rows.first.batchSoldQty, 40);
    expect(rows.first.deliveredOrderCount, 0);
    expect(rows.first.revenue, 0);

    final feb = rows.last;
    expect(feb.monthLabel, 'Feb 2026');
    expect(feb.producedQty, 80);
    expect(feb.batchSoldQty, 0);
    expect(feb.deliveredOrderCount, 1);
    expect(feb.revenue, 300);
    expect(feb.unitsSold, 3);
  });

  test('empty inputs produce an empty table (no invented months)', () {
    expect(buildMonthlyRows(batches: const [], deliveredOrders: const []),
        isEmpty);
  });

  test('rows ascend across months that only have production', () {
    final rows = buildMonthlyRows(
      batches: [
        batch(
          id: '2026-010',
          productionDate: '2026-03-01',
          produced: 50,
          sold: 10,
        ),
      ],
      deliveredOrders: const [],
    );
    expect(rows, hasLength(1));
    expect(rows.single.month, 3);
    expect(rows.single.year, 2026);
    expect(rows.single.producedQty, 50);
  });

  test('a batch whose date is unparseable is ignored, not guessed', () {
    final rows = buildMonthlyRows(
      batches: [
        batch(id: '2026-099', productionDate: 'not-a-date', produced: 999),
        batch(
          id: '2026-001',
          productionDate: '2026-04-15',
          produced: 20,
        ),
      ],
      deliveredOrders: const [],
    );
    expect(rows, hasLength(1));
    expect(rows.single.producedQty, 20);
  });

  test('delivered order with no createdAt cannot be placed in a month', () {
    final missingTime = delivered(
      orderId: 'NOTIME',
      createdAt: DateTime(2026, 5, 1),
    );
    // Simulate the caller never handing over a timestamp.
    final noTime = StoreOrder(
      orderId: 'NOTIME',
      customerName: missingTime.customerName,
      phone: missingTime.phone,
      items: missingTime.items,
      subtotal: missingTime.subtotal,
      deliveryFee: 0,
      total: missingTime.total,
      currency: 'INR',
      latitude: 23.0,
      longitude: 86.0,
      mapsUrl: missingTime.mapsUrl,
      status: OrderStatus.delivered,
    );
    final rows = buildMonthlyRows(
      batches: const [],
      deliveredOrders: [noTime],
    );
    expect(rows, isEmpty);
  });

  test('months between earliest and latest that have no data are absent', () {
    final rows = buildMonthlyRows(
      batches: [
        batch(id: 'A', productionDate: '2026-01-05', produced: 10),
        batch(id: 'B', productionDate: '2026-04-05', produced: 10),
      ],
      deliveredOrders: const [],
    );
    // Jan, Feb, Mar, Apr iterated; only Jan and Apr have data.
    expect(rows.map((r) => r.month).toList(), [1, 4]);
  });
}
