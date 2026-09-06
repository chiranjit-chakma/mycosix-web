import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/cart_item.dart';
import 'package:mycosix/models/customer_order.dart';
import 'package:mycosix/models/delivery_location.dart';
import 'package:mycosix/models/product.dart';
import 'package:mycosix/services/order_receipt_pdf.dart';

/// Builds the receipt fonts + logo straight from the repo assets, the same way
/// the running app does via [ReceiptAssets.fromAssets] (rootBundle is not
/// populated in a plain `flutter test`).
Future<ReceiptAssets> _assetsFromDisk() async {
  Future<ByteData> font(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  return ReceiptAssets(
    manrope: await font('assets/fonts/Manrope-Variable.ttf'),
    fraunces: await font('assets/fonts/Fraunces-Variable.ttf'),
    logoPng: await File('assets/brand/mycosix-logo.png').readAsBytes(),
  );
}

Product _product(String id, String name, String variant, String weight,
    double price) {
  return Product(
    id: id,
    name: name,
    description: 'Fresh by MYCOSIX',
    category: 'Mushrooms',
    image: 'assets/images/$id.png',
    variant: variant,
    weight: weight,
    price: price,
    stock: 10,
  );
}

CustomerOrder _order({
  String orderId = 'MYC-TEST0001',
  String? email,
  String? building,
  String? apartment,
  String? landmark,
  String? instructions,
}) {
  final pink = _product('pink', 'Pink Oyster Mushroom', 'Fresh', '250 g', 149);
  final dried =
      _product('dried', 'Dried Oyster Mushroom Slices', 'Dried Slices', '100 g', 249);
  final items = [CartItem(product: pink, quantity: 2), CartItem(product: dried, quantity: 1)];
  final subtotal = items.fold<double>(0, (s, i) => s + i.lineTotal);
  return CustomerOrder(
    orderId: orderId,
    customerName: 'Ananya Rao',
    phone: '+91 98765 43210',
    email: email,
    location: const DeliveryLocation(
      latitude: 17.3850,
      longitude: 78.4867,
      mapsUrl: 'https://www.google.com/maps?q=17.3850,78.4867&z=16',
      confirmed: true,
    ),
    items: items,
    subtotal: subtotal,
    deliveryFee: 39,
    total: subtotal + 39,
    building: building,
    apartment: apartment,
    landmark: landmark,
    instructions: instructions,
    createdAt: DateTime(2026, 9, 6, 9, 14),
  );
}

void main() {
  test('full receipt order renders a real, non-trivial PDF', () async {
    final assets = await _assetsFromDisk();
    final order = _order(
      email: 'ananya@example.com',
      building: '12-3-456, Green Valley Apartments',
      apartment: 'Flat 3B',
      landmark: 'Opposite City Park',
      instructions: 'Call on arrival',
    );

    final bytes = await buildOrderReceiptPdf(order, assets: assets);

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // Fonts + logo are embedded, so the file is substantial.
    expect(bytes.length, greaterThan(3000));
  });

  test('minimal order with blank optional fields still renders', () async {
    final assets = await _assetsFromDisk();
    final bytes = await buildOrderReceiptPdf(_order(), assets: assets);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(3000));
  });

  test('a product with no weight or variant still renders a line', () async {
    final assets = await _assetsFromDisk();
    final plain =
        _product('plain', 'Plain Oyster Mushroom', 'Fresh', '', 99);
    final order = CustomerOrder(
      orderId: 'MYC-PLAIN01',
      customerName: 'Kiran',
      phone: '+91 90000 00001',
      location: const DeliveryLocation(
        latitude: 17.0,
        longitude: 78.0,
        mapsUrl: 'https://maps.google.com/?q=17,78',
        confirmed: true,
      ),
      items: [CartItem(product: plain, quantity: 1)],
      subtotal: 99,
      deliveryFee: 39,
      total: 138,
      createdAt: DateTime(2026, 9, 5, 18, 0),
    );
    final bytes = await buildOrderReceiptPdf(order, assets: assets);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
