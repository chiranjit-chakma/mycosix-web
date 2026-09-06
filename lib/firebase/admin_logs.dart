import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/inventory_movement.dart';
import 'fb.dart';

/// Best-effort audit log for every product-stock change an admin makes.
///
/// Movements live in the admin-only `inventoryMovements` collection so the
/// team can see, per product, what changed and who changed it. These records
/// are supplementary  -  a movement-log write is never allowed to fail the
/// stock change it describes, so failures are swallowed (the product write is
/// the authoritative action; Firestore rules still guard both).
Future<void> logStockChange({
  required String productId,
  required String productLabel,
  required InventoryMovementType type,
  required int previousStock,
  required int newStock,
  String? note,
  String? linkedOrderId,
  String? recordedByEmail,
}) async {
  try {
    if (previousStock == newStock) return; // nothing actually changed
    final movement = InventoryMovement(
      id: '',
      productId: productId,
      productName: productLabel,
      movementType: type,
      previousStock: previousStock,
      newStock: newStock,
      note: note,
      linkedOrderId: linkedOrderId,
      recordedByEmail: recordedByEmail,
    );
    final map = movement.toMap();
    map['recordedAt'] = FieldValue.serverTimestamp();
    await Fb.inventoryMovements.add(map);
  } catch (_) {
    // Never let auditing break the real stock write.
  }
}
