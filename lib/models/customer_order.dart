import 'cart_item.dart';
import 'delivery_location.dart';

/// A customer order prepared for WhatsApp handoff.
class CustomerOrder {
  const CustomerOrder({
    required this.orderId,
    required this.customerName,
    required this.phone,
    required this.location,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.email,
    this.building,
    this.apartment,
    this.landmark,
    this.instructions,
    this.createdAt,
  });

  final String orderId;
  final String customerName;
  final String phone;
  final DeliveryLocation location;
  final List<CartItem> items;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String? email;
  final String? building;
  final String? apartment;
  final String? landmark;
  final String? instructions;
  final DateTime? createdAt;

  /// The order is only "valid" (sendable) when every WhatsApp requirement
  /// is satisfied: items, name, phone, a confirmed location with a maps URL.
  bool get isValid =>
      items.isNotEmpty &&
      customerName.trim().isNotEmpty &&
      phone.trim().isNotEmpty &&
      location.confirmed &&
      location.mapsUrl.trim().isNotEmpty &&
      total > 0;
}

class OrderLine {
  const OrderLine({required this.productId, required this.name, required this.quantity, required this.price});

  final String productId;
  final String name;
  final int quantity;
  final double price;

  double get lineTotal => price * quantity;
}
