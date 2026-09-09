import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/site_settings.dart';
import '../repositories/cart_repository.dart';
import '../services/delivery_pricing.dart';
import 'location_controller.dart';
import 'site_config_controller.dart';

/// Application state for the shopping cart.
class CartController extends ChangeNotifier {
  /// The delivery fee this cart quotes, taken from the runtime site config
  /// (the `siteConfig/public` document the trusted backend also reads when it
  /// prices a real order). 0 means free delivery. The app shell supplies it so
  /// the fee a customer sees can never drift from the fee the backend will
  /// actually charge for the order.
  ///
  /// [siteConfig] and [location] are optional live sources: when both are
  /// provided and the site has switched on distance-based delivery (a shop
  /// point + tiers), the quoted fee is computed from the customer's pin
  /// distance to the shop instead of this flat fee. The controller listens to
  /// both, so the quote updates live as the customer drags the pin or an
  /// admin edits the tiers.
  CartController(
    this._repo, {
    required this.siteDeliveryFee,
    this._siteConfig,
    this._location,
  }) {
    _siteConfig?.addListener(_externalChanged);
    _location?.addListener(_externalChanged);
  }

  final CartRepository _repo;
  final SiteConfigController? _siteConfig;
  final LocationController? _location;

  void _externalChanged() => notifyListeners();

  /// The business delivery fee for the current site configuration.
  final double siteDeliveryFee;

  List<CartItem> get lines => _repo.lines;

  int get totalQuantity => _repo.totalQuantity;

  int get lineCount => _repo.lineCount;

  double get subtotal => lines.fold(0, (a, l) => a + l.lineTotal);

  /// The live delivery quote for this cart: distance-based when the site has
  /// switched it on and a pin exists, the flat fallback otherwise. `known`
  /// distinguishes a real distance quote from the flat estimate.
  DeliveryQuote get deliveryQuote => computeDeliveryQuote(
    settings: _siteConfig?.settings ?? const SiteSettings(),
    customer: _location?.location,
    fallbackFee: siteDeliveryFee,
  );

  /// The straight-line distance (km) the quote was based on, when any.
  double? get deliveryDistanceKm => deliveryQuote.distanceKm;

  /// True when the current pin is outside every delivery tier: the order
  /// cannot be placed to this spot.
  bool get deliveryUnavailable => deliveryQuote.unavailable;

  /// Whether the quoted fee is genuinely distance-based (vs the flat
  /// estimate shown before a pin or tiers exist).
  bool get deliveryPricedByDistance => deliveryQuote.known;

  /// Charged only on a non-empty cart; an empty cart is never charged.
  double get deliveryFee => subtotal > 0 ? (deliveryQuote.unavailable ? 0 : deliveryQuote.fee) : 0;

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

  /// Merges the account cart into the local cart on the customer's explicit
  /// request (the cart page's load button). Every product is topped up to the
  /// HIGHER of its two quantities - never summed - so loading the same saved
  /// cart twice (or again after a re-login) can never double a line; the
  /// repository re-clamps everything against the live catalogue. Returns the
  /// merged item map so the caller can mirror it back to the account.
  Future<Map<String, int>> mergeRemoteCart(Map<String, int> remote) async {
    final merged = await _repo.mergeRemote(remote);
    notifyListeners();
    return merged;
  }

  /// Applies the account's REMOVAL TOMBSTONES to the local cart (live sync):
  /// drops local lines the account removed, unless this device explicitly
  /// re-added them. Not a customer action - the dropped lines are not
  /// recorded as pending removals, because the account already knows.
  Future<void> applyRemoteRemovals(Set<String> tombstoned) async {
    final dropped = await _repo.applyRemoteRemovals(tombstoned);
    if (dropped.isNotEmpty) notifyListeners();
  }

  @override
  void dispose() {
    _siteConfig?.removeListener(_externalChanged);
    _location?.removeListener(_externalChanged);
    super.dispose();
  }
}
