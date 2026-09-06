/// A customer request recorded by the farm team, linked to a shop order.
///
/// This is the zero-budget foundation of the request workflow. There is no paid
/// inbound-messaging/AI service yet, so a request arrives through WhatsApp,
/// phone or email and an admin records it here from the admin area. The model
/// keeps the exact customer request, the linked order and the admin decision;
/// a later trusted backend (Cloud Functions + a messaging provider) can create
/// these automatically in the same shape.
library;

/// Cancellation window that applies to a linked order created [window] ago.
/// A cancellation request recorded within this window is straightforward to
/// honour; outside it the admin sees a warning and decides manually.
const Duration orderCancelWindow = Duration(minutes: 15);

/// Canonical request types (mirrored in `firestore.rules`).
enum OrderRequestType {
  cancellation('Cancellation'),
  quantityChange('Quantity Change'),
  productChange('Product Change'),
  deliveryCorrection('Delivery Correction'),
  assistance('Assistance');

  const OrderRequestType(this.label);

  final String label;

  static OrderRequestType fromLabel(String? label) {
    for (final t in OrderRequestType.values) {
      if (t.label == label) return t;
    }
    return OrderRequestType.assistance;
  }
}

/// Plain-string mirror of [OrderRequestType] for the security rules allowlist.
const List<String> requestTypeLabels = <String>[
  'Cancellation',
  'Quantity Change',
  'Product Change',
  'Delivery Correction',
  'Assistance',
];

/// Canonical request statuses (mirrored in `firestore.rules`).
enum OrderRequestStatus {
  pending('Pending'),
  approved('Approved'),
  rejected('Rejected'),
  resolved('Resolved'),
  expired('Expired');

  const OrderRequestStatus(this.label);

  final String label;

  static OrderRequestStatus fromLabel(String? label) {
    for (final s in OrderRequestStatus.values) {
      if (s.label == label) return s;
    }
    return OrderRequestStatus.pending;
  }
}

/// Plain-string mirror of [OrderRequestStatus] for the security rules
/// allowlist. Firestore rules also restrict which transitions the admin can
/// write (see firestore.rules).
const List<String> requestStatusLabels = <String>[
  'Pending',
  'Approved',
  'Rejected',
  'Resolved',
  'Expired',
];

/// The single human step required to fulfil a request, shown to the admin.
/// Until a trusted backend can mutate orders by itself, every decision is a
/// note plus a manual step in another admin section  -  that is deliberate,
/// not a placeholder.
String manualStepFor(OrderRequestType type) {
  switch (type) {
    case OrderRequestType.cancellation:
      return 'Cancel the linked order in the Orders section, then mark this request Resolved.';
    case OrderRequestType.quantityChange:
      return 'Adjust the line quantity on the linked order in the Orders section.';
    case OrderRequestType.productChange:
      return 'Change the product line on the linked order in the Orders section.';
    case OrderRequestType.deliveryCorrection:
      return 'Update the delivery details on the linked order in the Orders section.';
    case OrderRequestType.assistance:
      return 'Answer the customer directly (WhatsApp/phone) and record the outcome.';
  }
}

/// Whether [orderCreatedAt] still falls inside the [orderCancelWindow].
bool isWithinCancelWindow(
  DateTime orderCreatedAt, {
  DateTime? now,
  Duration window = orderCancelWindow,
}) {
  final ref = now ?? DateTime.now();
  final elapsed = ref.difference(orderCreatedAt);
  return !elapsed.isNegative && elapsed <= window;
}

/// The exact moment the cancellation window closes for [orderCreatedAt].
DateTime cancelWindowEndsAt(
  DateTime orderCreatedAt, {
  Duration window = orderCancelWindow,
}) =>
    orderCreatedAt.add(window);

/// A recorded customer request.
class OrderRequest {
  const OrderRequest({
    required this.id,
    required this.requestType,
    required this.requestDetail,
    required this.status,
    this.orderId,
    this.orderStatusLabel,
    this.orderCreatedAt,
    this.customerName,
    this.phone,
    this.recordedAt,
    this.recordedByEmail,
    this.decisionAt,
    this.decidedByEmail,
    this.decisionNote,
  });

  /// Firestore document id. Empty before the request is persisted.
  final String id;

  final OrderRequestType requestType;

  /// What the customer actually asked, in the customer's words (recorded by
  /// the admin who received the WhatsApp/phone/email message).
  final String requestDetail;

  final OrderRequestStatus status;

  // Linked order snapshot (so the request row stands alone and is readable
  // even if the order row changes later).
  final String? orderId;
  final String? orderStatusLabel;
  final DateTime? orderCreatedAt;
  final String? customerName;
  final String? phone;

  final DateTime? recordedAt;
  final String? recordedByEmail;

  final DateTime? decisionAt;
  final String? decidedByEmail;
  final String? decisionNote;

  bool get open =>
      status == OrderRequestStatus.pending ||
      status == OrderRequestStatus.approved;

  OrderRequest copyWith({
    OrderRequestStatus? status,
    DateTime? decisionAt,
    String? decidedByEmail,
    String? decisionNote,
  }) {
    return OrderRequest(
      id: id,
      requestType: requestType,
      requestDetail: requestDetail,
      status: status ?? this.status,
      orderId: orderId,
      orderStatusLabel: orderStatusLabel,
      orderCreatedAt: orderCreatedAt,
      customerName: customerName,
      phone: phone,
      recordedAt: recordedAt,
      recordedByEmail: recordedByEmail,
      decisionAt: decisionAt ?? this.decisionAt,
      decidedByEmail: decidedByEmail ?? this.decidedByEmail,
      decisionNote: decisionNote ?? this.decisionNote,
    );
  }

  Map<String, Object?> toMap() => {
        'requestType': requestType.label,
        'requestDetail': requestDetail.trim(),
        'status': status.label,
        if (orderId != null && orderId!.isNotEmpty) 'orderId': orderId,
        if (orderStatusLabel != null && orderStatusLabel!.isNotEmpty)
          'orderStatusLabel': orderStatusLabel,
        if (customerName != null && customerName!.trim().isNotEmpty)
          'customerName': customerName!.trim(),
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
        if (recordedByEmail != null && recordedByEmail!.isNotEmpty)
          'recordedByEmail': recordedByEmail,
        if (decidedByEmail != null && decidedByEmail!.isNotEmpty)
          'decidedByEmail': decidedByEmail,
        if (decisionNote != null && decisionNote!.trim().isNotEmpty)
          'decisionNote': decisionNote!.trim(),
      };

  /// Builds the Firestore update map for an admin decision on this request.
  ///
  /// [timestamp] is the caller's `FieldValue.serverTimestamp()` so Firestore
  /// stamps the decision time. A decision never mutates the order itself  -  it
  /// records who decided, what and when; the manual order change happens in the
  /// Orders section (rules allowlist matches exactly these keys).
  Map<String, Object?> decisionFields(
    OrderRequestStatus next, {
    required Object timestamp,
    String? decidedByEmail,
    String? decisionNote,
  }) {
    return {
      'status': next.label,
      'decisionAt': timestamp,
      'updatedAt': timestamp,
      if (decidedByEmail != null && decidedByEmail.isNotEmpty)
        'decidedByEmail': decidedByEmail,
      if (decisionNote != null && decisionNote.trim().isNotEmpty)
        'decisionNote': decisionNote.trim(),
    };
  }

  factory OrderRequest.fromMap(
    Map<String, dynamic> map, {
    required String id,
    DateTime? orderCreatedAt,
    DateTime? recordedAt,
    DateTime? decisionAt,
  }) {
    return OrderRequest(
      id: id,
      requestType: OrderRequestType.fromLabel(map['requestType'] as String?),
      requestDetail: (map['requestDetail'] ?? '') as String,
      status: OrderRequestStatus.fromLabel(map['status'] as String?),
      orderId: map['orderId'] as String?,
      orderStatusLabel: map['orderStatusLabel'] as String?,
      orderCreatedAt: orderCreatedAt,
      customerName: map['customerName'] as String?,
      phone: map['phone'] as String?,
      recordedAt: recordedAt,
      recordedByEmail: map['recordedByEmail'] as String?,
      decisionAt: decisionAt,
      decidedByEmail: map['decidedByEmail'] as String?,
      decisionNote: map['decisionNote'] as String?,
    );
  }
}
