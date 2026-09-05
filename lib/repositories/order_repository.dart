import '../models/order_draft.dart';
import '../models/store_order.dart';

/// Raised when no trusted backend (the `createOrder` Cloud Function) is
/// reachable — because it is not deployed, Firebase is offline, or the project
/// is not on the Blaze plan yet.
///
/// Callers must NOT fake the backend: when this is thrown the order simply is
/// not recorded server-side, and the app falls back to the WhatsApp-handoff
/// flow from Part 1 (which remains fully functional).
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

/// Order persistence.
///
/// Orders are created ONLY through a trusted backend ([FirestoreOrderRepository]
/// calls the Cloud Function); the browser never writes an order document
/// directly, so client-side totals can never reach Firestore.
abstract class OrderRepository {
  /// Creates an order through the trusted backend and returns the authoritative
  /// stored order (trusted prices, totals, order id, server timestamps).
  ///
  /// Throws [BackendUnavailable] when the trusted backend is not reachable, or
  /// [OrderRejected] when the backend refuses the order.
  Future<StoreOrder> createOrder(OrderDraft draft);
}

/// No trusted backend configured — used when Firebase is not initialised.
class LocalOrderRepository implements OrderRepository {
  const LocalOrderRepository();

  @override
  Future<StoreOrder> createOrder(OrderDraft draft) async {
    throw const BackendUnavailable();
  }
}
