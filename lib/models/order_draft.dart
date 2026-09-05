/// One product + quantity the customer wants to order.
///
/// Deliberately carries NO price: prices are never trusted from the browser.
/// The backend resolves every line against the real product catalogue.
class OrderDraftLine {
  const OrderDraftLine({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  Map<String, Object?> toCallableData() => {
        'productId': productId,
        'quantity': quantity,
      };
}

/// What the customer submits from checkout.
///
/// Totals, product names, fees and availability are intentionally absent — the
/// trusted backend computes them from Firestore data. The client also never
/// chooses the order id or status.
class OrderDraft {
  const OrderDraft({
    required this.customerName,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.mapsUrl,
    required this.lines,
    this.email,
    this.building,
    this.apartment,
    this.landmark,
    this.instructions,
  });

  final String customerName;
  final String phone;
  final String? email;

  final double latitude;
  final double longitude;
  final String mapsUrl;

  final String? building;
  final String? apartment;
  final String? landmark;
  final String? instructions;

  final List<OrderDraftLine> lines;

  int get totalQuantity => lines.fold(0, (sum, l) => sum + l.quantity);

  Map<String, Object?> toCallableData() => {
        'customerName': customerName,
        'phone': phone,
        if (email != null && email!.trim().isNotEmpty) 'email': email!.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'mapsUrl': mapsUrl,
        if (building != null && building!.trim().isNotEmpty)
          'building': building!.trim(),
        if (apartment != null && apartment!.trim().isNotEmpty)
          'apartment': apartment!.trim(),
        if (landmark != null && landmark!.trim().isNotEmpty)
          'landmark': landmark!.trim(),
        if (instructions != null && instructions!.trim().isNotEmpty)
          'instructions': instructions!.trim(),
        'items': lines.map((l) => l.toCallableData()).toList(),
      };
}
