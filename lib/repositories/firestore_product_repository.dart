import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/fb.dart';
import '../models/product.dart';
import 'product_repository.dart';

/// Reads the product catalogue from the Firestore `products` collection.
///
/// Product documents are ordered by `sortKey`. `stock`, `available`, prices
/// and descriptions all come from here, so admin edits reach the shop without
/// any source-code change.
class FirestoreProductRepository
    implements ProductRepository, ProductStreamSource {
  @override
  Future<List<Product>> fetchAll() async {
    final snap = await Fb.products.orderBy('sortKey').get();
    return _docsToProducts(snap.docs);
  }

  @override
  Future<Product?> fetchById(String id) async {
    final d = await Fb.products.doc(id).get();
    if (!d.exists) return null;
    final m = d.data() ?? const <String, dynamic>{};
    return Product.fromFirestoreMap(m).copyWith(
      createdAt: _date(m['createdAt']),
      updatedAt: _date(m['updatedAt']),
    );
  }

  @override
  Future<List<Product>> fetchByCategory(String category) async {
    final snap = await Fb.products
        .where('category', isEqualTo: category)
        .orderBy('sortKey')
        .get();
    return _docsToProducts(snap.docs);
  }

  @override
  Stream<List<Product>> watchAll() {
    // Live mirror of the catalogue. The admin section writes to this same
    // collection, so an add / edit / delete is pushed to every open customer
    // page the moment it lands in Firestore — no refresh required.
    return Fb.products.orderBy('sortKey').snapshots().map((snap) {
      return _docsToProducts(snap.docs);
    });
  }

  static List<Product> _docsToProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final list = <Product>[];
    for (final d in docs) {
      final m = d.data();
      list.add(
        Product.fromFirestoreMap(m).copyWith(
          createdAt: _date(m['createdAt']),
          updatedAt: _date(m['updatedAt']),
        ),
      );
    }
    return list;
  }

  static DateTime? _date(Object? v) =>
      v is Timestamp ? v.toDate() : v is DateTime ? v : null;
}

/// Where the catalogue currently comes from.
enum CatalogSource { firestore, localFallback }

/// Product repository that prefers Firestore but never takes the site down
/// when Firebase is unreachable or not yet configured.
///
/// On a genuine failure (offline, rules not deployed yet, timeout) it logs the
/// real cause to the console and serves the bundled catalogue instead, so the
/// Part 1 experience stays intact while the backend is being connected. An
/// EMPTY Firestore result is treated as truth (not a failure), so an
/// unseeded-but-reachable catalogue shows its proper empty state rather than
/// silently substituting local data.
class ResilientProductRepository
    implements ProductRepository, ProductStreamSource {
  ResilientProductRepository(
    this._primary, {
    LocalProductRepository? fallback,
  }) : _fallback = fallback ?? LocalProductRepository();

  final FirestoreProductRepository _primary;
  final LocalProductRepository _fallback;

  CatalogSource _last = CatalogSource.localFallback;

  /// Source used for the most recent successful read.
  CatalogSource get lastSource => _last;

  bool get usingFallback => _last == CatalogSource.localFallback;

  @override
  Future<List<Product>> fetchAll() async {
    try {
      final all = await _primary.fetchAll().timeout(_timeout);
      _last = CatalogSource.firestore;
      return all;
    } catch (e) {
      _logFallback(e);
      return _fallback.fetchAll();
    }
  }

  @override
  Future<Product?> fetchById(String id) async {
    try {
      final p = await _primary.fetchById(id).timeout(_timeout);
      _last = CatalogSource.firestore;
      if (p != null) return p;
      // Not in the database yet (pre-seed) — fall back so deep links to the
      // bundled catalogue still open while the backend is coming up.
      return await _fallback.fetchById(id);
    } catch (e) {
      _logFallback(e);
      return await _fallback.fetchById(id);
    }
  }

  @override
  Future<List<Product>> fetchByCategory(String category) async {
    try {
      final list = await _primary.fetchByCategory(category).timeout(_timeout);
      _last = CatalogSource.firestore;
      return list;
    } catch (e) {
      _logFallback(e);
      return _fallback.fetchByCategory(category);
    }
  }

  @override
  Stream<List<Product>> watchAll() {
    // Delegate to the Firestore listener. Firestore's persistent listeners
    // reconnect on their own when the network returns, so this stays live even
    // if the initial one-shot read fell back to the bundled catalogue.
    return _primary.watchAll();
  }

  static const _timeout = Duration(seconds: 10);

  void _logFallback(Object e) {
    _last = CatalogSource.localFallback;
    debugPrint(
      'MYCOSIX: Firestore products unavailable ($e) — serving the bundled '
      'catalogue as a fallback. This is expected until Firestore rules are '
      'deployed and the catalogue is seeded.',
    );
  }
}
