import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/order_status.dart';
import 'package:mycosix/models/order_status_update.dart';
import 'package:mycosix/models/store_order.dart';

void main() {
  group('orderStatusLabels', () {
    test('mirrors OrderStatus.values exactly, in order', () {
      const expected = <String>[
        'New',
        'Contacted',
        'Confirmed',
        'Preparing',
        'Out for Delivery',
        'Delivered',
        'Cancelled',
      ];
      expect(orderStatusLabels, expected);
      expect(orderStatusLabels.length, OrderStatus.values.length);
    });

    test('every canonical label round-trips through OrderStatus.fromLabel', () {
      for (final label in orderStatusLabels) {
        final s = OrderStatus.fromLabel(label);
        expect(s.label, label, reason: '$label must resolve back to itself');
      }
    });

    test('unknown or absent stored labels fall back to New, never throw', () {
      expect(OrderStatus.fromLabel('Shipped'), OrderStatus.newOrder);
      expect(OrderStatus.fromLabel(''), OrderStatus.newOrder);
      expect(OrderStatus.fromLabel(null), OrderStatus.newOrder);
    });
  });

  group('orderStatusField', () {
    test('writes the canonical label, never the Dart enum name', () {
      for (final s in OrderStatus.values) {
        expect(orderStatusField(s), s.label);
      }
      // Regression: OrderStatus.delivered.name is `delivered` (lowercase,
      // Dart identifier) while the stored value must be the label.
      expect(orderStatusField(OrderStatus.delivered), 'Delivered');
      expect(OrderStatus.delivered.name, isNot('Delivered'));
    });
  });

  group('orderStatusUpdateFields', () {
    // An opaque identity token stands in for FieldValue.serverTimestamp();
    // the helper must pass the caller's value through untouched.
    final stamp = Object();

    test('non-delivered transitions record status and updatedAt only', () {
      for (final s in OrderStatus.values) {
        if (s == OrderStatus.delivered) continue;
        final fields = orderStatusUpdateFields(s, stamp);
        expect(fields['status'], s.label);
        expect(fields['updatedAt'], same(stamp));
        expect(
          fields.containsKey('deliveredAt'),
          isFalse,
          reason: 'deliveredAt is a one-way stamp reserved for Delivered',
        );
      }
    });

    test('moving to Delivered additionally stamps deliveredAt', () {
      final fields = orderStatusUpdateFields(OrderStatus.delivered, stamp);
      expect(fields['status'], 'Delivered');
      expect(fields['updatedAt'], same(stamp));
      expect(fields['deliveredAt'], same(stamp));
    });
  });

  group('StoreOrder status persistence', () {
    Map<String, dynamic> minimal(Map<String, dynamic> extra) => <String, dynamic>{
          'orderId': 'MYC-AB12CD34',
          'customerName': 'A Name',
          'phone': '9876543210',
          'items': <dynamic>[],
          'subtotal': 0,
          'deliveryFee': 0,
          'total': 0,
          ...extra,
        };

    test('fromMap resolves a stored label to the matching enum', () {
      final o = StoreOrder.fromMap(minimal({'status': 'Delivered'}));
      expect(o.status, OrderStatus.delivered);
      expect(o.status.label, 'Delivered');
    });

    test('deliveredAt is threaded through fromMap unchanged', () {
      final at = DateTime.utc(2026, 9, 6, 12, 30);
      final o = StoreOrder.fromMap(
        minimal({'status': 'Delivered'}),
        deliveredAt: at,
      );
      expect(o.deliveredAt, at);
    });

    test('orders without deliveredAt read back as null', () {
      final o = StoreOrder.fromMap(minimal({'status': 'Confirmed'}));
      expect(o.deliveredAt, isNull);
    });
  });
}
