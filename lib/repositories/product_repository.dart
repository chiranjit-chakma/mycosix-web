import '../models/product.dart';

/// Source of product data.
///
/// The UI depends only on this interface. Today it is backed by local
/// in-memory data ([LocalProductRepository]); a future
/// [FirebaseProductRepository] can swap in without touching any widget.
abstract class ProductRepository {
  Future<List<Product>> fetchAll();
  Future<Product?> fetchById(String id);
  Future<List<Product>> fetchByCategory(String category);
}

/// Local product data — the catalog shipped with the site.
class LocalProductRepository implements ProductRepository {
  LocalProductRepository();

  @override
  Future<List<Product>> fetchAll() async => _products;

  @override
  Future<Product?> fetchById(String id) async {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<Product>> fetchByCategory(String category) async {
    return _products.where((p) => p.category == category).toList();
  }

  static const _products = <Product>[
    Product(
      id: 'fresh-oyster-250',
      name: 'Fresh Oyster Mushrooms',
      description:
          'Plump, velvety oyster mushrooms harvested at peak freshness. Grown on '
          'pasteurised straw and sawdust in a climate-controlled room, they are '
          'clean, mild-flavoured mushrooms that cook in minutes.',
      category: 'Fresh',
      image: 'assets/brand/mushroom-1.webp',
      gallery: [
        'assets/brand/mushroom-1.webp',
        'assets/products/oyster_bouquet.jpg',
        'assets/products/oyster_fry.jpg',
      ],
      variant: 'Fresh',
      weight: '250 g',
      price: 80,
      stock: 40,
      available: true,
      createdAt: null,
      updatedAt: null,
    ),
    Product(
      id: 'fresh-oyster-500',
      name: 'Fresh Oyster Mushrooms — Family Pack',
      description:
          'A generous half-kilo of fresh oyster mushrooms for family meals. Perfect '
          'for stir-fries, curries, soups and grilled dishes across the week.',
      category: 'Fresh',
      image: 'assets/products/oyster_family.webp',
      gallery: [
        'assets/products/oyster_family.webp',
        'assets/products/oyster_cluster.jpg',
        'assets/products/oyster_bouquet.jpg',
      ],
      variant: 'Fresh',
      weight: '500 g',
      price: 150,
      stock: 30,
      available: true,
      createdAt: null,
      updatedAt: null,
    ),
    Product(
      id: 'fresh-oyster-1kg',
      name: 'Fresh Oyster Mushrooms — Party Pack',
      description:
          'A full kilogram for gatherings, restaurants and bulk cooking. Order a day '
          'ahead and we harvest to order so it reaches you at its absolute freshest.',
      category: 'Fresh',
      image: 'assets/products/oyster_party.webp',
      gallery: [
        'assets/products/oyster_party.webp',
        'assets/products/oyster_cluster.jpg',
        'assets/products/oyster_bouquet.jpg',
      ],
      variant: 'Fresh',
      weight: '1 kg',
      price: 280,
      stock: 25,
      available: true,
      createdAt: null,
      updatedAt: null,
    ),
    Product(
      id: 'oyster-slices-50',
      name: 'Dried Oyster Mushroom Slices',
      description:
          'Sun-dried oyster slices with a deep, savoury umami. Rehydrate in warm '
          'water for 15 minutes and use anywhere you would use fresh mushrooms.',
      category: 'Dried',
      image: 'assets/products/oyster_dried.webp',
      gallery: [
        'assets/products/oyster_dried.webp',
        'assets/products/oyster_bouquet.jpg',
      ],
      variant: 'Dried',
      weight: '50 g',
      price: 120,
      stock: 18,
      available: true,
      createdAt: null,
      updatedAt: null,
    ),
    Product(
      id: 'oyster-powder-100',
      name: 'Oyster Mushroom Powder',
      description:
          'Stone-ground oyster mushroom powder — a natural umami booster for soups, '
          'gravies, marinades and seasoning blends. Nothing added, nothing taken away.',
      category: 'Dried',
      image: 'assets/products/oyster_powder.webp',
      gallery: [
        'assets/products/oyster_powder.webp',
        'assets/products/oyster_dried.webp',
      ],
      variant: 'Dried',
      weight: '100 g',
      price: 180,
      stock: 12,
      available: true,
      createdAt: null,
      updatedAt: null,
    ),
    Product(
      id: 'oyster-pickle-250',
      name: 'Oyster Mushroom Pickle',
      description:
          'Tangy, spicy mushroom pickle made in small batches with cold-pressed oil '
          'and whole spices. A fiery side for rice, roti and parathas.',
      category: 'Preserved',
      image: 'assets/products/oyster_pickle.webp',
      gallery: [
        'assets/products/oyster_pickle.webp',
        'assets/products/oyster_bouquet.jpg',
      ],
      variant: 'Preserved',
      weight: '250 g',
      price: 160,
      stock: 0,
      available: false,
      createdAt: null,
      updatedAt: null,
    ),
  ];
}
