import 'order_status.dart';

/// A line recorded on a stored order.
///
/// This is an immutable snapshot of what was agreed at order time. The unit
/// price, line total and product name come from the trusted backend (the Cloud
/// Function that created the order), never from the browser.
class StoreOrderLine {
  const StoreOrderLine({
    required this.productId,
    required this.productName,
    this.variant,
    this.weight,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productId;
  final String productName;
  final String? variant;
  final String? weight;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  Map<String, Object?> toMap() => {
        'productId': productId,
        'productName': productName,
        if (variant != null && variant!.isNotEmpty) 'variant': variant,
        if (weight != null && weight!.isNotEmpty) 'weight': weight,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
      };

  factory StoreOrderLine.fromMap(Map<String, dynamic> map) {
    return StoreOrderLine(
      productId: (map['productId'] ?? '') as String,
      productName: (map['productName'] ?? '') as String,
      variant: map['variant'] as String?,
      weight: map['weight'] as String?,
      quantity: ((map['quantity'] ?? 0) as num).toInt(),
      unitPrice: ((map['unitPrice'] ?? 0) as num).toDouble(),
      lineTotal: ((map['lineTotal'] ?? 0) as num).toDouble(),
    );
  }
}

/// A stored order, as written by the trusted backend and read by admins.
class StoreOrder {
  const StoreOrder({
    required this.orderId,
    required this.customerName,
    required this.phone,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.currency,
    required this.latitude,
    required this.longitude,
    required this.mapsUrl,
    required this.status,
    this.id,
    this.email,
    this.building,
    this.apartment,
    this.landmark,
    this.instructions,
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore document id (stable, set by the backend). Null before the
  /// order is persisted.
  final String? id;

  /// Customer-facing id, format `MYC-XXXXXXXX`.
  final String orderId;

  final String customerName;
  final String phone;
  final String? email;
  final List<StoreOrderLine> items;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String currency;

  final double latitude;
  final double longitude;
  final String mapsUrl;

  final String? building;
  final String? apartment;
  final String? landmark;
  final String? instructions;

  final OrderStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get totalQuantity => items.fold(0, (sum, l) => sum + l.quantity);

  StoreOrder copyWith({OrderStatus? status, DateTime? updatedAt}) {
    return StoreOrder(
      id: id,
      orderId: orderId,
      customerName: customerName,
      phone: phone,
      email: email,
      items: items,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      total: total,
      currency: currency,
      latitude: latitude,
      longitude: longitude,
      mapsUrl: mapsUrl,
      building: building,
      apartment: apartment,
      landmark: landmark,
      instructions: instructions,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'orderId': orderId,
        'customerName': customerName,
        'phone': phone,
        if (email != null) 'email': email,
        'items': items.map((l) => l.toMap()).toList(),
        'subtotal': subtotal,
        'deliveryFee': deliveryFee,
        'total': total,
        'currency': currency,
        'latitude': latitude,
        'longitude': longitude,
        'mapsUrl': mapsUrl,
        if (building != null && building!.isNotEmpty) 'building': building,
        if (apartment != null && apartment!.isNotEmpty) 'apartment': apartment,
        if (landmark != null && landmark!.isNotEmpty) 'landmark': landmark,
        if (instructions != null && instructions!.isNotEmpty)
          'instructions': instructions,
        'status': status.label,
      };

  factory StoreOrder.fromMap(
    Map<String, dynamic> map, {
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final items = <StoreOrderLine>[];
    for (final raw in (map['items'] as List<dynamic>? ?? const [])) {
      items.add(StoreOrderLine.fromMap((raw as Map).cast<String, dynamic>()));
    }
    return StoreOrder(
      id: id,
      orderId: (map['orderId'] ?? '') as String,
      customerName: (map['customerName'] ?? '') as String,
      phone: (map['phone'] ?? '') as String,
      email: map['email'] as String?,
      items: items,
      subtotal: ((map['subtotal'] ?? 0) as num).toDouble(),
      deliveryFee: ((map['deliveryFee'] ?? 0) as num).toDouble(),
      total: ((map['total'] ?? 0) as num).toDouble(),
      currency: (map['currency'] ?? 'INR') as String,
      latitude: ((map['latitude'] ?? 0) as num).toDouble(),
      longitude: ((map['longitude'] ?? 0) as num).toDouble(),
      mapsUrl: (map['mapsUrl'] ?? '') as String,
      building: map['building'] as String?,
      apartment: map['apartment'] as String?,
      landmark: map['landmark'] as String?,
      instructions: map['instructions'] as String?,
      status: OrderStatus.fromLabel(map['status'] as String?),
      // Timestamps are converted by the caller (Firestore returns Timestamp
      // objects, which must not be cast straight to DateTime here).
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
