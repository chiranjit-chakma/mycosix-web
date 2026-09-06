import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../repositories/product_repository.dart';

/// Loads and exposes the product catalog.
///
/// When the backing repository supports live updates ([ProductStreamSource]),
/// the controller keeps a subscription open after the first load, so an admin's
/// Firestore edits reach every open customer page without a refresh. Repos
/// without a live source behave exactly as before: load once, serve the cache.
class ProductsController extends ChangeNotifier {
  ProductsController(this._repo);

  final ProductRepository _repo;

  List<Product> _products = const [];
  bool _loaded = false;
  Object? _error;
  Future<List<Product>>? _pending;
  StreamSubscription<List<Product>>? _watch;

  List<Product> get products => _products;
  bool get loaded => _loaded;
  Object? get error => _error;

  /// Loads the catalog once; subsequent calls return the cached result.
  ///
  /// Concurrent first calls share a single in-flight request.
  Future<List<Product>> fetchAll() {
    if (_loaded) return Future.value(_products);
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<List<Product>> _load() async {
    try {
      _products = await _repo.fetchAll();
      _loaded = true;
      _error = null;
      notifyListeners();
      _startLiveWatch();
    } catch (e) {
      _error = e;
      notifyListeners();
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

  /// Subscribes to repository pushes once, after the first successful load.
  void _startLiveWatch() {
    if (_watch != null) return;
    // Repos that can stream declare ProductStreamSource next to
    // ProductRepository (unrelated interfaces, so promotion needs a cast).
    if (_repo is ProductStreamSource) {
      final source = _repo as ProductStreamSource;
      _watch = source.watchAll().listen(
        (snapshot) {
          _products = List<Product>.unmodifiable(snapshot);
          _loaded = true;
          _error = null;
          notifyListeners();
        },
        onError: (Object e) {
          // Firestore's persistent listener reconnects and re-emits on its own,
          // so on a dropped snapshot we simply keep the current list.
          debugPrint('MYCOSIX: live catalogue stream unavailable — keeping the '
              'current list ($e).');
        },
      );
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }
}
