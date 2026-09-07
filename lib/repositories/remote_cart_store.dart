import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/mx_config.dart';
import '../firebase/fb.dart';

/// Remote per-account cart storage: the `carts/{uid}` document.
///
/// This is a mirror of the local cart for signed-in customers, so the same
/// customer sees the same cart in the browser and in the installed app, on any
/// device. The local cart remains the instant UI source; every local change is
/// written through to the account document.
///
/// The remote copy is never trusted: quantities are sanitised on read (bounded
/// 1..max per line, unknown keys dropped), re-clamped against the live
/// catalogue when applied, and prices/stock are decided exclusively by the
/// order backend at checkout. A customer tampering with their own cart
/// document gains nothing — every value that matters is recomputed from the
/// catalogue at order time.
abstract class RemoteCartStore {
  Future<Map<String, int>> fetch(String uid);

  /// Live snapshots of the account cart. Emits the sanitised item map.
  Stream<Map<String, int>> watch(String uid);

  Future<void> push(String uid, Map<String, int> items);
}

class FirestoreRemoteCartStore implements RemoteCartStore {
  const FirestoreRemoteCartStore();

  static Map<String, int> _sanitize(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      if (key is String &&
          key.isNotEmpty &&
          key.length <= 100 &&
          value is int &&
          value >= 1 &&
          value <= MxConfig.maxUnitsPerProduct) {
        out[key] = value;
      }
    });
    return out;
  }

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      Fb.carts.doc(uid);

  @override
  Future<Map<String, int>> fetch(String uid) async {
    final snap = await _doc(uid).get();
    return _sanitize(snap.data()?['items']);
  }

  @override
  Stream<Map<String, int>> watch(String uid) {
    return _doc(uid)
        .snapshots()
        .map((doc) => _sanitize(doc.data()?['items']));
  }

  @override
  Future<void> push(String uid, Map<String, int> items) {
    return _doc(uid).set({
      'items': items,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
