import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../repositories/cart_repository.dart';

/// Application state for the shopping cart.
class CartController extends ChangeNotifier {
  /// The delivery fee this cart quotes, taken from the runtime site config
  /// (the `siteConfig/public` document the trusted backend also reads when it
  /// prices a real order). 0 means free delivery. The app shell supplies it so
  /// the fee a customer sees can never drift from the fee the backend will
  /// actually charge for the order.
  CartController(this._repo, {required this.siteDeliveryFee});

  final CartRepository _repo;

  /// The business delivery fee for the current site configuration.
  final double siteDeliveryFee;

  List<CartItem> get lines => _repo.lines;

  int get totalQuantity => _repo.totalQuantity;

  int get lineCount => _repo.lineCount;

  double get subtotal => lines.fold(0, (a, l) => a + l.lineTotal);

  /// Charged only on a non-empty cart; an empty cart is never charged.
  double get deliveryFee => subtotal > 0 ? siteDeliveryFee : 0;

  double get total => subtotal + deliveryFee;

  bool get isEmpty => _repo.isEmpty;

  int quantityOf(String productId) => _repo.items[productId] ?? 0;

  /// How many copies of [product] one order may carry (0 when unavailable).
  int maxQuantityOf(Product product) => _repo.maxFor(product);

  /// Product ids removed since the last page load (for "undo" affordance).
  final Set<String> _removedRecently = {};

  Set<String> get removedRecently => Set.unmodifiable(_removedRecently);

  void markRemoved(String productId) {
    _removedRecently.add(productId);
    notifyListeners();
  }

  void add(Product product, {int quantity = 1}) {
    _repo.add(product.id, quantity);
    notifyListeners();
  }

  void setQuantity(Product product, int quantity) {
    _repo.setQuantity(product.id, quantity);
    notifyListeners();
  }

  void increment(Product product) {
    // Repository clamps regardless; guarding here keeps the + button from
    // feeling dead when the per-line ceiling or stock is already reached.
    if (quantityOf(product.id) >= maxQuantityOf(product)) return;
    _repo.setQuantity(product.id, quantityOf(product.id) + 1);
    notifyListeners();
  }

  void decrement(Product product) {
    final q = quantityOf(product.id);
    if (q > 1) {
      _repo.setQuantity(product.id, q - 1);
    } else {
      _repo.remove(product.id);
    }
    notifyListeners();
  }

  void remove(Product product) {
    _repo.remove(product.id);
    markRemoved(product.id);
    notifyListeners();
  }

  Future<void> clear() async {
    await _repo.clear();
    notifyListeners();
  }

  Future<void> hydrate() => _repo.load();
}
