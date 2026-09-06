import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/inventory_movement.dart';

void main() {
  test('movement type labels round-trip', () {
    expect(InventoryMovementType.adjustment.label, 'Adjustment');
    expect(InventoryMovementType.sale.label, 'Sale');
    expect(inventoryMovementTypeLabels, ['Adjustment', 'Sale']);
    expect(InventoryMovementType.fromLabel('Sale'), InventoryMovementType.sale);
    expect(InventoryMovementType.fromLabel('??'), InventoryMovementType.adjustment);
    expect(InventoryMovementType.fromLabel(null), InventoryMovementType.adjustment);
  });

  test('delta is newStock minus previousStock (signed)', () {
    final down = InventoryMovement(
      id: '',
      productId: 'p1',
      productName: 'Oyster',
      movementType: InventoryMovementType.sale,
      previousStock: 10,
      newStock: 7,
    );
    expect(down.delta, -3);

    final up = InventoryMovement(
      id: '',
      productId: 'p1',
      productName: 'Oyster',
      movementType: InventoryMovementType.adjustment,
      previousStock: 5,
      newStock: 8,
    );
    expect(up.delta, 3);
  });

  test('round-trips through toMap/fromMap with caller-supplied timestamp', () {
    final original = InventoryMovement(
      id: 'm1',
      productId: 'p1',
      productName: 'Pink Oyster 200g',
      movementType: InventoryMovementType.adjustment,
      previousStock: 6,
      newStock: 4,
      note: 'Two packs broken in transit.',
      recordedByEmail: 'owner@mycosix.in',
    );
    final when = DateTime(2026, 9, 6, 9, 15);
    final restored = InventoryMovement.fromMap(
      original.toMap(),
      id: 'm1',
      recordedAt: when,
    );
    expect(restored.productId, 'p1');
    expect(restored.productName, 'Pink Oyster 200g');
    expect(restored.movementType, InventoryMovementType.adjustment);
    expect(restored.previousStock, 6);
    expect(restored.newStock, 4);
    expect(restored.delta, -2);
    expect(restored.note, 'Two packs broken in transit.');
    expect(restored.recordedAt, when);
    expect(restored.recordedByEmail, 'owner@mycosix.in');
  });

  test('optional fields are omitted from the map when empty', () {
    final m = InventoryMovement(
      id: '',
      productId: 'p2',
      productName: 'Oyster',
      movementType: InventoryMovementType.sale,
      previousStock: 3,
      newStock: 2,
    );
    expect(m.toMap().containsKey('note'), isFalse);
    expect(m.toMap().containsKey('linkedOrderId'), isFalse);
  });

  test('sale movement can carry its linked order id', () {
    final m = InventoryMovement(
      id: '',
      productId: 'p2',
      productName: 'Oyster',
      movementType: InventoryMovementType.sale,
      previousStock: 3,
      newStock: 2,
      linkedOrderId: 'MYC-XYZ00001',
    );
    expect(m.toMap()['linkedOrderId'], 'MYC-XYZ00001');
  });
}
