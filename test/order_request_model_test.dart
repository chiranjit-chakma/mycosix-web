import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/order_request.dart';

void main() {
  group('request type/status labels', () {
    test('labels are the stored canonical values', () {
      expect(OrderRequestType.cancellation.label, 'Cancellation');
      expect(OrderRequestType.quantityChange.label, 'Quantity Change');
      expect(requestTypeLabels, contains('Cancellation'));
      expect(requestTypeLabels, contains('Assistance'));
      expect(requestStatusLabels, contains('Resolved'));
    });

    test('unknown labels fall back safely', () {
      expect(OrderRequestType.fromLabel('nonsense'), OrderRequestType.assistance);
      expect(OrderRequestStatus.fromLabel('nonsense'), OrderRequestStatus.pending);
      expect(OrderRequestType.fromLabel(null), OrderRequestType.assistance);
      expect(OrderRequestStatus.fromLabel(null), OrderRequestStatus.pending);
    });
  });

  group('cancel window', () {
    final placed = DateTime(2026, 9, 6, 10, 0);

    test('inside the window returns true', () {
      expect(
        isWithinCancelWindow(placed, now: placed.add(const Duration(minutes: 14))),
        isTrue,
      );
    });

    test('exactly at the window edge is still inside', () {
      expect(
        isWithinCancelWindow(placed, now: placed.add(const Duration(minutes: 15))),
        isTrue,
      );
    });

    test('after the window returns false', () {
      expect(
        isWithinCancelWindow(placed, now: placed.add(const Duration(minutes: 16))),
        isFalse,
      );
    });

    test('a request recorded before the order is not inside', () {
      expect(
        isWithinCancelWindow(placed, now: placed.subtract(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('window end is order time plus 15 minutes', () {
      expect(cancelWindowEndsAt(placed), placed.add(const Duration(minutes: 15)));
    });
  });

  group('manual intervention step', () {
    test('every type names a manual step, none claim automation', () {
      for (final type in OrderRequestType.values) {
        final step = manualStepFor(type);
        expect(step, isNotEmpty);
        // Zero-budget guarantee: no step may claim a system did the change.
        expect(step.toLowerCase().contains('automatically'), isFalse,
            reason: '$type step must be manual');
      }
    });

    test('a cancellation names the Orders section', () {
      expect(
        manualStepFor(OrderRequestType.cancellation),
        contains('Orders section'),
      );
    });
  });

  group('OrderRequest model', () {
    test('round-trips through toMap/fromMap', () {
      final original = OrderRequest(
        id: 'r1',
        requestType: OrderRequestType.quantityChange,
        requestDetail: 'Please reduce Pink Oyster from 2 to 1 pack.',
        status: OrderRequestStatus.approved,
        orderId: 'MYC-ABC12345',
        orderStatusLabel: 'Preparing',
        customerName: 'A Customer',
        phone: '+91 90000 00000',
        decisionNote: 'Will adjust before packing.',
      );
      final restored = OrderRequest.fromMap(
        original.toMap(),
        id: 'r1',
        orderCreatedAt: original.orderCreatedAt,
        recordedAt: original.recordedAt,
        decisionAt: original.decisionAt,
      );
      expect(restored.requestType, OrderRequestType.quantityChange);
      expect(restored.requestDetail, original.requestDetail);
      expect(restored.status, OrderRequestStatus.approved);
      expect(restored.orderId, 'MYC-ABC12345');
      expect(restored.orderStatusLabel, 'Preparing');
      expect(restored.customerName, 'A Customer');
      expect(restored.phone, '+91 90000 00000');
      expect(restored.decisionNote, 'Will adjust before packing.');
    });

    test('timestamps come from the caller, not the map', () {
      final docTime = DateTime(2026, 9, 6, 11, 30);
      final restored = OrderRequest.fromMap(
        {
          'requestType': 'Assistance',
          'requestDetail': 'How long does a pack last?',
          'status': 'Pending',
        },
        id: 'r2',
        orderCreatedAt: docTime,
        recordedAt: docTime,
      );
      expect(restored.recordedAt, docTime);
      expect(restored.orderCreatedAt, docTime);
      expect(restored.requestType, OrderRequestType.assistance);
    });

    test('open reflects pending/approved only', () {
      OrderRequest make(OrderRequestStatus s) => OrderRequest(
            id: '',
            requestType: OrderRequestType.cancellation,
            requestDetail: 'Cancel it.',
            status: s,
          );
      expect(make(OrderRequestStatus.pending).open, isTrue);
      expect(make(OrderRequestStatus.approved).open, isTrue);
      expect(make(OrderRequestStatus.rejected).open, isFalse);
      expect(make(OrderRequestStatus.resolved).open, isFalse);
      expect(make(OrderRequestStatus.expired).open, isFalse);
    });

    test('copyWith records a decision without losing the request', () {
      final r = OrderRequest(
        id: 'r3',
        requestType: OrderRequestType.cancellation,
        requestDetail: 'Changed my mind.',
        status: OrderRequestStatus.pending,
        orderId: 'MYC-AA000001',
      );
      final decided = r.copyWith(
        status: OrderRequestStatus.rejected,
        decidedByEmail: 'owner@mycosix.in',
        decisionAt: DateTime(2026, 9, 6, 12, 0),
        decisionNote: 'Too late to cancel; already dispatched.',
      );
      expect(decided.status, OrderRequestStatus.rejected);
      expect(decided.orderId, 'MYC-AA000001');
      expect(decided.requestDetail, 'Changed my mind.');
      expect(decided.decidedByEmail, 'owner@mycosix.in');
      // Original is untouched.
      expect(r.status, OrderRequestStatus.pending);
      expect(r.decidedByEmail, isNull);
    });
  });
}
