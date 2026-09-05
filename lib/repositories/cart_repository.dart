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
}
