import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/product.dart';

/// Locks the delivery-note contract: an optional per-product override of the
/// delivery line. Stored only when non-blank; blank/null always round-trips to
/// null so the product page falls back to the site-wide default from Settings.
Product _base({String? deliveryNote}) => Product(
      id: 'p1',
      name: 'Oyster Mushroom',
      description: 'Fresh',
      category: 'Mushrooms',
      image: '',
      variant: 'Fresh',
      weight: '250 g',
      price: 120,
      stock: 10,
      deliveryNote: deliveryNote,
    );

void main() {
  group('Product deliveryNote', () {
    test('is absent from the Firestore map when null or blank', () {
      expect(_base().toFirestoreMap().containsKey('deliveryNote'), isFalse);
      expect(
        _base(deliveryNote: '   ').toFirestoreMap().containsKey('deliveryNote'),
        isFalse,
      );
    });

    test('is written to the Firestore map (trimmed) when set', () {
      final map = _base(deliveryNote: '  Same-day in Mysore  ').toFirestoreMap();
      expect(map['deliveryNote'], 'Same-day in Mysore');
    });

    test('reads back from the Firestore map', () {
      final p = Product.fromFirestoreMap({
        'id': 'p1',
        'name': 'Oyster Mushroom',
        'description': 'Fresh',
        'category': 'Mushrooms',
        'image': '',
        'variant': 'Fresh',
        'weight': '250 g',
        'price': 120,
        'stock': 10,
        'deliveryNote': ' Next morning only  ',
      });
      expect(p.deliveryNote, 'Next morning only');
    });

    test('is null when the Firestore map omits the key', () {
      final p = Product.fromFirestoreMap({
        'id': 'p1',
        'name': 'Oyster Mushroom',
        'description': 'Fresh',
        'category': 'Mushrooms',
        'image': '',
        'variant': 'Fresh',
        'weight': '250 g',
        'price': 120,
        'stock': 10,
      });
      expect(p.deliveryNote, isNull);
    });

    test('round-trips through toJson/fromJson', () {
      final original = _base(deliveryNote: 'Same day before 6 pm');
      final revived = Product.fromJson(original.toJson());
      expect(revived.deliveryNote, 'Same day before 6 pm');
    });

    test('copyWith sets it', () {
      final p = _base().copyWith(deliveryNote: 'Custom');
      expect(p.deliveryNote, 'Custom');
    });
  });
}
