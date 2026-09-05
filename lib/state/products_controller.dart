import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../repositories/product_repository.dart';

/// Loads and exposes the product catalog.
class ProductsController extends ChangeNotifier {
  ProductsController(this._repo);

  final ProductRepository _repo;

  List<Product> _products = const [];
  bool _loaded = false;
  Object? _error;

  List<Product> get products => _products;
  bool get loaded => _loaded;
  Object? get error => _error;

  /// Loads once; subsequent calls return the cached result.
  Future<List<Product>> fetchAll() async {
    if (_loaded) return _products;
    try {
      _products = await _repo.fetchAll();
      _loaded = true;
      notifyListeners();
    } catch (e) {
      _error = e;
      rethrow;
    }
    return _products;
  }

  Future<Product?> byId(String id) async {
    if (!_loaded) await fetchAll();
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }
}
