/// A product sold by MYCOSIX.
///
/// Pure data model — no Flutter/Firebase imports. Matches the shape a
/// Firebase-backed ProductRepository returns from the `products` collection.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.image,
    this.gallery = const [],
    required this.variant,
    required this.weight,
    required this.price,
    required this.stock,
    this.available = true,
    this.sortKey = 0,
    this.videoUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String category;
  final String image;

  /// Additional images for the product gallery. Falls back to [image].
  final List<String> gallery;

  /// Optional web (https) video link (e.g. a cooking or grow-room clip).
  /// Null/blank means the product has no video and the UI hides the
  /// "Watch product video" control entirely.
  final String? videoUrl;

  /// e.g. "Fresh Oyster Mushroom" or "Dried Slices".
  final String variant;

  /// e.g. "250 g".
  final String weight;

  /// Price in rupees (whole units). Prices recorded on orders come from the
  /// trusted backend, never from a browser.
  final double price;

  final int stock;
  final bool available;

  /// Display order in the shop. Firestore orders by this key, so admins can
  /// control catalogue ordering without code changes.
  final int sortKey;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get inStock => available && stock > 0;

  Product copyWith({
    String? name,
    String? description,
    String? category,
    String? image,
    List<String>? gallery,
    String? variant,
    String? weight,
    double? price,
    int? stock,
    bool? available,
    int? sortKey,
    String? videoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      image: image ?? this.image,
      gallery: gallery ?? this.gallery,
      variant: variant ?? this.variant,
      weight: weight ?? this.weight,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      available: available ?? this.available,
      sortKey: sortKey ?? this.sortKey,
      videoUrl: videoUrl ?? this.videoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'image': image,
        'gallery': gallery,
        'variant': variant,
        'weight': weight,
        'price': price,
        'stock': stock,
        'available': available,
        'sortKey': sortKey,
        if (videoUrl != null && videoUrl!.trim().isNotEmpty)
          'videoUrl': videoUrl!.trim(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory Product.fromJson(Map<String, Object?> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      description: (json['description'] ?? '') as String,
      category: (json['category'] ?? 'Mushrooms') as String,
      image: json['image'] as String,
      gallery: ((json['gallery'] ?? const []) as List).cast<String>(),
      variant: (json['variant'] ?? 'Fresh') as String,
      weight: (json['weight'] ?? '') as String,
      price: (json['price'] as num).toDouble(),
      stock: (json['stock'] ?? 0) as int,
      available: json['available'] as bool? ?? true,
      sortKey: ((json['sortKey'] ?? 0) as num).toInt(),
      videoUrl: (json['videoUrl'] as String?)?.trim(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  /// Firestore document map. Timestamps are written by the repository layer as
  /// server timestamps; [createdAt]/[updatedAt] are read back and merged in by
  /// the repository, so they are not part of this map.
  Map<String, Object?> toFirestoreMap() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'image': image,
        'gallery': gallery,
        'variant': variant,
        'weight': weight,
        'price': price,
        'stock': stock,
        'available': available,
        'sortKey': sortKey,
        if (videoUrl != null && videoUrl!.trim().isNotEmpty)
          'videoUrl': videoUrl!.trim(),
      };

  /// Reads a product document. Timestamp fields are converted by the caller
  /// (see the Firestore repository), because a stored Firestore timestamp is
  /// not a plain [DateTime].
  factory Product.fromFirestoreMap(Map<String, dynamic> map) {
    return Product(
      id: (map['id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      description: (map['description'] ?? '') as String,
      category: (map['category'] ?? 'Mushrooms') as String,
      image: (map['image'] ?? '') as String,
      gallery: (map['gallery'] as List<dynamic>? ?? const []).cast<String>(),
      variant: (map['variant'] ?? 'Fresh') as String,
      weight: (map['weight'] ?? '') as String,
      price: ((map['price'] ?? 0) as num).toDouble(),
      stock: ((map['stock'] ?? 0) as num).toInt(),
      available: map['available'] as bool? ?? true,
      sortKey: ((map['sortKey'] ?? 0) as num).toInt(),
      videoUrl: (map['videoUrl'] as String?)?.trim(),
    );
  }

  @override
  bool operator ==(Object other) => other is Product && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
