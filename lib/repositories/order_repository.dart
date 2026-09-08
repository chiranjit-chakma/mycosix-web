import '../models/order_draft.dart';
import '../models/store_order.dart';

/// Raised when no trusted backend (the `createOrder` Cloud Function) is
/// reachable — because it is not deployed, Firebase is offline, or the project
/// is not on the Blaze plan yet.
///
/// Callers must NOT fake the backend: when this is thrown the order simply is
/// not recorded by the trusted backend. Checkout then records a capture
/// ([OrderRepository.captureNewOrder]) so the order still reaches the admin
/// workflow, and if that too fails the order is not recorded anywhere
/// server-side and the customer is told honestly.
class BackendUnavailable implements Exception {
  const BackendUnavailable([
    this.message = 'The secure order service is not connected yet.',
  ]);

  final String message;

  @override
  String toString() => 'BackendUnavailable: $message';
}

/// Raised when the trusted backend refuses an order (invalid product, stock,
/// quantity, coordinates, etc.). [message] is customer-safe and may be shown
/// directly in the UI.
class OrderRejected implements Exception {
  const OrderRejected(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'OrderRejected($code): $message';
}

/// One product line for a browser-captured order.
///
/// productName/variant/weight help the admin pack, and the unit price the
/// customer actually saw at checkout is recorded as a reference ([unitPrice],
/// [lineTotal]) so a delivered capture can be recognised in sales analytics.
/// The amounts on a capture are never server-authoritative (`verified` is
/// false) — the admin confirms the cash total with the customer by phone
/// before packing, and Firestore rules still stop a customer from changing an
/// order's status or delivering anything themselves.
class CapturedOrderLine {
  const CapturedOrderLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.variant,
    this.weight,
  });

  final String productId;
  final String productName;
  final int quantity;

  /// The unit price the live catalogue showed at checkout (reference only).
  final double unitPrice;

  /// unitPrice x quantity (reference only).
  final double lineTotal;

  final String? variant;
  final String? weight;
}

/// Everything the browser may record about an order while the trusted backend
/// is unreachable. This is the ONLY path a customer request can write to
/// Firestore. Status is forced to 'New' and verified to false by the write
/// itself AND by security rules; the amount fields record what the customer
/// was shown and agreed at checkout (from the live catalogue), so the order
/// stays a real, analysable sale even while the secure backend is not
/// deployed — an admin's Delivered action is what makes those amounts count.
class CapturedOrderData {
  const CapturedOrderData({
    required this.orderId,
    required this.customerName,
    required this.phone,
    this.phoneVerified = false,
    required this.latitude,
    required this.longitude,
    required this.mapsUrl,
    required this.lines,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.currency = 'INR',
    this.email,
    this.customerId,
    this.building,
    this.apartment,
    this.landmark,
    this.instructions,
  });

  /// Customer-facing id, format `MYC-XXXXXXXX` (generated locally).
  final String orderId;

  final String customerName;
  final String phone;

  /// True only when this capture was made after the number was proven on the
  /// caller's own Firebase auth session (one-time-code verification). The
  /// Firestore rules pin this marker to the auth token's phone_number claim
  /// server-side, so a client can never stamp it on by itself.
  final bool phoneVerified;

  final String? email;

  /// The Firebase Auth uid of the customer account that was signed in at
  /// checkout, when there was one. Stamped by the caller and pinned to the
  /// signed-in user by the Firestore rules (a browser can never write someone
  /// else's id), so the customer's own My Orders view can find their orders
  /// and nobody else's. Null for guest checkout.
  final String? customerId;

  final double latitude;
  final double longitude;
  final String mapsUrl;

  final String? building;
  final String? apartment;
  final String? landmark;
  final String? instructions;

  final List<CapturedOrderLine> lines;

  /// Amounts the customer saw and agreed at checkout (subtotal / delivery fee
  /// / total) and the currency. Reference figures for the admin workflow —
  /// never server-authoritative, and never counted until an admin delivers.
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String currency;
}

/// Order persistence.
///
/// Real orders are created ONLY through a trusted backend
/// ([FirestoreOrderRepository.createOrder] calls the Cloud Function), so
/// client-side totals can never reach Firestore as a server-authoritative
/// order. When that backend is unreachable, [captureNewOrder] may record the
/// order so it still enters the admin workflow: status is pinned to 'New' and
/// verified to false, and the amount fields only record what the customer was
/// shown and agreed at checkout (never server-trusted).
abstract class OrderRepository {
  /// Creates an order through the trusted backend and returns the authoritative
  /// stored order (trusted prices, totals, order id, server timestamps).
  ///
  /// Throws [BackendUnavailable] when the trusted backend is not reachable, or
  /// [OrderRejected] when the backend refuses the order.
  Future<StoreOrder> createOrder(OrderDraft draft);

  /// Records an order document while the trusted backend is unreachable, so
  /// the order still reaches the admin Orders list and the normal confirmation
  /// workflow can follow (admin calls the customer, confirms the cash total,
  /// packs and delivers).
  ///
  /// The document is written with `status == 'New'`, `verified == false`, a
  /// server `createdAt`, and the amounts the customer was shown at checkout —
  /// the same enforcement is mirrored in Firestore rules (status/verified are
  /// pinned; the amount fields are bounded numbers; nothing here can change an
  /// existing order). Throws [BackendUnavailable] when no write is possible
  /// (Firebase offline / rules refuse), in which case the order was not
  /// recorded and the caller must tell the customer honestly.
  Future<void> captureNewOrder(CapturedOrderData data);
}

/// No trusted backend configured — used when Firebase is not initialised.
class LocalOrderRepository implements OrderRepository {
  const LocalOrderRepository();

  @override
  Future<StoreOrder> createOrder(OrderDraft draft) async {
    throw const BackendUnavailable();
  }

  @override
  Future<void> captureNewOrder(CapturedOrderData data) async {
    throw const BackendUnavailable(
      'Orders cannot be recorded while Firebase is offline.',
    );
  }
}
