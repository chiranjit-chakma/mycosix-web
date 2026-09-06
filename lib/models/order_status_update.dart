import 'order_status.dart';

/// Canonical stored statuses. Kept as plain strings so Firestore security
/// rules can mirror the same allowlist server-side (they cannot see Dart enums).
const List<String> orderStatusLabels = <String>[
  'New',
  'Contacted',
  'Confirmed',
  'Preparing',
  'Out for Delivery',
  'Delivered',
  'Cancelled',
];

/// The canonical value written to the `status` field of an order document.
///
/// The stored value is the human label (`OrderStatus.label`), never the Dart
/// enum identifier (`OrderStatus.name`, e.g. `delivered`)  -  the enum name is
/// only a code symbol and silently fails `OrderStatus.fromLabel` on read-back.
String orderStatusField(OrderStatus status) => status.label;

/// Builds the Firestore update map for moving an order to [next].
///
/// [timestamp] is what the caller wants recorded as the change time  -  the app
/// passes `FieldValue.serverTimestamp()` so Firestore stamps it. When an order
/// moves to Delivered the same trusted timestamp is additionally recorded on
/// `deliveredAt`; that field is a one-way stamp and must never be sent for any
/// other transition (Firestore rules enforce this server-side too).
Map<String, Object?> orderStatusUpdateFields(
  OrderStatus next,
  Object timestamp,
) {
  return {
    'status': next.label,
    'updatedAt': timestamp,
    if (next == OrderStatus.delivered) 'deliveredAt': timestamp,
  };
}
