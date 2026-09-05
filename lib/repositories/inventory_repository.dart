import '../models/product.dart';

/// Live inventory / stock levels.
///
/// Interface only — today it reads stock off the catalog. A future Firebase
/// InventoryRepository will sync real-time availability.
abstract class InventoryRepository {
  Future<int> stockFor(String productId);
  Future<bool> reserve(String productId, int quantity);
}

class LocalInventoryRepository implements InventoryRepository {
  final List<Product> catalog;

  LocalInventoryRepository({required this.catalog});

  @override
  Future<int> stockFor(String productId) async {
    for (final p in catalog) {
      if (p.id == productId) return p.stock;
    }
    return 0;
  }

  @override
  Future<bool> reserve(String productId, int quantity) async => true;
}
