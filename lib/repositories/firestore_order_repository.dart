import 'package:cloud_firestore/cloud_firestore.dart';
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

  @override
  Future<void> captureNewOrder(CapturedOrderData data) async {
    try {
      // Money-free by construction AND by security rules. status/verified are
      // pinned here (never read from the customer) and createdAt is the server
      // clock. Firestore rules re-enforce all of it on the write.
      await Fb.orders.add({
        'orderId': data.orderId,
        'customerName': data.customerName,
        'phone': data.phone,
        if (data.email != null && data.email!.trim().isNotEmpty)
          'email': data.email!.trim(),
        'latitude': data.latitude,
        'longitude': data.longitude,
        'mapsUrl': data.mapsUrl,
        if (data.building != null && data.building!.trim().isNotEmpty)
          'building': data.building!.trim(),
        if (data.apartment != null && data.apartment!.trim().isNotEmpty)
          'apartment': data.apartment!.trim(),
        if (data.landmark != null && data.landmark!.trim().isNotEmpty)
          'landmark': data.landmark!.trim(),
        if (data.instructions != null && data.instructions!.trim().isNotEmpty)
          'instructions': data.instructions!.trim(),
        'items': [
          for (final l in data.lines)
            {
              'productId': l.productId,
              'productName': l.productName,
              'quantity': l.quantity,
              if (l.variant != null && l.variant!.trim().isNotEmpty)
                'variant': l.variant!.trim(),
              if (l.weight != null && l.weight!.trim().isNotEmpty)
                'weight': l.weight!.trim(),
            },
        ],
        'status': 'New',
        'verified': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Rules refusal, offline, or anything else: the order was NOT recorded.
      // Never pretend it was.
      throw BackendUnavailable(
        'Your order could not be recorded right now. Please try again.',
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
