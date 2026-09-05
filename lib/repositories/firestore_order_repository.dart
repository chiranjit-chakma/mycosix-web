import 'package:cloud_functions/cloud_functions.dart';

import '../firebase/fb.dart';
import '../models/order_draft.dart';
import '../models/store_order.dart';
import 'order_repository.dart';

/// Client for the trusted order backend.
///
/// Every order the website submits goes through the `createOrder` Cloud
/// Function, which validates the draft against the real product catalogue and
/// site configuration and writes the order itself. The browser never touches
/// the `orders` collection directly, so manipulated totals cannot reach
/// Firestore.
class FirestoreOrderRepository implements OrderRepository {
  @override
  Future<StoreOrder> createOrder(OrderDraft draft) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createOrder')
          .call(draft.toCallableData());
      final data = (result.data as Map?)?.cast<String, dynamic>();
      if (data == null) {
        throw const OrderRejected(
          "We couldn't save your order. Please try again.",
        );
      }
      final saved = data['order'] as Map<String, dynamic>? ?? data;
      final id = data['id'] as String?;
      return _parse(saved, id: id);
    } on FirebaseFunctionsException catch (e) {
      // The function is not deployed yet, the project is not on Blaze, or the
      // request timed out: the trusted backend is simply not available. The
      // caller falls back to the WhatsApp-handoff flow — nothing is faked.
      const unavailable = {
        'unavailable',
        'not-found',
        'deadline-exceeded',
        'internal',
      };
      if (unavailable.contains(e.code)) {
        throw const BackendUnavailable();
      }
      throw OrderRejected(
        e.message ?? Fb.friendlyMessage(e),
        code: e.code,
      );
    }
  }

  static StoreOrder _parse(Map<String, dynamic> map, {String? id}) {
    return StoreOrder.fromMap(
      map,
      id: id ?? map['id'] as String?,
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  static DateTime? _date(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
