import 'product.dart';

/// A line in the shopping cart: product + quantity.
class CartItem {
  const CartItem({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  double get lineTotal => product.price * quantity;

  CartItem copyWith({Product? product, int? quantity}) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }

  Map<String, Object?> toJson() => {
        'productId': product.id,
        'quantity': quantity,
      };

  @override
  bool operator ==(Object other) => other is CartItem && other.product.id == product.id;

  @override
  int get hashCode => product.id.hashCode;
}
