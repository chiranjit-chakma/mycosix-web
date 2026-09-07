import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/fb.dart';

/// Remote per-account wishlist storage: the `wishlists/{uid}` document.
///
/// The document is a bounded list of saved product ids plus a server
/// `updatedAt`. It is owned by exactly one customer (owner-only rules), so
/// the same wishlist is seen in the browser and in the installed app on any
/// device.
///
/// The remote list is never trusted wholesale: every entry is de-duplicated
/// and bounded on read, and each id is resolved against the live product
/// catalogue when displayed — a stale or tampered id simply never renders.
abstract class WishlistStore {
  /// The currently saved product ids, most-recently-added first.
  Future<List<String>> fetch(String uid);

  /// Live snapshots of the saved ids. Emits the sanitised, ordered list.
  Stream<List<String>> watch(String uid);

  /// Replaces the whole list for one account (last-writer-wins).
  Future<void> write(String uid, List<String> items);
}

class FirestoreWishlistStore implements WishlistStore {
  const FirestoreWishlistStore();

  /// Bounded, de-duplicated, insertion-ordered product ids. `raw` is a list
  /// (the rules allow only lists here, but nothing from the network is
  /// trusted until it passes this). Public so the sanitisation is directly
  /// testable without a live Firestore.
  static List<String> sanitize(Object? raw) {
    final out = <String>[];
    if (raw is! List) return out;
    for (final v in raw) {
      if (v is String &&
          v.isNotEmpty &&
          v.length <= 100 &&
          !out.contains(v)) {
        out.add(v);
        if (out.length >= 120) break;
      }
    }
    return out;
  }

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      Fb.wishlists.doc(uid);

  @override
  Future<List<String>> fetch(String uid) async {
    final snap = await _doc(uid).get();
    return sanitize(snap.data()?['items']);
  }

  @override
  Stream<List<String>> watch(String uid) {
    return _doc(uid)
        .snapshots()
        .map((doc) => sanitize(doc.data()?['items']));
  }

  @override
  Future<void> write(String uid, List<String> items) {
    return _doc(uid).set({
      'items': items,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
