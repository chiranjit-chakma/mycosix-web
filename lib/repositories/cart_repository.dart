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

  /// This device's cart actions since the last acknowledged write-through to
  /// the account: products ADDED/raised (added) and products REMOVED/lowered
  /// to zero (removed). They are the per-device delta removal propagation
  /// needs - a removal on one device tombstones the product account-wide,
  /// while an explicit re-add on this device lifts the tombstone again.
  final Set<String> _addedPending = {};
  final Set<String> _removedPending = {};

  Map<String, int> get items => Map.unmodifiable(_items);

  /// The unresolved cart actions this device is still owed by the account.
  PendingActions get pendingActions => PendingActions(
        added: Set.unmodifiable(_addedPending),
        removed: Set.unmodifiable(_removedPending),
      );

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
  ///
  /// This is [restoreFromDevice] followed by [refreshCatalog], which is what
  /// every caller wants; the two are separate only so the app can get the
  /// saved cart back WITHOUT waiting for the catalog, which is a network read.
  Future<void> load() async {
    restoreFromDevice();
    await refreshCatalog();
  }

  /// Brings back the cart and the delivery point this device saved, reading
  /// only this device. Nothing here touches the network, so it finishes in the
  /// same breath as the first frame - which is the whole reason it is split
  /// out of [load].
  ///
  /// The lines are restored as they were last saved rather than re-checked
  /// against the catalog: the catalog is not in hand yet, and checking against
  /// an empty one would throw the customer's cart away. Everything stored was
  /// already put through that check when it was written, so the only thing
  /// that can be stale is a product that has since been deleted or sold out -
  /// and [refreshCatalog] drops those a moment later, which is why `lines`
  /// skips a product it cannot resolve.
  void restoreFromDevice() {
    final cartRaw = _prefs.getString(_cartKey);
    if (cartRaw != null) {
      try {
        final list = jsonDecode(cartRaw) as List<dynamic>;
        final next = <String, int>{};
        for (final entry in list) {
          final id = entry['productId'] as String;
          final qty = entry['quantity'] as int;
          if (id.isEmpty || qty <= 0) continue;
          next[id] = qty;
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

  /// Fetches the live catalog and re-checks the cart against it: unknown or
  /// unavailable products are dropped and every quantity is clamped to what
  /// may actually be bought. Safe to call again at any time.
  Future<void> refreshCatalog() async {
    final all = await _products.fetchAll();
    _catalog = {for (final p in all) p.id: p};

    final next = <String, int>{};
    _items.forEach((id, qty) {
      final product = _catalog[id];
      if (product == null || !product.inStock) return;
      next[id] = min(qty, _cap(product));
    });
    _items = next;
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

  void _noteAdded(String productId) {
    _addedPending.add(productId);
    _removedPending.remove(productId);
  }

  void _noteRemoved(String productId) {
    _removedPending.add(productId);
    _addedPending.remove(productId);
  }

  Future<void> add(String productId, int quantity) async {
    final product = _catalog[productId];
    // Never add an unknown or unavailable product — the UI also hides the
    // button, but the repository must not be talked into it either.
    if (product == null || !product.inStock || quantity <= 0) return;
    final current = _items[productId] ?? 0;
    _items[productId] = min(current + quantity, _cap(product));
    _noteAdded(productId);
    await _persist();
  }

  Future<void> setQuantity(String productId, int quantity) async {
    final product = _catalog[productId];
    if (quantity <= 0 || product == null || !product.inStock) {
      _items.remove(productId);
      _noteRemoved(productId);
    } else {
      _items[productId] = min(quantity, _cap(product));
      _noteAdded(productId);
    }
    await _persist();
  }

  Future<void> remove(String productId) async {
    _items.remove(productId);
    _noteRemoved(productId);
    await _persist();
  }

  Future<void> clear() async {
    _removedPending.addAll(_items.keys);
    _addedPending.clear();
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

  /// Merges the account cart into the local (guest) cart: every product
  /// ends at the HIGHER of its two quantities - never at their sum. The
  /// account cart is a write-through MIRROR of this cart, so summing it in
  /// would count the customer's own items twice (the same saved cart can be
  /// offered again after a re-login, or reloaded after a failed write);
  /// topping up is the deterministic combine that can never double a line.
  /// Everything is re-clamped to what the live catalogue allows, so a stale
  /// account cart can never push an unavailable product or an over-stock
  /// quantity back into this device. Returns the merged map.
  Future<Map<String, int>> mergeRemote(Map<String, int> remote) async {
    final merged = mergeCartQuantities(_items, remote, capForId);
    _items = merged;
    await _persist();
    return merged;
  }

  /// Applies the account's REMOVAL TOMBSTONES to this cart (live sync). Not
  /// a customer action: a dropped line is never recorded as a pending removal
  /// (the account already knows), and a product this device explicitly
  /// re-added is kept. Returns the ids dropped.
  Future<Set<String>> applyRemoteRemovals(Set<String> tombstoned) async {
    if (tombstoned.isEmpty) return const {};
    final dropped = <String>{};
    _items.removeWhere((id, qty) {
      if (tombstoned.contains(id) && !_addedPending.contains(id)) {
        dropped.add(id);
        _removedPending.remove(id); // the tombstone is already account-wide
        return true;
      }
      return false;
    });
    if (dropped.isNotEmpty) await _persist();
    return dropped;
  }

  /// Clears the pending actions a successful write-through carried to the
  /// account. Each id is cleared only if it is still pending in that
  /// direction, so a change made AFTER the write was built survives and is
  /// retried on the next push.
  void ackPush({required Set<String> added, required List<String> removed}) {
    _removedPending.removeAll(removed);
    _addedPending.removeAll(added);
  }
}

/// Cart actions this device has taken since the account last acknowledged
/// them. `added` and `removed` are disjoint.
class PendingActions {
  const PendingActions({required this.added, required this.removed});

  final Set<String> added;
  final Set<String> removed;
}

/// The account cart a device should write, as computed by
/// [reconcileAccountCart].
class ReconcileResult {
  const ReconcileResult({required this.items, required this.removed});

  final Map<String, int> items;

  /// Tombstone list, account's existing order preserved and new ones appended
  /// newest-last, so the bounded write keeps the most recent.
  final List<String> removed;
}

/// Tops two cart item maps up to the higher quantity per product, clamped to
/// [capFor] (0 = drop the product entirely: unknown, unavailable, or out of
/// stock). Products present in the account at a HIGHER quantity are raised to
/// it; products already carried at the same or a higher quantity are left
/// alone - quantities are never summed, so re-loading the same saved cart can
/// never double a line. Pure, so the guest→login merge can be unit-tested
/// without prefs or Firebase.
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
    final current = merged[entry.key] ?? 0;
    if (entry.value > current) {
      merged[entry.key] = min(entry.value, cap);
    }
  }
  return merged;
}

/// Computes the account cart this device should write, given the account's
/// current snapshot and this device's local cart + pending actions. Pure and
/// unit-testable.
///
/// The rule is last-action-wins with tombstones:
///  * A local line the account has TOMBSTONED, and this device has not
///    explicitly re-added, is NOT pushed (a stale device can never resurrect
///    an item the account removed).
///  * Every local removal this device has not yet had acknowledged becomes a
///    NEW tombstone (removal propagates), unless this device re-added the
///    product (an explicit re-add lifts the tombstone again).
///  * Items are the top-up union of the account and this device's push, with
///    every tombstoned line removed - so quantities only ever grow towards
///    the union, never shrink, and nothing removed is ever resurrected.
ReconcileResult reconcileAccountCart({
  required Map<String, int> accountItems,
  required List<String> accountRemoved,
  required Map<String, int> localItems,
  required Set<String> addedPending,
  required Set<String> removedPending,
  required int Function(String productId) capFor,
}) {
  final accountRemovedSet = accountRemoved.toSet();

  // This device's push: every local line EXCEPT ones the account has
  // tombstoned and this device has not explicitly re-added.
  final allowedPush = <String, int>{};
  localItems.forEach((id, qty) {
    if (accountRemovedSet.contains(id) && !addedPending.contains(id)) return;
    final cap = capFor(id);
    if (cap <= 0 || qty < 1) return;
    allowedPush[id] = min(qty, cap);
  });

  // Tombstones: what the account already marks, plus this device's removals,
  // minus anything this device explicitly re-added.
  final newRemovedSet = {...accountRemovedSet, ...removedPending}
    ..removeAll(addedPending);

  // Items: the top-up union of the account and this device's push, with every
  // tombstoned line removed (never resurrected unless re-added above).
  final items = <String, int>{};
  void applyLine(String id, int qty) {
    if (newRemovedSet.contains(id)) return;
    final cap = capFor(id);
    if (cap <= 0 || qty < 1) return;
    final current = items[id] ?? 0;
    if (qty > current) items[id] = min(qty, cap);
  }

  accountItems.forEach(applyLine);
  allowedPush.forEach(applyLine);

  // Tombstone list, account order first and new ones appended newest-last.
  final removed = <String>[];
  final seen = <String>{};
  for (final id in accountRemoved) {
    if (newRemovedSet.contains(id) && seen.add(id)) removed.add(id);
  }
  for (final id in newRemovedSet) {
    if (seen.add(id)) removed.add(id);
  }

  return ReconcileResult(items: items, removed: removed);
}
