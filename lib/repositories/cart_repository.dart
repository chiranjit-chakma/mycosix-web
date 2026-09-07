import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/mx_config.dart';
import '../models/cart_item.dart';
import '../models/delivery_location.dart';
import '../models/product.dart';
import 'product_repository.dart';

/// Persisted shopping cart keyed by product id, plus the saved delivery
/// location. Persists across browser refreshes via SharedPreferences.
///
/// This repository is the single authority on what can sit in a cart: it never
/// holds a line for a product that is unavailable, and it clamps every quantity
/// to the configured per-line ceiling. The UI enforces the same limits for
/// feedback; the repository enforces them for correctness.
class CartRepository {
  CartRepository(this._prefs, this._products);

  static const _cartKey = 'mx.cart.v1';
  static const _locationKey = 'mx.location.v1';

  final SharedPreferences _prefs;
  final ProductRepository _products;

  Map<String, int> _items = {};
  Map<String, Product> _catalog = {};
  DeliveryLocation? _location;

  Map<String, int> get items => Map.unmodifiable(_items);

  /// Resolved cart lines, in catalog order, skipping unknown products.
  List<CartItem> get lines {
    final result = <CartItem>[];
    _items.forEach((id, qty) {
      final product = _catalog[id];
      if (product != null) {
        result.add(CartItem(product: product, quantity: qty));
      }
    });
    return result;
  }

  int get totalQuantity => _items.values.fold(0, (a, b) => a + b);

  int get lineCount => _items.length;

  DeliveryLocation? get location => _location;

  bool get isEmpty => _items.isEmpty;

  /// Most copies of [product] one order may carry: 0 when unavailable,
  /// otherwise stock limited by the configured ceiling.
  int maxFor(Product product) {
    if (!product.inStock) return 0;
    return min(product.stock, MxConfig.maxUnitsPerProduct);
  }

  /// [maxFor] by product id (0 when the product is unknown or unavailable).
  int capForId(String productId) {
    final product = _catalog[productId];
    if (product == null) return 0;
    return maxFor(product);
  }

  int _cap(Product product) => maxFor(product);

  /// Loads catalog + persisted cart/location. Call once at startup.
  Future<void> load() async {
    final all = await _products.fetchAll();
    _catalog = {for (final p in all) p.id: p};

    final cartRaw = _prefs.getString(_cartKey);
    if (cartRaw != null) {
      try {
        final list = jsonDecode(cartRaw) as List<dynamic>;
        final next = <String, int>{};
        for (final entry in list) {
          final id = entry['productId'] as String;
          final qty = entry['quantity'] as int;
          if (id.isEmpty || qty <= 0) continue;
          // Sanitise anything a past session may have left behind: unknown or
          // unavailable products are dropped, quantities are re-clamped.
          final product = _catalog[id];
          if (product == null || !product.inStock) continue;
          next[id] = min(qty, _cap(product));
        }
        _items = next;
      } catch (_) {
        _items = {};
      }
    }

    final locRaw = _prefs.getString(_locationKey);
    if (locRaw != null) {
      try {
        _location = DeliveryLocation.fromJson(
          jsonDecode(locRaw) as Map<String, Object?>,
        );
      } catch (_) {
        _location = null;
      }
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _cartKey,
      jsonEncode(
        _items.entries
            .map((e) => {'productId': e.key, 'quantity': e.value})
            .toList(),
      ),
    );
  }

  Future<void> add(String productId, int quantity) async {
    final product = _catalog[productId];
    // Never add an unknown or unavailable product — the UI also hides the
    // button, but the repository must not be talked into it either.
    if (product == null || !product.inStock || quantity <= 0) return;
    final current = _items[productId] ?? 0;
    _items[productId] = min(current + quantity, _cap(product));
    await _persist();
  }

  Future<void> setQuantity(String productId, int quantity) async {
    final product = _catalog[productId];
    if (quantity <= 0 || product == null || !product.inStock) {
      _items.remove(productId);
    } else {
      _items[productId] = min(quantity, _cap(product));
    }
    await _persist();
  }

  Future<void> remove(String productId) async {
    _items.remove(productId);
    await _persist();
  }

  Future<void> clear() async {
    _items = {};
    await _persist();
  }

  Future<void> saveLocation(DeliveryLocation location) async {
    _location = location;
    await _prefs.setString(_locationKey, jsonEncode(location.toJson()));
  }

  Future<void> clearLocation() async {
    _location = null;
    await _prefs.remove(_locationKey);
  }

  /// Replaces the whole cart from an outside source (the account cart mirror).
  /// Not a customer action: every line is re-validated against the live
  /// catalogue exactly like a persisted cart restore — unknown or unavailable
  /// products are dropped, quantities re-clamped.
  Future<void> replaceAll(Map<String, int> items) async {
    final next = <String, int>{};
    items.forEach((id, qty) {
      final cap = capForId(id);
      if (cap <= 0 || qty < 1) return;
      next[id] = min(qty, cap);
    });
    _items = next;
    await _persist();
  }

  /// Merges the account cart into the local (guest) cart: quantities are
  /// summed per product and re-clamped to what the live catalogue allows, so a
  /// stale account cart can never push an unavailable product or an
  /// over-stock quantity back into this device. Returns the merged map.
  Future<Map<String, int>> mergeRemote(Map<String, int> remote) async {
    final merged = mergeCartQuantities(_items, remote, capForId);
    _items = merged;
    await _persist();
    return merged;
  }
}

/// Sums two cart item maps per product, clamped to [capFor] (0 = drop the
/// product entirely: unknown, unavailable, or out of stock). Pure, so the
/// guest→login merge can be unit-tested without prefs or Firebase.
Map<String, int> mergeCartQuantities(
  Map<String, int> guest,
  Map<String, int> account,
  int Function(String productId) capFor,
) {
  final merged = <String, int>{};
  for (final entry in guest.entries) {
    final cap = capFor(entry.key);
    if (cap <= 0 || entry.value < 1) continue;
    merged[entry.key] = min(entry.value, cap);
  }
  for (final entry in account.entries) {
    if (entry.value < 1) continue;
    final cap = capFor(entry.key);
    if (cap <= 0) continue;
    final current = merged[entry.key];
    merged[entry.key] = min((current ?? 0) + entry.value, cap);
  }
  return merged;
}
