import '../models/order_draft.dart';
import '../models/store_order.dart';

/// Raised when no trusted backend (the `createOrder` Cloud Function) is
/// reachable — because it is not deployed, Firebase is offline, or the project
/// is not on the Blaze plan yet.
///
/// Callers must NOT fake the backend: when this is thrown the order simply is
/// not recorded by the trusted backend. Checkout then attempts a money-free
/// capture ([OrderRepository.captureNewOrder]) so the order still reaches the
/// admin workflow, and if that too fails the order is not recorded anywhere
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
/// Deliberately money-free: productName/variant/weight are kept only to help
/// the admin pack — the admin never trusts them for pricing, and Firestore
/// rules forbid any price, total or status field on a captured order.
class CapturedOrderLine {
  const CapturedOrderLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.variant,
    this.weight,
  });

  final String productId;
  final String productName;
  final int quantity;
  final String? variant;
  final String? weight;
}

/// Everything the browser may record about an order while the trusted backend
/// is unreachable. This is the ONLY path a customer request can write to
/// Firestore, and it carries no economics and no trust flags — status is forced
/// to 'New' and verified to false by the write itself AND by security rules.
class CapturedOrderData {
  const CapturedOrderData({
    required this.orderId,
    required this.customerName,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.mapsUrl,
    required this.lines,
    this.email,
    this.building,
    this.apartment,
    this.landmark,
    this.instructions,
  });

  /// Customer-facing id, format `MYC-XXXXXXXX` (generated locally).
  final String orderId;

  final String customerName;
  final String phone;
  final String? email;

  final double latitude;
  final double longitude;
  final String mapsUrl;

  final String? building;
  final String? apartment;
  final String? landmark;
  final String? instructions;

  final List<CapturedOrderLine> lines;
}

/// Order persistence.
///
/// Real orders are created ONLY through a trusted backend
/// ([FirestoreOrderRepository.createOrder] calls the Cloud Function), so
/// client-side totals can never reach Firestore. When that backend is
/// unreachable, [captureNewOrder] may record a strictly money-free copy so the
/// order still enters the admin workflow — never with customer-supplied
/// economics.
abstract class OrderRepository {
  /// Creates an order through the trusted backend and returns the authoritative
  /// stored order (trusted prices, totals, order id, server timestamps).
  ///
  /// Throws [BackendUnavailable] when the trusted backend is not reachable, or
  /// [OrderRejected] when the backend refuses the order.
  Future<StoreOrder> createOrder(OrderDraft draft);

  /// Records a money-free order document while the trusted backend is
  /// unreachable, so the order still reaches the admin Orders list and the
  /// normal confirmation workflow can follow (admin calls the customer,
  /// confirms the cash total, packs and delivers).
  ///
  /// The document is written with `status == 'New'`, `verified == false` and a
  /// server `createdAt`, and NO economic fields — the same enforcement is
  /// mirrored in Firestore rules. Throws [BackendUnavailable] when no write is
  /// possible (Firebase offline / rules refuse), in which case the order was
  /// not recorded and the caller must tell the customer honestly.
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
