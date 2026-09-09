import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/mx_config.dart';
import '../firebase/fb.dart';

/// What one device sees / writes for the account cart: the item map plus the
/// account's REMOVAL TOMBSTONES.
///
/// `removed` is the account-wide list of product ids a signed-in customer has
/// removed from the cart (newest appended last). It is what lets a removal on
/// one device propagate: another device still holding such an item drops it,
/// and a device that removed it never lets a stale snapshot resurrect it. An
/// explicit re-add on any device lifts the tombstone again.
class RemoteCartSnapshot {
  const RemoteCartSnapshot({required this.items, this.removed = const []});

  final Map<String, int> items;

  /// Tombstoned product ids, oldest first, newest last. Bounded (the newest
  /// 100 survive reads and writes).
  final List<String> removed;

  bool get isEmpty => items.isEmpty && removed.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RemoteCartSnapshot) return false;
    if (items.length != other.items.length) return false;
    for (final entry in items.entries) {
      if (other.items[entry.key] != entry.value) return false;
    }
    if (removed.length != other.removed.length) return false;
    for (var i = 0; i < removed.length; i++) {
      if (removed[i] != other.removed[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(items, removed);
}

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
  Future<RemoteCartSnapshot> fetch(String uid);

  /// Live snapshots of the account cart. Emits the sanitised snapshot.
  Stream<RemoteCartSnapshot> watch(String uid);

  Future<void> push(String uid, RemoteCartSnapshot snapshot);
}

class FirestoreRemoteCartStore implements RemoteCartStore {
  const FirestoreRemoteCartStore();

  /// The longest a tombstone list may grow; past this, the OLDEST entries are
  /// dropped on read and on write. Generous for a per-customer cart.
  static const maxTombstones = 100;

  static Map<String, int> _sanitizeItems(Object? raw) {
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

  static List<String> _sanitizeRemoved(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final v in raw) {
      if (v is String && v.isNotEmpty && v.length <= 100) out.add(v);
    }
    if (out.length > maxTombstones) {
      out.removeRange(0, out.length - maxTombstones);
    }
    return out;
  }

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      Fb.carts.doc(uid);

  @override
  Future<RemoteCartSnapshot> fetch(String uid) async {
    final snap = await _doc(uid).get();
    return RemoteCartSnapshot(
      items: _sanitizeItems(snap.data()?['items']),
      removed: _sanitizeRemoved(snap.data()?['removed']),
    );
  }

  @override
  Stream<RemoteCartSnapshot> watch(String uid) {
    return _doc(uid)
        .snapshots()
        .map((doc) => RemoteCartSnapshot(
              items: _sanitizeItems(doc.data()?['items']),
              removed: _sanitizeRemoved(doc.data()?['removed']),
            ));
  }

  @override
  Future<void> push(String uid, RemoteCartSnapshot snapshot) {
    var removed = snapshot.removed;
    if (removed.length > maxTombstones) {
      removed = removed.sublist(removed.length - maxTombstones);
    }
    return _doc(uid).set({
      'items': snapshot.items,
      'removed': removed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
